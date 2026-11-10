`timescale 1 ns / 1 ps
// Таблица 7-сегментного кода десятичной цифры.
// Формат: seg = {g, f, e, d, c, b, a}, 1 — сегмент светится.
module sw_seg_tab (
	input  wire [3:0] digit,
	output reg  [6:0] seg
);

	always @(*) begin
		case (digit)
			4'd0:    seg = 7'b011_1111;
			4'd1:    seg = 7'b000_0110;
			4'd2:    seg = 7'b101_1011;
			4'd3:    seg = 7'b100_1111;
			4'd4:    seg = 7'b110_0110;
			4'd5:    seg = 7'b110_1101;
			4'd6:    seg = 7'b111_1101;
			4'd7:    seg = 7'b000_0111;
			4'd8:    seg = 7'b111_1111;
			4'd9:    seg = 7'b110_1111;
			default: seg = 7'b000_0000;
		endcase
	end

endmodule
