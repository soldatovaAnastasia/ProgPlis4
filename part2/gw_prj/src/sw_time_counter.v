`timescale 1 ns / 1 ps
// Счётчик секундомера в формате ЧЧ:ММ:СС.мсмсмс, хранится сразу в
// двоично-десятичном коде — для вывода не нужно ни деление, ни
// преобразование двоичного числа в десятичное.
//
// t = {h1, h0, m1, m0, s1, s0, ms2, ms1, ms0}, по 4 бита на цифру.
//
// Каждые PERIOD_CLK тактов (если run = 1) значение увеличивается на STEP_MS
// миллисекунд: STEP_MS раз подряд прибавляется 1 мс (по одному такту).
module sw_time_counter #(
	parameter PERIOD_CLK = 108_000_000, // 4 с при 27 МГц
	parameter STEP_MS    = 4,
	parameter [35:0] INIT_BCD = 36'h0   // начальное значение
) (
	input  wire        clk,
	input  wire        run,    // 1 — счёт идёт
	input  wire        clear,  // возврат к начальному значению
	output reg  [35:0] t = INIT_BCD
);

	reg [$clog2(PERIOD_CLK)-1:0]  per_cnt = 0;
	reg [$clog2(STEP_MS + 1)-1:0] pending = 0; // сколько ещё миллисекунд прибавить

	// +1 мс с переносами; предел разряда: 5 для десятков секунд и минут, иначе 9.
	// Переполнение 99:59:59.999 -> 00:00:00.000.
	function [35:0] bcd_inc(input [35:0] v);
		integer i;
		reg     carry;
		reg [3:0] lim;
		begin
			bcd_inc = v;
			carry   = 1'b1;
			for (i = 0; i < 9; i = i + 1) begin
				lim = (i == 4 || i == 6) ? 4'd5 : 4'd9;
				if (carry) begin
					if (v[i*4 +: 4] >= lim) begin
						bcd_inc[i*4 +: 4] = 4'd0;
					end else begin
						bcd_inc[i*4 +: 4] = v[i*4 +: 4] + 4'd1;
						carry = 1'b0;
					end
				end
			end
		end
	endfunction

	always @(posedge clk) begin
		if (clear) begin
			t       <= INIT_BCD;
			per_cnt <= 0;
			pending <= 0;
		end else begin
			if (run) begin
				if (per_cnt == PERIOD_CLK - 1) begin
					per_cnt <= 0;
					pending <= STEP_MS;
				end else begin
					per_cnt <= per_cnt + 1'b1;
				end
			end
			if (pending != 0) begin
				t       <= bcd_inc(t);
				pending <= pending - 1'b1;
			end
		end
	end

endmodule
