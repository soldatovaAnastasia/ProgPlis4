`timescale 1 ns / 1 ps
// Testbench части 1: модель стенда (два последовательно соединённых сдвиговых
// регистра 74HC595 + 8 разрядов 7-сегментного индикатора) с самопроверкой.
//
// Запуск из корня репозитория:
//   iverilog -o out/top_tb.vvp -c compile_files.txt top_tb.v
//   vvp out/top_tb.vvp
//   gtkwave out/top.vcd
module top_tb;

	// Должны совпадать с параметрами seven_seg_control (схема стенда)
	localparam SEG_BYTE_FIRST = 1;
	localparam SEG_ACTIVE_LOW = 0;
	localparam DIG_ACTIVE_LOW = 1; // PNP-ключи разрядов
	localparam DIG_REVERSE    = 1; // Q0 первого регистра = DIG1 = старший разряд
	localparam LEADING_ZEROS  = 1;

	reg         clk = 1'b0;
	reg  [27:0] display_value = 28'd0;
	wire        ser_data, ser_clk, ser_latch, ready;

	top dut (
		.clk           (clk),
		.display_value (display_value),
		.ser_data      (ser_data),
		.ser_clk       (ser_clk),
		.ser_latch     (ser_latch),
		.ready         (ready)
	);

	always #18.518 clk = ~clk; // 27 МГц

	// ---------------- модель двух 74HC595 ----------------
	// Данные входят в Q0 первого регистра, его Q7 подан на вход второго.
	reg [7:0] sr1 = 8'h00, sr2 = 8'h00;   // сдвиговые части
	reg [7:0] out1 = 8'h00, out2 = 8'h00; // выходные защёлки

	always @(posedge ser_clk) begin
		sr2 <= {sr2[6:0], sr1[7]};
		sr1 <= {sr1[6:0], ser_data};
	end

	always @(posedge ser_latch) begin
		out1 <= sr1;
		out2 <= sr2;
	end

	// Первый переданный байт оказывается во втором (дальнем) регистре
	wire [7:0] seg_raw = SEG_BYTE_FIRST ? out2 : out1;
	wire [7:0] dig_raw = SEG_BYTE_FIRST ? out1 : out2;
	wire [7:0] seg = SEG_ACTIVE_LOW ? ~seg_raw : seg_raw; // {dp,g,f,e,d,c,b,a}, 1 — горит
	wire [7:0] dig = DIG_ACTIVE_LOW ? ~dig_raw : dig_raw; // 1 — разряд включён

	// ---------------- модель индикатора ----------------
	reg [7:0] shown [0:7];  // что светилось на каждом разряде за кадр
	reg [7:0] seen = 8'h00; // какие разряды обновлялись за кадр
	integer   errors = 0;
	integer   frames = 0;
	integer   n_clk  = 0;   // импульсов ser_clk между защёлкиваниями

	always @(posedge ser_clk) n_clk = n_clk + 1;

	function integer dig_index(input [7:0] d);
		integer k;
		begin
			dig_index = -1;
			for (k = 0; k < 8; k = k + 1)
				if (d == (8'h01 << k))
					dig_index = DIG_REVERSE ? 7 - k : k;
		end
	endfunction

	function [3:0] seg2digit(input [7:0] s); // 15 — погашен, 14 — не цифра
		case (s)
			8'h3F: seg2digit = 4'd0;
			8'h06: seg2digit = 4'd1;
			8'h5B: seg2digit = 4'd2;
			8'h4F: seg2digit = 4'd3;
			8'h66: seg2digit = 4'd4;
			8'h6D: seg2digit = 4'd5;
			8'h7D: seg2digit = 4'd6;
			8'h07: seg2digit = 4'd7;
			8'h7F: seg2digit = 4'd8;
			8'h6F: seg2digit = 4'd9;
			8'h00: seg2digit = 4'd15;
			default: seg2digit = 4'd14;
		endcase
	endfunction

	integer idx;
	always @(posedge ser_latch) begin
		#1; // дождаться обновления out1/out2
		if (n_clk != 16) begin
			errors = errors + 1;
			$display("[%0t] ОШИБКА: между защёлкиваниями %0d импульсов ser_clk вместо 16", $time, n_clk);
		end
		n_clk = 0;
		if (^{seg_raw, dig_raw} === 1'bx) begin
			errors = errors + 1;
			$display("[%0t] ОШИБКА: X/Z на выходах регистров", $time);
		end
		idx = dig_index(dig);
		if (idx < 0) begin
			errors = errors + 1;
			$display("[%0t] ОШИБКА: байт выбора разряда %b не one-hot", $time, dig);
		end else begin
			shown[idx] = seg;
			seen[idx]  = 1'b1;
		end
	end

	// ---------------- проверка кадра по импульсу ready ----------------
	reg [27:0] frame_value = 28'd0; // значение, действовавшее в начале кадра
	integer    exp_rest, k, d_exp, d_got;
	reg        nonzero_above;
	real       t_ready;

	always @(posedge ready) begin
		t_ready = $realtime;
		frames  = frames + 1;
		if (seen !== 8'hFF) begin
			errors = errors + 1;
			$display("[%0t] ОШИБКА: за кадр обновлены не все разряды (seen=%b)", $time, seen);
		end
		// разложение на цифры — только в testbench, здесь деление допустимо
		exp_rest = frame_value % 100000000;
		for (k = 0; k < 8; k = k + 1) begin
			d_exp = exp_rest % 10;
			exp_rest = exp_rest / 10;
			nonzero_above = (exp_rest != 0);
			d_got = seg2digit(shown[k]);
			if (!LEADING_ZEROS && k != 0 && d_exp == 0 && !nonzero_above)
				d_exp = 15;
			if (d_got !== d_exp) begin
				errors = errors + 1;
				$display("[%0t] ОШИБКА: значение %0d, разряд %0d: сегменты %b (цифра %0d), ожидалась %0d",
				         $time, frame_value, k, shown[k], d_got, d_exp);
			end
		end
		$display("[%0t] кадр %0d: value=%0d -> %0d%0d%0d%0d%0d%0d%0d%0d", $time, frames, frame_value,
		         seg2digit(shown[7]), seg2digit(shown[6]), seg2digit(shown[5]), seg2digit(shown[4]),
		         seg2digit(shown[3]), seg2digit(shown[2]), seg2digit(shown[1]), seg2digit(shown[0]));
		seen        = 8'h00;
		frame_value = display_value; // следующий кадр должен показать текущее значение целиком
	end

	always @(negedge ready)
		$display("[%0t] длительность ready = %0.1f нс", $time, $realtime - t_ready);

	// ---------------- ход симуляции ----------------
	task wait_frames(input integer n);
		repeat (n) @(posedge ready);
	endtask

	initial begin
		$dumpfile("out/top.vcd");
		$dumpvars(0, top_tb);
	end

	initial begin
		$display("###################################################");
		$display("Start TestBench");

		// display_value задано до первого кадра
		display_value = 28'd12345678;
		frame_value   = display_value;
		wait_frames(2);

		// смена значения в середине кадра: текущий кадр обязан целиком
		// показать старое значение, следующий — целиком новое
		#300_000 display_value = 28'd87654321; wait_frames(2);
		#650_000 display_value = 28'd0;        wait_frames(2);
		#100_000 display_value = 28'd99999999; wait_frames(2);
		#900_000 display_value = 28'd9;        wait_frames(2);
		#450_000 display_value = 28'd10203040; wait_frames(2);
		#777_000 display_value = 28'd50607080; wait_frames(2);
		#123_000 display_value = 28'd35640000; wait_frames(2);

		$display("###################################################");
		if (errors == 0) $display("TEST PASSED: кадров %0d, ошибок нет", frames);
		else             $display("TEST FAILED: ошибок %0d", errors);
		#1000 $finish;
	end

	// защита от зависания
	initial begin
		#100_000_000;
		$display("TEST FAILED: таймаут, импульсы ready не формируются");
		$finish;
	end

endmodule
