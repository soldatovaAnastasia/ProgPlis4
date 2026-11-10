`timescale 1 ns / 1 ps
// Преобразование 28-битного двоичного числа в двоично-десятичный код
// алгоритмом "double dabble" (сдвиг и прибавление 3) — без операции деления.
// Последовательная реализация: один бит входного числа за такт.
//
// 28 бит -> до 268 435 455, т.е. 9 десятичных разрядов. Считаются все 9,
// чтобы младшие 8 разрядов оставались верными и при значениях >= 10^8.
module bin2bcd (
	input  wire        clk,
	input  wire        start,   // импульс в 1 такт: начать преобразование bin
	input  wire [27:0] bin,
	output reg  [35:0] bcd  = 36'd0, // 9 тетрад, [3:0] — единицы
	output reg         done = 1'b1   // 1 — результат в bcd действителен
);

	reg [27:0] shift = 28'd0;
	reg [4:0]  cnt   = 5'd0;

	// Коррекция: каждая тетрада >= 5 увеличивается на 3 перед сдвигом
	reg [35:0] adj;
	integer i;
	always @(*) begin
		adj = bcd;
		for (i = 0; i < 9; i = i + 1)
			if (adj[i*4 +: 4] >= 4'd5)
				adj[i*4 +: 4] = adj[i*4 +: 4] + 4'd3;
	end

	always @(posedge clk) begin
		if (start) begin
			shift <= bin;
			bcd   <= 36'd0;
			cnt   <= 5'd28;
			done  <= 1'b0;
		end else if (!done) begin
			bcd   <= {adj[34:0], shift[27]};
			shift <= {shift[26:0], 1'b0};
			cnt   <= cnt - 5'd1;
			if (cnt == 5'd1)
				done <= 1'b1;
		end
	end

endmodule
