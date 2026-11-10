`timescale 1 ns / 1 ps
// Динамическая индикация 8 разрядов через два 74HC595 стенда (FPGA_Expander).
//
// Схема: данные входят в U3 (Q0..Q7 = DIG1..DIG8, PNP-ключи, активный 0),
// Q7S U3 -> DS U4 (Q0..Q7 = SEG a,b,c,d,e,f,g,dp, NPN-ключи, активная 1).
// Пакет на разряд — 16 бит старшим битом вперёд: {байт сегментов, байт разряда}.
// DIG1 — левый разряд.
//
// Входы digits/dots/blank фиксируются один раз в начале кадра (8 разрядов),
// поэтому новое значение не смешивается со старым в одном кадре.
module sw_display #(
	parameter CLK_DIV = 270 // 27 МГц / 270 = 100 кГц — частота ser_clk
) (
	input  wire        clk,
	input  wire [31:0] digits,  // 8 цифр BCD, [31:28] — левый разряд (DIG1)
	input  wire [7:0]  dots,    // точки, бит 7 — DIG1
	input  wire        blank,   // 1 — все сегменты погашены
	output reg         ser_data   = 1'b0,
	output reg         ser_clk    = 1'b0,
	output reg         ser_latch  = 1'b0,
	output reg         frame_done = 1'b0 // импульс после обновления 8 разрядов
);

	// ---------------- делитель частоты ----------------
	// tick — строб длиной 1 такт с частотой 2 * F(ser_clk)
	localparam HALF = CLK_DIV / 2;

	reg [$clog2(HALF)-1:0] div_cnt = 0;
	reg                    tick    = 1'b0;

	always @(posedge clk) begin
		if (div_cnt == HALF - 1) begin
			div_cnt <= 0;
			tick    <= 1'b1;
		end else begin
			div_cnt <= div_cnt + 1'b1;
			tick    <= 1'b0;
		end
	end

	// ---------------- кадр ----------------
	localparam [2:0]
		S_LOAD  = 3'd0, // фиксация входов
		S_PREP  = 3'd1, // формирование пакета разряда dig
		S_SETUP = 3'd2, // ser_clk = 0, выставить бит
		S_CLOCK = 3'd3, // ser_clk = 1, регистр принимает бит
		S_LATCH = 3'd4, // ser_latch = 1
		S_NEXT  = 3'd5; // ser_latch = 0, следующий разряд

	reg [2:0]  state   = S_LOAD;
	reg [2:0]  dig     = 3'd0;    // 0 — DIG1 (левый) ... 7 — DIG8
	reg [3:0]  bit_cnt = 4'd0;
	reg [15:0] word    = 16'd0;

	reg [31:0] digits_q = 32'd0;  // значения, зафиксированные на кадр
	reg [7:0]  dots_q   = 8'd0;
	reg        blank_q  = 1'b0;

	wire [3:0] cur_digit = digits_q[(3'd7 - dig)*4 +: 4];
	wire       cur_dot   = dots_q[3'd7 - dig];
	wire [6:0] seg_code;

	sw_seg_tab seg_tab_i (
		.digit (cur_digit),
		.seg   (seg_code)
	);

	wire [7:0] seg_byte = blank_q ? 8'h00 : {cur_dot, seg_code}; // бит 7 -> Q7 U4 = dp
	wire [7:0] dig_byte = ~(8'h01 << dig);                        // бит k -> Q k U3 = DIG(k+1)

	always @(posedge clk) begin
		frame_done <= 1'b0;

		if (tick) begin
			case (state)
				S_LOAD: begin
					digits_q <= digits;
					dots_q   <= dots;
					blank_q  <= blank;
					dig      <= 3'd0;
					state    <= S_PREP;
				end

				S_PREP: begin
					word    <= {seg_byte, dig_byte};
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
						frame_done <= 1'b1;
						state      <= S_LOAD;
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
