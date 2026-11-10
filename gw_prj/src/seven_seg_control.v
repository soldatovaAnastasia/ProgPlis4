`timescale 1 ns / 1 ps
// Контроллер динамической индикации на 8 разрядов через два последовательно
// соединённых 8-битных сдвиговых регистра (типа 74HC595).
//
// Один кадр = 8 пакетов по 16 бит (байт сегментов + байт выбора разряда).
// Значение value фиксируется один раз в начале кадра, поэтому при его смене
// данные старого и нового значения в одном кадре не смешиваются.
// После защёлкивания восьмого разряда формируется импульс ready.
//
// Все выходы меняются только по tick (строб делителя частоты):
//   ser_clk  — период 2 tick, данные выставляются при ser_clk = 0,
//              регистр захватывает их по фронту ser_clk;
//   ser_latch — импульс длиной 1 tick после 16-го бита.
module seven_seg_control #(
	// --- Параметры, зависящие от схемы стенда (FPGA_Expander) ---
	// Данные входят в U3 (Q0..Q7 = DIG1..DIG8), его Q7S подан на U4
	// (Q0..Q7 = SEG1..SEG8 = a,b,c,d,e,f,g,dp). Первый переданный байт
	// оказывается в U4, поэтому сначала идёт байт сегментов.
	// Разряды включаются PNP-ключами (активный 0), сегменты — NPN (активная 1).
	// DIG1 — левый (старший) разряд, DIG8 — правый (единицы).
	parameter SEG_BYTE_FIRST = 1, // 1: первым передаётся байт сегментов, 0: байт выбора разряда
	parameter MSB_FIRST      = 1, // 1: байт передаётся старшим битом вперёд (бит 7 -> Q7)
	parameter SEG_ACTIVE_LOW = 0, // 1: сегмент светится при 0 на выходе регистра
	parameter DIG_ACTIVE_LOW = 1, // 1: разряд выбран при 0 на выходе регистра
	parameter DIG_REVERSE    = 1, // 0: бит i байта выбора — разряд i (0 — младший, единицы)
	                              // 1: бит 7-i
	parameter LEADING_ZEROS  = 1  // 1: показывать ведущие нули, 0: гасить их
) (
	input  wire        clk,
	input  wire        tick,
	input  wire [27:0] value,
	output reg         ser_data  = 1'b0,
	output reg         ser_clk   = 1'b0,
	output reg         ser_latch = 1'b0,
	output reg         ready     = 1'b0
);

	localparam [2:0]
		S_LOAD  = 3'd0, // фиксация value, запуск преобразования в BCD
		S_CONV  = 3'd1, // ожидание конца преобразования
		S_PREP  = 3'd2, // формирование 16-битного пакета для разряда dig
		S_SETUP = 3'd3, // ser_clk = 0, выставить бит данных
		S_CLOCK = 3'd4, // ser_clk = 1, регистр принимает бит
		S_LATCH = 3'd5, // ser_latch = 1
		S_NEXT  = 3'd6; // ser_latch = 0, переход к следующему разряду

	reg [2:0]  state   = S_LOAD;
	reg [2:0]  dig     = 3'd0;
	reg [3:0]  bit_cnt = 4'd0;
	reg [15:0] word    = 16'd0;
	reg [31:0] digits  = 32'd0; // 8 тетрад BCD текущего кадра

	// ---------------- двоичное -> BCD ----------------
	reg         conv_start = 1'b0;
	wire [35:0] bcd;
	wire        conv_done;

	bin2bcd bin2bcd_i (
		.clk   (clk),
		.start (conv_start),
		.bin   (value),
		.bcd   (bcd),
		.done  (conv_done)
	);

	// ---------------- пакет для текущего разряда ----------------
	wire [3:0] cur_digit = digits[dig*4 +: 4];
	wire [7:0] seg_code;

	seven_seg_tab seven_seg_tab_i (
		.digit (cur_digit),
		.seg   (seg_code)
	);

	// Ведущий ноль: все более старшие тетрады и сама текущая равны нулю
	// (младший разряд показывается всегда).
	wire [31:0] upper       = digits >> {dig, 2'b00};
	wire        leading_0   = (upper == 32'd0) && (dig != 3'd0);
	wire        blank       = (LEADING_ZEROS == 0) && leading_0;

	wire [7:0] seg_on   = blank ? 8'h00 : seg_code;
	wire [7:0] dig_on   = 8'h01 << (DIG_REVERSE ? (3'd7 - dig) : dig);
	wire [7:0] seg_lvl  = SEG_ACTIVE_LOW ? ~seg_on : seg_on;
	wire [7:0] dig_lvl  = DIG_ACTIVE_LOW ? ~dig_on : dig_on;

	function [7:0] bit_order(input [7:0] b);
		integer k;
		begin
			for (k = 0; k < 8; k = k + 1)
				bit_order[k] = MSB_FIRST ? b[k] : b[7-k];
		end
	endfunction

	// word[15] передаётся первым
	wire [15:0] word_next = SEG_BYTE_FIRST ? {bit_order(seg_lvl), bit_order(dig_lvl)}
	                                       : {bit_order(dig_lvl), bit_order(seg_lvl)};

	// ---------------- автомат ----------------
	always @(posedge clk) begin
		conv_start <= 1'b0;

		if (tick) begin
			case (state)
				S_LOAD: begin
					ready      <= 1'b0;
					conv_start <= 1'b1; // bin2bcd захватит value на следующем такте
					state      <= S_CONV;
				end

				S_CONV: begin
					if (!conv_start && conv_done) begin
						digits <= bcd[31:0];
						dig    <= 3'd0;
						state  <= S_PREP;
					end
				end

				S_PREP: begin
					word    <= word_next;
					bit_cnt <= 4'd0;
					state   <= S_SETUP;
				end

				S_SETUP: begin
					ser_clk  <= 1'b0;
					ser_data <= word[15];
					state    <= S_CLOCK;
				end

				S_CLOCK: begin
					ser_clk <= 1'b1;
					word    <= {word[14:0], 1'b0};
					bit_cnt <= bit_cnt + 4'd1;
					state   <= (bit_cnt == 4'd15) ? S_LATCH : S_SETUP;
				end

				S_LATCH: begin
					ser_clk   <= 1'b0;
					ser_latch <= 1'b1;
					state     <= S_NEXT;
				end

				S_NEXT: begin
					ser_latch <= 1'b0;
					if (dig == 3'd7) begin
						ready <= 1'b1; // все 8 разрядов обновлены
						state <= S_LOAD;
					end else begin
						dig   <= dig + 3'd1;
						state <= S_PREP;
					end
				end

				default: state <= S_LOAD;
			endcase
		end
	end

endmodule
