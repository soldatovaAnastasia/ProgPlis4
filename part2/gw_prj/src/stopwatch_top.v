`timescale 1 ns / 1 ps
// Лабораторная работа №4, часть 2. Вариант: STOPWATCH.
//
//  - секундомер, каждые 4 с значение увеличивается на 4 мс;
//  - вывод в формате HH.MM.SS.mSmS (DECIMAL_ZERO — ведущие нули показываются),
//    mSmS — сотни и десятки миллисекунд;
//  - светодиод горит, когда значение >= 35 640 000 мс (= 09:54:00.000);
//  - S0 — выключение / включение дисплея;
//  - S1 — остановка / продолжение счёта;
//  - S2 — сброс в начальное состояние.
//
// Деление нигде не используется: время хранится сразу в BCD.
module stopwatch_top #(
	parameter PERIOD_CLK   = 108_000_000,  // период изменения: 4 с * 27 МГц
	parameter STEP_MS      = 4,            // шаг изменения, мс
	parameter DEBOUNCE_CLK = 540_000,      // 20 мс — время подавления дребезга
	parameter CLK_DIV      = 270,          // 27 МГц -> 100 кГц для 74HC595
	// {h1,h0,m1,m0,s1,s0,ms2,ms1,ms0}
	parameter [35:0] INIT_BCD      = 36'h0_0_0_0_0_0_0_0_0, // начальное значение
	parameter [35:0] THRESHOLD_BCD = 36'h0_9_5_4_0_0_0_0_0  // 35 640 000 мс = 09:54:00.000
) (
	input  wire clk,        // 27 МГц
	input  wire btn_s0,     // кнопки Dock, нажатие = 0
	input  wire btn_s1,
	input  wire btn_s2,
	output wire ser_data,   // 74HC595: DS
	output wire ser_clk,    //          SHCP
	output wire ser_latch,  //          STCP
	output reg  led_n = 1'b1 // светодиод Dock, горит при 0
);

	// ---------------- кнопки ----------------
	wire p_s0, p_s1, p_s2;

	sw_debounce #(.STABLE_CLK(DEBOUNCE_CLK)) db_s0 (.clk(clk), .btn_raw(btn_s0), .pressed(p_s0));
	sw_debounce #(.STABLE_CLK(DEBOUNCE_CLK)) db_s1 (.clk(clk), .btn_raw(btn_s1), .pressed(p_s1));
	sw_debounce #(.STABLE_CLK(DEBOUNCE_CLK)) db_s2 (.clk(clk), .btn_raw(btn_s2), .pressed(p_s2));

	// ---------------- состояние устройства ----------------
	reg disp_on = 1'b1;
	reg running = 1'b1;

	always @(posedge clk) begin
		if (p_s2) begin            // сброс — начальное состояние целиком
			disp_on <= 1'b1;
			running <= 1'b1;
		end else begin
			if (p_s0) disp_on <= ~disp_on;
			if (p_s1) running <= ~running;
		end
	end

	// ---------------- счётчик времени ----------------
	wire [35:0] t;

	sw_time_counter #(
		.PERIOD_CLK (PERIOD_CLK),
		.STEP_MS    (STEP_MS),
		.INIT_BCD   (INIT_BCD)
	) counter (
		.clk   (clk),
		.run   (running),
		.clear (p_s2),
		.t     (t)
	);

	// ---------------- светодиод ----------------
	// Цифры BCD сравниваются как обычное число: старшие тетрады — старшие разряды.
	always @(posedge clk)
		led_n <= ~(t >= THRESHOLD_BCD);

	// ---------------- индикация ----------------
	// HH.MM.SS.mSmS: отбрасывается единица миллисекунд, точки после HH, MM, SS
	wire frame_done;

	sw_display #(.CLK_DIV(CLK_DIV)) disp (
		.clk        (clk),
		.digits     (t[35:4]),
		.dots       (8'b0101_0100),
		.blank      (~disp_on),
		.ser_data   (ser_data),
		.ser_clk    (ser_clk),
		.ser_latch  (ser_latch),
		.frame_done (frame_done)
	);

endmodule
