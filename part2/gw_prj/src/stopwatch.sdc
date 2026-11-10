//File Title: Timing Constraints file
//Кварцевый генератор 27 МГц
create_clock -name clk -period 37.037 -waveform {0 18.518} [get_ports {clk}]
