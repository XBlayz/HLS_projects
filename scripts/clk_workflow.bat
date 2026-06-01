@echo off
setlocal enabledelayedexpansion

:: Change working directory to project root (parent of scripts\)
:: This allows the script to work whether called from CLI or via double-click.
cd /d "%~dp0.."
set "ROOT_DIR=%CD%"


:: ============================================================
::  USAGE
::
::    clk_workflow.bat <PROJECT_NAME> <COMP_VERSION> <COMP_NAME> <CLK_VAL>
::                     [/from <0-3>]
::
::  Positional (required):
::    PROJECT_NAME   Project directory name        (e.g., project01_FIR)
::    COMP_VERSION   HLS component directory name  (e.g., fir_baseline)
::    COMP_NAME      Top-level HLS function name   (e.g., fir)
::    CLK_VAL        Clock target value passed to --hls.clock
::                   (e.g., 10, 10ns, 100MHz -- must be a valid HLS clock string)
::
::  Named (optional):
::    /from     Step to start from     (default: 1)
::                1 = C simulation
::                2 = HLS synthesis  (with clock override)
::                3 = C/RTL co-simulation
::                0 = Report aggregation
::
::  Clock override mechanism:
::    A temporary config file (hls_config_clk.cfg) is generated next to
::    hls_config.cfg with the "clock=" line stripped from the [hls] section.
::    The CLK_VAL is then passed via --hls.clock on the command line, which
::    is the sole clock source. The temporary file is deleted on exit.
:: ============================================================

:: -- Positional required arguments
if "%~4"=="" (
    echo [FAIL ] Missing required positional arguments.
    goto :usage
)
set "PROJECT_NAME=%~1"
set "COMP_VERSION=%~2"
set "COMP_NAME=%~3"
set "CLK_VAL=%~4"
shift
shift
shift
shift

:: -- Named optional arguments (initialize with defaults)
set "FROM_STEP=1"

:parse_opts
if "%~1"=="" goto :end_parse
if /i "%~1"=="/from" ( set "FROM_STEP=%~2" & shift & shift & goto :parse_opts )
echo [WARN ] Unknown option ignored: %~1
shift
goto :parse_opts
:end_parse

:: -- Validate /from
set /a "FROM_STEP_VAL=%FROM_STEP%" 2>nul
if not "%FROM_STEP_VAL%"=="%FROM_STEP%" (
    echo [FAIL ] /from must be a number between 0 and 3.
    goto :usage
)
if %FROM_STEP% lss 0 ( echo [FAIL ] /from must be between 0 and 3. & goto :usage )
if %FROM_STEP% gtr 3 ( echo [FAIL ] /from must be between 0 and 3. & goto :usage )
set /a "FROM_STEP_PREV=%FROM_STEP%-1"


:: ============================================================
::  Derived paths -- Do not modify
:: ============================================================
set "HLS_ROOT_DIR=%ROOT_DIR%\projects\%PROJECT_NAME%\%COMP_VERSION%"
set "HLS_WORK_DIR=.\%COMP_VERSION%_clk-%CLK_VAL%_script"
set "CFG_FILE=.\hls_config.cfg"
set "CFG_FILE_CLK=.\hls_config_clk.cfg"

:: Reports land in a clock-specific subdirectory
set "REPORT_SUBDIR=%COMP_VERSION%_clk-%CLK_VAL%"


echo.
echo ========================================================
echo  WORKFLOW : clk
echo  TARGET   : %COMP_VERSION%  (%COMP_NAME%)
echo  CLOCK    : %CLK_VAL%
echo  REPORTS  : reports\%PROJECT_NAME%\%REPORT_SUBDIR%
if %FROM_STEP% == 0 (
    echo  START    : report aggregation
)
if %FROM_STEP% gtr 1 (
    echo  START    : step %FROM_STEP%  ^(steps 1-%FROM_STEP_PREV% skipped^)
)
echo ========================================================

if %FROM_STEP%==0 goto :step0

cd /d "%HLS_ROOT_DIR%"
if not exist "%CFG_FILE%" (
    echo [FAIL ] HLS config not found: %CFG_FILE%
    goto :error_no_cleanup
)

:: ============================================================
::  Generate temporary config with "clock=" line stripped.
::  findstr /v /i /r performs a case-insensitive regex exclusion:
::    ^clock=  matches any line starting with "clock=" (the [hls] directive).
:: ============================================================
echo [INFO ] Generating temporary config: %CFG_FILE_CLK%
findstr /v /i /r "^clock=" "%CFG_FILE%" > "%CFG_FILE_CLK%"
if %errorlevel% neq 0 (
    echo [FAIL ] Failed to generate temporary config.
    goto :error_no_cleanup
)
echo [INFO ] HLS config (original) : %CFG_FILE%
echo [INFO ] HLS config (patched)  : %CFG_FILE_CLK%  ^(clock= removed^)
echo [INFO ] Clock override        : --hls.clock=%CLK_VAL%

