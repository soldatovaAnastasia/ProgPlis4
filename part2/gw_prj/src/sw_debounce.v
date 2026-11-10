`timescale 1 ns / 1 ps
// Подавление дребезга механической кнопки.
// Вход синхронизируется двумя триггерами, затем новое состояние принимается
// только если оно держится STABLE_CLK тактов подряд. При переходе в
// "нажато" выдаётся импульс pressed длиной 1 такт — одно нажатие даёт
// ровно один импульс, сколько бы раз контакт ни "дребезжал".
module sw_debounce #(
	parameter STABLE_CLK = 540_000, // 20 мс при 27 МГц
	parameter ACTIVE_LOW = 1        // 1: нажатая кнопка даёт 0 (кнопки Dock)
) (
	input  wire clk,
	input  wire btn_raw,
	output reg  pressed = 1'b0
);

	localparam IDLE = ACTIVE_LOW ? 1'b1 : 1'b0;

	reg s1 = IDLE, s2 = IDLE;  // синхронизатор
	reg stable = IDLE;         // принятое (отфильтрованное) состояние
	reg [$clog2(STABLE_CLK + 1)-1:0] cnt = 0;

	always @(posedge clk) begin
		s1      <= btn_raw;
		s2      <= s1;
		pressed <= 1'b0;

		if (s2 == stable) begin
			cnt <= 0;                      // дребезг или покой — счёт заново
		end else if (cnt == STABLE_CLK - 1) begin
			cnt    <= 0;
			stable <= s2;
			if (s2 != IDLE)
				pressed <= 1'b1;           // фронт нажатия
		end else begin
			cnt <= cnt + 1'b1;
		end
	end

endmodule
