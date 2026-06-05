@echo off
setlocal enabledelayedexpansion

:: ==============================================================================
:: ARGUMENTS CHECK
:: ==============================================================================
if "%~3"=="" (
    echo [ERROR] Missing arguments.
    echo Usage: %~nx0 ^<PROJECT_NAME^> ^<COMP_VERSION^> ^<COMP_NAME^> [STATUS] [WORKFLOW]
    exit /b 1
)

set "PRJ_NAME=%~1"
set "COMP_VER=%~2"
set "COMP_NAME=%~3"
set "STATUS=%~4"
set "WORKFLOW=%~5"

:: Default workflow is power if not specified
if "%WORKFLOW%"=="" set "WORKFLOW=power"

:: Resolve absolute project root directory (parent of scripts\)
for %%I in ("%~dp0..") do set "ROOT_DIR=%%~fI"

:: ==============================================================================
:: PATH DEFINITIONS
::
:: power workflow:
::   SRC_HLS   = projects\<PRJ>\<COMP_VER>\<COMP_VER>_script
::   SRC_BUILD = build\<PRJ>\<COMP_VER>
::   DST_BASE  = reports\<PRJ>\<COMP_VER>
::
:: clk workflow:
::   COMP_VER is the full report subdir, e.g. fir_baseline_clk-10ns.
::   The HLS work dir lives inside the base component folder, derived by
::   stripping the "_clk-<value>" suffix from COMP_VER.
::   SRC_HLS   = projects\<PRJ>\<BASE_VER>\<COMP_VER>_script
::   SRC_BUILD = (unused)
::   DST_BASE  = reports\<PRJ>\<COMP_VER>
:: ==============================================================================
if /i "%WORKFLOW%"=="clk" (
    :: Derive BASE_VER by stripping "_clk-<value>" suffix from COMP_VER.
    :: Replace the first "_clk-" with "=" then extract the left token.
    :: Example: fir_baseline_clk-10ns -> BASE_VER=fir_baseline
    set "_TMP=!COMP_VER:_clk-==!"
    for /f "tokens=1 delims==" %%A in ("!_TMP!") do set "BASE_VER=%%A"
    for /f "tokens=2 delims==" %%A in ("!_TMP!") do set "CLK_VAL=%%A"

    set "SRC_HLS=!ROOT_DIR!\projects\!PRJ_NAME!\!BASE_VER!\!COMP_VER!_script"
    set "SRC_BUILD="
    set "DST_BASE=%ROOT_DIR%\reports\%PRJ_NAME%\!BASE_VER!_clk\!CLK_VAL!"
) else (
    set "SRC_HLS=%ROOT_DIR%\projects\%PRJ_NAME%\%COMP_VER%\%COMP_VER%_script"
    set "SRC_BUILD=%ROOT_DIR%\build\%PRJ_NAME%\%COMP_VER%"
    set "DST_BASE=%ROOT_DIR%\reports\%PRJ_NAME%\%COMP_VER%"
)


echo [INFO] Starting report aggregation for:
echo        Project:   %PRJ_NAME%
echo        Version:   %COMP_VER%
echo        Component: %COMP_NAME%
echo        Workflow:  %WORKFLOW%
if /i "%STATUS%"=="FAILURE" (
    echo        Mode:      Partial Export ^(Muting missing file warnings^)
)
echo.

:: ==============================================================================
:: HLS FILE AGGREGATION
:: ==============================================================================

if /i not "%WORKFLOW%"=="clk" (
    :: hls/csim (power workflow only -- C simulation step not run in clk workflow)
    call :COPY_FILE "%SRC_HLS%\logs\hls_run_csim.log" "%DST_BASE%\hls\csim"
    call :COPY_FILE "%SRC_HLS%\hls\csim\report\%COMP_NAME%_csim.log" "%DST_BASE%\hls\csim"

    :: hls/sim (power workflow only -- cosim step not run in clk workflow)
    call :COPY_FILE "%SRC_HLS%\logs\hls_run_cosim.log" "%DST_BASE%\hls\sim"
    call :COPY_FILE "%SRC_HLS%\hls\sim\report\%COMP_NAME%_cosim.rpt" "%DST_BASE%\hls\sim"

    :: hls/sim/waveform (power workflow only -- waveform step not run in clk workflow)
    call :COPY_FILE "%SRC_HLS%\hls\sim\verilog\%COMP_NAME%.wcfg" "%DST_BASE%\hls\sim\waveform"
    call :COPY_FILE "%SRC_HLS%\hls\sim\verilog\%COMP_NAME%.wdb" "%DST_BASE%\hls\sim\waveform"
    call :COPY_FILE "%SRC_HLS%\hls\sim\verilog\%COMP_NAME%_dataflow_ana.wcfg" "%DST_BASE%\hls\sim\waveform"
)

:: hls/syn
call :COPY_FILE "%SRC_HLS%\hls\syn\report\csynth.rpt" "%DST_BASE%\hls\syn"
call :COPY_FILE "%SRC_HLS%\hls\syn\report\csynth_design_size.rpt" "%DST_BASE%\hls\syn"
call :COPY_FILE "%SRC_HLS%\logs\hls_compile.log" "%DST_BASE%\hls\syn"
call :COPY_FILE "%SRC_HLS%\hls\syn\report\%COMP_NAME%_csynth.rpt" "%DST_BASE%\hls\syn"
call :COPY_FILE "%SRC_HLS%\hls\.autopilot\db\%COMP_NAME%.verbose.sched.rpt" "%DST_BASE%\hls\syn"

:: hls/impl (power workflow only -- package step not run in clk workflow)
if /i not "%WORKFLOW%"=="clk" (
    call :COPY_FILE "%SRC_HLS%\logs\hls_run_package.log" "%DST_BASE%\hls\impl"
)

:: hls root
call :COPY_FILE "%SRC_HLS%\logs\%COMP_VER%_script.steps.log" "%DST_BASE%\hls"

:: ==============================================================================
:: VIVADO FILE AGGREGATION (power workflow only)
:: ==============================================================================
if /i "%WORKFLOW%"=="clk" goto :aggregation_done

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

:aggregation_done
echo.
echo [INFO] File aggregation completed.
exit /b 0

:: ==============================================================================
:: SUBROUTINES
:: ==============================================================================

:: ------------------------------------------------------------------------------
:: COPY_FILE <src> <dst_dir>
:: Copies <src> to <dst_dir>, creating the directory if needed.
:: Warnings are suppressed when STATUS=FAILURE or WORKFLOW=clk.
:: ------------------------------------------------------------------------------
:COPY_FILE
set "SRC_FILE=%~1"
set "DST_DIR=%~2"

if not exist "%DST_DIR%" mkdir "%DST_DIR%"

if exist "%SRC_FILE%" (
    copy /Y "%SRC_FILE%" "%DST_DIR%" >nul
    echo   [OK] Copied: %SRC_FILE%
) else (
    if /i not "%STATUS%"=="FAILURE" (
        echo   [WARNING] File not found: %SRC_FILE%
    )
)
exit /b 0