:: -- Route to the requested start step
if %FROM_STEP%==1 goto :step1
if %FROM_STEP%==2 goto :step2
if %FROM_STEP%==3 goto :step3
goto :step0


:step1
cd /d "%HLS_ROOT_DIR%"
echo.
echo.
echo ========================================================
echo  1. RUNNING C SIMULATION (vitis-run)
echo ========================================================
call vitis-run --mode hls --csim --config "%CFG_FILE_CLK%" --work_dir "%HLS_WORK_DIR%" --hls.clock=%CLK_VAL%
if %errorlevel% neq 0 (
    echo [FAIL ] C simulation failed ^(errorlevel: %errorlevel%^)
    goto :error
)
echo [ OK  ] C simulation completed


:step2
cd /d "%HLS_ROOT_DIR%"
echo.
echo.
echo ========================================================
echo  2. RUNNING HIGH-LEVEL SYNTHESIS (v++)
echo ========================================================
call v++ -c --mode hls --config "%CFG_FILE_CLK%" --work_dir "%HLS_WORK_DIR%" --hls.clock=%CLK_VAL%
if %errorlevel% neq 0 (
    echo [FAIL ] HLS synthesis failed ^(errorlevel: %errorlevel%^)
    goto :error
)
echo [ OK  ] HLS synthesis completed


:step3
cd /d "%HLS_ROOT_DIR%"
echo.
echo.
echo ========================================================
echo  3. RUNNING C/RTL CO-SIMULATION (vitis-run)
echo ========================================================
call vitis-run --mode hls --cosim --config "%CFG_FILE_CLK%" --work_dir "%HLS_WORK_DIR%" --hls.clock=%CLK_VAL%
if %errorlevel% neq 0 (
    echo [FAIL ] C/RTL co-simulation failed ^(errorlevel: %errorlevel%^)
    goto :error
)
echo [ OK  ] C/RTL co-simulation completed


:: ============================================================
::  REPORT AGGREGATION (SUCCESS)
:: ============================================================
:step0
echo.
echo ========================================================
echo  SAVING REPORTS
echo ========================================================
cd /d "%ROOT_DIR%"
call ".\scripts\aggregate_reports.bat" "%PROJECT_NAME%" "%REPORT_SUBDIR%" "%COMP_NAME%" SUCCESS clk

call :CLEANUP
echo.
echo.
echo ========================================================
echo  WORKFLOW COMPLETED SUCCESSFULLY
echo  Target  : %COMP_VERSION%  (%COMP_NAME%)
echo  Clock   : %CLK_VAL%
echo  Reports : reports\%PROJECT_NAME%\%REPORT_SUBDIR%
echo ========================================================

endlocal
exit /b 0


:usage
echo.
echo  USAGE:
echo    %~nx0 ^<PROJECT_NAME^> ^<COMP_VERSION^> ^<COMP_NAME^> ^<CLK_VAL^>
echo           [/from ^<0-3^>]
echo.
echo  Positional ^(required^):
echo    PROJECT_NAME   Project directory      ^(e.g., project01_FIR^)
echo    COMP_VERSION   HLS component dir      ^(e.g., fir_baseline^)
echo    COMP_NAME      Top-level HLS function ^(e.g., fir^)
echo    CLK_VAL        Clock target value     ^(e.g., 10ns, 100MHz^)
echo.
echo  Named ^(optional^):
echo    /from     Step to start from, 0-3      ^(default: 1^)
echo                1 = C simulation
echo                2 = HLS synthesis  ^(clock override applied^)
echo                3 = C/RTL co-simulation
echo                0 = Report aggregation only
echo.
endlocal
exit /b 1

:error
:: ============================================================
::  REPORT AGGREGATION (FAILURE)
:: ============================================================
echo.
echo ========================================================
echo  SAVING REPORTS (PARTIAL EXPORT)
echo ========================================================
cd /d "%ROOT_DIR%"
call ".\scripts\aggregate_reports.bat" "%PROJECT_NAME%" "%REPORT_SUBDIR%" "%COMP_NAME%" FAILURE clk

call :CLEANUP

echo.
echo ========================================================
echo  WORKFLOW INTERRUPTED -- Check the logs above
echo  Target  : %COMP_VERSION%  (%COMP_NAME%)
echo  Clock   : %CLK_VAL%
echo ========================================================

endlocal
exit /b 1

:error_no_cleanup
:: Pre-patch failure: temporary config was never created, skip cleanup.
echo.
echo ========================================================
echo  WORKFLOW INTERRUPTED -- Check the logs above
echo  Target  : %COMP_VERSION%  (%COMP_NAME%)
echo  Clock   : %CLK_VAL%
echo ========================================================

endlocal
exit /b 1

:: ============================================================
::  SUBROUTINES
:: ============================================================
:CLEANUP
:: Delete the temporary patched config if it exists.
cd /d "%HLS_ROOT_DIR%"
if exist "%CFG_FILE_CLK%" (
    del /f /q "%CFG_FILE_CLK%"
    echo [INFO ] Temporary config deleted: %CFG_FILE_CLK%
)
exit /b 0
