@echo off
setlocal enabledelayedexpansion

:: ==============================================================================
:: ARGUMENTS CHECK
:: ==============================================================================
if "%~3"=="" (
    echo [ERROR] Missing arguments.
    echo Usage: %~nx0 ^<PROJECT_NAME^> ^<COMP_VERSION^> ^<COMP_NAME^> [STATUS]
    exit /b 1
)

set "PRJ_NAME=%~1"
set "COMP_VER=%~2"
set "COMP_NAME=%~3"
set "STATUS=%~4"

:: Resolve absolute project root directory (parent of scripts\)
for %%I in ("%~dp0..") do set "ROOT_DIR=%%~fI"

:: ==============================================================================
:: PATH DEFINITIONS
:: ==============================================================================
set "SRC_BUILD=%ROOT_DIR%\build\%PRJ_NAME%\%COMP_VER%"
set "SRC_HLS=%ROOT_DIR%\projects\%PRJ_NAME%\%COMP_VER%\%COMP_VER%_script"
set "DST_BASE=%ROOT_DIR%\reports\%PRJ_NAME%\%COMP_VER%"

echo [INFO] Starting report aggregation for:
echo        Project:   %PRJ_NAME%
echo        Version:   %COMP_VER%
echo        Component: %COMP_NAME%
if /i "%STATUS%"=="FAILURE" (
    echo        Mode:      Partial Export (Muting missing file warnings)
)
echo.

:: ==============================================================================
:: HLS FILE AGGREGATION
:: ==============================================================================

:: hls/csim
call :COPY_FILE "%SRC_HLS%\logs\hls_run_csim.log" "%DST_BASE%\hls\csim"
call :COPY_FILE "%SRC_HLS%\hls\csim\report\%COMP_NAME%_csim.log" "%DST_BASE%\hls\csim"

:: hls/sim
call :COPY_FILE "%SRC_HLS%\logs\hls_run_cosim.log" "%DST_BASE%\hls\sim"
call :COPY_FILE "%SRC_HLS%\reports\hls_cosim.rpt" "%DST_BASE%\hls\sim"
call :COPY_FILE "%SRC_HLS%\hls\sim\report\%COMP_NAME%_cosim.rpt" "%DST_BASE%\hls\sim"

:: hls/sim/waveform
call :COPY_FILE "%SRC_HLS%\hls\sim\verilog\%COMP_NAME%.wcfg" "%DST_BASE%\hls\sim\waveform"
call :COPY_FILE "%SRC_HLS%\hls\sim\verilog\%COMP_NAME%.wdb" "%DST_BASE%\hls\sim\waveform"
call :COPY_FILE "%SRC_HLS%\hls\sim\verilog\%COMP_NAME%_dataflow_ana.wcfg" "%DST_BASE%\hls\sim\waveform"

:: hls/syn
call :COPY_FILE "%SRC_HLS%\hls\syn\report\csynth.rpt" "%DST_BASE%\hls\syn"
call :COPY_FILE "%SRC_HLS%\hls\syn\report\csynth_design_size.rpt" "%DST_BASE%\hls\syn"
call :COPY_FILE "%SRC_HLS%\logs\hls_compile.log" "%DST_BASE%\hls\syn"
call :COPY_FILE "%SRC_HLS%\reports\hls_compile.rpt" "%DST_BASE%\hls\syn"
call :COPY_FILE "%SRC_HLS%\hls\syn\report\%COMP_NAME%_csynth.rpt" "%DST_BASE%\hls\syn"

:: hls/impl & hls root
call :COPY_FILE "%SRC_HLS%\logs\hls_run_package.log" "%DST_BASE%\hls\impl"
call :COPY_FILE "%SRC_HLS%\logs\%COMP_VER%_script.steps.log" "%DST_BASE%\hls"

:: ==============================================================================
:: VIVADO FILE AGGREGATION
:: ==============================================================================

:: vivado root
call :COPY_FILE "%SRC_BUILD%\vivado.log" "%DST_BASE%\vivado"

:: vivado/synth_ooc
call :COPY_FILE "%SRC_BUILD%\vivado_prj\vivado_prj.runs\%COMP_NAME%_0_synth_1\%COMP_NAME%_0_utilization_synth.rpt" "%DST_BASE%\vivado\synth_ooc"
call :COPY_FILE "%SRC_BUILD%\vivado_prj\vivado_prj.runs\%COMP_NAME%_0_synth_1\runme.log" "%DST_BASE%\vivado\synth_ooc"

:: vivado/synth
call :COPY_FILE "%SRC_BUILD%\vivado_prj\vivado_prj.runs\synth_1\%COMP_NAME%_0_sv_utilization_synth.rpt" "%DST_BASE%\vivado\synth"
call :COPY_FILE "%SRC_BUILD%\vivado_prj\vivado_prj.runs\synth_1\runme.log" "%DST_BASE%\vivado\synth"

:: vivado/sim/post-synth_timing
call :COPY_FILE "%SRC_BUILD%\vivado_prj\vivado_prj.sim\sim_1\synth\timing\xsim\%COMP_NAME%_tb_time_synth.wdb" "%DST_BASE%\vivado\sim\post-synth_timing"
call :COPY_FILE "%SRC_BUILD%\vivado_prj\vivado_prj.sim\sim_1\synth\timing\xsim\simulate.log" "%DST_BASE%\vivado\sim\post-synth_timing"

echo.
echo [INFO] File aggregation completed.
exit /b 0

:: ==============================================================================
:: SUBROUTINES
:: ==============================================================================
:COPY_FILE
set "SRC_FILE=%~1"
set "DST_DIR=%~2"

:: Create destination directory if it does not exist
if not exist "%DST_DIR%" (
    mkdir "%DST_DIR%"
)

:: Perform copy and handle standard output
if exist "%SRC_FILE%" (
    copy /Y "%SRC_FILE%" "%DST_DIR%" >nul
    echo   [OK] Copied: %SRC_FILE%
) else (
    if /i not "%STATUS%"=="FAILURE" (
        echo   [WARNING] File not found: %SRC_FILE%
    )
)
exit /b 0
