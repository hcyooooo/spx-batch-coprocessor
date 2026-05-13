@echo off
setlocal

set TOP=spx_thashx4_core
set PART=xc7a35tcpg236-1
set CLOCK_PERIOD_NS=10.0

if not "%~1"=="" set TOP=%~1
if not "%~2"=="" set PART=%~2
if not "%~3"=="" set CLOCK_PERIOD_NS=%~3

vivado -mode batch -source "%~dp0synth_vivado.tcl" -tclargs %TOP% %PART% %CLOCK_PERIOD_NS%

endlocal
