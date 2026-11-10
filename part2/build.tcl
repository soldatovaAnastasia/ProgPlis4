# Сборка проекта части 2 без GUI:
#   C:\Gowin\Gowin_V1.9.10.01_x64\IDE\bin\gw_sh.exe build.tcl
# Запускать из папки, где лежит gw_prj (путь без кириллицы и пробелов).
# Результат: gw_prj/impl/pnr/stopwatch.fs — файл прошивки.

set_device -name GW2A-18C GW2A-LV18PG256C8/I7

add_file gw_prj/src/stopwatch_top.v
add_file gw_prj/src/sw_debounce.v
add_file gw_prj/src/sw_time_counter.v
add_file gw_prj/src/sw_display.v
add_file gw_prj/src/sw_seg_tab.v
add_file gw_prj/src/stopwatch.cst
add_file gw_prj/src/stopwatch.sdc

set_option -top_module stopwatch_top
set_option -output_base_name stopwatch
set_option -verilog_std v2001
# T10 (кнопка S0) — вывод конфигурационного интерфейса SSPI, освобождаем его
set_option -use_sspi_as_gpio 1

run all
