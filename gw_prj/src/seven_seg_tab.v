`timescale 1 ns / 1 ps
// Таблица 7-сегментного кода десятичной цифры.
// Формат: seg = {dp, g, f, e, d, c, b, a}, 1 — сегмент светится.
// Точка (бит 7) здесь всегда погашена.
module seven_seg_tab (
	input  wire [3:0] digit,
	output reg  [7:0] seg
);

	always @(*) begin
		case (digit)
			4'd0:    seg = 8'b0011_1111;
			4'd1:    seg = 8'b0000_0110;
			4'd2:    seg = 8'b0101_1011;
			4'd3:    seg = 8'b0100_1111;
			4'd4:    seg = 8'b0110_0110;
			4'd5:    seg = 8'b0110_1101;
			4'd6:    seg = 8'b0111_1101;
			4'd7:    seg = 8'b0000_0111;
			4'd8:    seg = 8'b0111_1111;
			4'd9:    seg = 8'b0110_1111;
			default: seg = 8'b0000_0000; // не цифра — разряд погашен
		endcase
	end

endmodule
