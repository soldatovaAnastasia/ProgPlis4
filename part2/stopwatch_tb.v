`timescale 1 ns / 1 ps
// Testbench части 2 (секундомер) с моделью стенда и самопроверкой.
//
// Для симуляции время ускорено: период изменения 20 000 тактов (~0.74 мс)
// вместо 4 с, подавление дребезга 200 тактов вместо 20 мс. Начальное значение
// взято рядом с порогом (09:53:59.980), чтобы увидеть включение светодиода.
//
// Запуск из папки part2:
//   iverilog -o out/stopwatch_tb.vvp -c compile_files.txt stopwatch_tb.v
//   vvp out/stopwatch_tb.vvp
//   gtkwave out/stopwatch.vcd stopwatch.gtkw
module stopwatch_tb;

	localparam PERIOD_CLK = 20_000;
	localparam STEP_MS    = 4;
	localparam [35:0] INIT_BCD = 36'h0_9_5_3_5_9_9_8_0; // 09:53:59.980
	localparam integer THRESHOLD_MS = 35_640_000;

	reg  clk = 1'b0;
	reg  btn_s0 = 1'b1, btn_s1 = 1'b1, btn_s2 = 1'b1; // не нажаты
	wire ser_data, ser_clk, ser_latch, led_n;

	stopwatch_top #(
		.PERIOD_CLK   (PERIOD_CLK),
		.STEP_MS      (STEP_MS),
		.DEBOUNCE_CLK (200),
		.INIT_BCD     (INIT_BCD)
	) dut (
		.clk       (clk),
		.btn_s0    (btn_s0),
		.btn_s1    (btn_s1),
		.btn_s2    (btn_s2),
		.ser_data  (ser_data),
		.ser_clk   (ser_clk),
		.ser_latch (ser_latch),
		.led_n     (led_n)
	);

	always #18.518 clk = ~clk; // 27 МГц

	// ---------------- модель двух 74HC595 и индикатора ----------------
	reg [7:0] sr1 = 0, sr2 = 0, q_dig = 8'hFF, q_seg = 0;

	always @(posedge ser_clk) begin
		sr2 <= {sr2[6:0], sr1[7]};
		sr1 <= {sr1[6:0], ser_data};
	end
	always @(posedge ser_latch) begin
		q_dig <= sr1; // U3: DIG1..DIG8, активный 0
		q_seg <= sr2; // U4: a..g, dp, активная 1
	end

	reg [7:0] shown [0:7]; // сегменты каждого разряда за кадр, индекс 0 — DIG1
	integer k, errors = 0, frames = 0;

	always @(posedge ser_latch) begin
		#1;
		for (k = 0; k < 8; k = k + 1)
			if (q_dig == ~(8'h01 << k)) shown[k] = q_seg;
	end

	function [7:0] seg2chr(input [6:0] s);
		case (s)
			7'h3F: seg2chr = "0"; 7'h06: seg2chr = "1"; 7'h5B: seg2chr = "2";
			7'h4F: seg2chr = "3"; 7'h66: seg2chr = "4"; 7'h6D: seg2chr = "5";
			7'h7D: seg2chr = "6"; 7'h07: seg2chr = "7"; 7'h7F: seg2chr = "8";
			7'h6F: seg2chr = "9"; 7'h00: seg2chr = " ";
			default: seg2chr = "?";
		endcase
	endfunction

	function [6:0] dig2seg(input [3:0] d);
		case (d)
			0: dig2seg = 7'h3F; 1: dig2seg = 7'h06; 2: dig2seg = 7'h5B; 3: dig2seg = 7'h4F;
			4: dig2seg = 7'h66; 5: dig2seg = 7'h6D; 6: dig2seg = 7'h7D; 7: dig2seg = 7'h07;
			8: dig2seg = 7'h7F; 9: dig2seg = 7'h6F; default: dig2seg = 7'h00;
		endcase
	endfunction

	// Что показывает индикатор — строка для GTKWave (формат ASCII) и лога
	reg [8*12-1:0] disp_txt = "";
	reg [8*12-1:0] txt;
	reg [7:0] exp_seg;

	// значение счётчика в миллисекундах (в testbench умножение допустимо)
	function integer bcd2ms(input [35:0] v);
		bcd2ms = ((v[35:32]*10 + v[31:28]) * 3600 + (v[27:24]*10 + v[23:20]) * 60
		         + v[19:16]*10 + v[15:12]) * 1000 + v[11:8]*100 + v[7:4]*10 + v[3:0];
	endfunction

	integer value_ms;
	always @(*) value_ms = bcd2ms(dut.t);

	// Проверка каждого кадра: показано ровно то, что зафиксировал контроллер
	always @(posedge dut.frame_done) begin
		#1;
		frames = frames + 1;
		txt = "";
		for (k = 0; k < 8; k = k + 1) begin
			exp_seg = dut.disp.blank_q ? 8'h00
			        : {dut.disp.dots_q[7-k], dig2seg(dut.disp.digits_q[(7-k)*4 +: 4])};
			if (shown[k] !== exp_seg) begin
				errors = errors + 1;
				$display("[%0t] ОШИБКА: разряд DIG%0d показывает %b, ожидалось %b",
				         $time, k + 1, shown[k], exp_seg);
			end
			txt = {txt[8*11-1:0], seg2chr(shown[k][6:0])};
			if (shown[k][7]) txt = {txt[8*11-1:0], "."};
		end
		disp_txt = txt;
		if (led_n !== !(value_ms >= THRESHOLD_MS)) begin
			errors = errors + 1;
			$display("[%0t] ОШИБКА: led_n=%b при значении %0d мс", $time, led_n, value_ms);
		end
		$write("[%0t] кадр %0d: [%s]  значение %0d мс  ", $time, frames, disp_txt, value_ms);
		if (led_n) $display("LED выкл");
		else       $display("LED ВКЛ");
	end

	// ---------------- нажатие с дребезгом ----------------
	task press(input integer which);
		integer i;
		begin
			for (i = 0; i < 6; i = i + 1) begin // дребезг при нажатии
				set_btn(which, i[0]);
				#(400 + i * 300);
			end
			set_btn(which, 1'b0);
			#60_000;                            // удержание 60 мкс
			for (i = 0; i < 6; i = i + 1) begin // дребезг при отпускании
				set_btn(which, ~i[0]);
				#(500 + i * 200);
			end
			set_btn(which, 1'b1);
		end
	endtask

	task set_btn(input integer which, input v);
		case (which)
			0: btn_s0 = v;
			1: btn_s1 = v;
			2: btn_s2 = v;
		endcase
	endtask

	// синхронизация с серединой периода счётчика — отсчёты не попадают на изменение
	task mid_period;
		begin
			@(posedge clk);
			while (dut.counter.per_cnt != PERIOD_CLK / 2) @(posedge clk);
		end
	endtask

	// пауза длиной n периодов — работает и когда счётчик периода остановлен
	task wait_periods(input integer n);
		repeat (n * PERIOD_CLK) @(posedge clk);
	endtask

	// Текст проверки идёт прямо в формат $display: строки с кириллицей,
	// сохранённые в переменную, iverilog печатает некорректно.
	`define CHECK(cond, msg) \
		begin \
			if (cond) $write("[%0t] OK: ", $time); \
			else begin errors = errors + 1; $write("[%0t] ОШИБКА: ", $time); end \
			$display(msg); \
		end

	integer v0, v1;

	initial begin
		$dumpfile("out/stopwatch.vcd");
		$dumpvars(0, stopwatch_tb);
	end

	initial begin
		$display("###################################################");
		$display("Start TestBench: секундомер");

		#1;
		`CHECK(value_ms == bcd2ms(INIT_BCD), "после включения — начальное значение");

		// 1. Счёт: за 5 периодов +20 мс, светодиод включается на пороге
		mid_period; v0 = value_ms;
		repeat (5) mid_period; v1 = value_ms;
		`CHECK(v1 - v0 == 5 * STEP_MS, "за 5 периодов значение выросло на 20 мс");
		`CHECK(led_n == 1'b0 && v1 >= THRESHOLD_MS, "значение >= 35640000 мс, светодиод горит");

		// 2. S1 — остановка
		press(1);
		#1000; v0 = value_ms;
		wait_periods(3); v1 = value_ms;
		`CHECK(v1 == v0, "S1: счёт остановлен");

		// 3. S1 — продолжение
		press(1);
		mid_period; v0 = value_ms;
		repeat (3) mid_period; v1 = value_ms;
		`CHECK(v1 - v0 == 3 * STEP_MS, "S1 повторно: счёт продолжается");

		// 4. S0 — выключение дисплея (счёт при этом идёт)
		press(0);
		repeat (2) @(posedge dut.frame_done); #10;
		`CHECK(disp_txt == "        ", "S0: дисплей погашен");
		`CHECK(dut.running == 1'b1, "S0: счёт при выключенном дисплее продолжается");

		// 5. S0 — включение
		press(0);
		repeat (2) @(posedge dut.frame_done); #10;
		`CHECK(disp_txt != "        ", "S0 повторно: дисплей включён");

		// 6. S2 — сброс в начальное состояние
		press(1); // остановим, чтобы проверить, что S2 возвращает и режим счёта
		press(2);
		#1000;
		`CHECK(value_ms == bcd2ms(INIT_BCD) && dut.running && dut.disp_on,
		      "S2: начальное значение, счёт идёт, дисплей включён");
		repeat (2) @(posedge dut.frame_done); #10;
		`CHECK(led_n == 1'b1, "S2: значение ниже порога, светодиод погас");

		repeat (2) mid_period;

		$display("###################################################");
		if (errors == 0) $display("TEST PASSED: кадров %0d, ошибок нет", frames);
		else             $display("TEST FAILED: ошибок %0d", errors);
		$finish;
	end

	initial begin
		#200_000_000;
		$display("TEST FAILED: таймаут");
		$finish;
	end

endmodule
