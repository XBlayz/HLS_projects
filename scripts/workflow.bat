@echo off
setlocal enabledelayedexpansion

:: Change working directory to project root (parent of scripts\)
:: This allows the script to work whether called from CLI or via double-click.
cd /d "%~dp0.."
set "ROOT_DIR=%CD%"

:: ============================================================
::  CONSTANTS -- Edit default values here
:: ============================================================
set "DEFAULT_SIM_TIME=1000ns"


:: ============================================================
::  USAGE
::
::    workflow.bat <PROJECT_NAME> <COMP_VERSION> <COMP_NAME>
::                 [/tb <name>] [/clk <name>]
::                 [/from <1-5>] [/simtime <duration>]
::
::  Positional (required):
::    PROJECT_NAME   Project directory name        (e.g., project01_FIR)
::    COMP_VERSION   HLS component directory name  (e.g., fir_baseline)
::    COMP_NAME      Top-level HLS function name   (e.g., fir)
::
::  Named (optional):
::    /tb       Testbench file name    (default: <PROJECT_NAME>_<COMP_VERSION>_tb)
::    /clk      Clock file name        (default: <PROJECT_NAME>_<COMP_VERSION>_clk)
::    /from     Step to start from     (default: 1)
::                1 = C simulation
::                2 = HLS synthesis
::                3 = C/RTL co-simulation
::                4 = RTL IP export
::                5 = Vivado power analysis
::    /simtime  Co-simulation duration (default: %DEFAULT_SIM_TIME%)
:: ============================================================

:: -- Positional required arguments
if "%~3"=="" (
    echo [FAIL ] Missing required positional arguments.
    goto :usage
)
set "PROJECT_NAME=%~1"
set "COMP_VERSION=%~2"
set "COMP_NAME=%~3"
shift
shift
shift

:: -- Named optional arguments (initialize with defaults)
set "TB_FILE_NAME="
set "CLOCK_FILE_NAME="
set "FROM_STEP=1"
set "SIM_TIME=%DEFAULT_SIM_TIME%"

:parse_opts
if "%~1"=="" goto :end_parse
if /i "%~1"=="/tb"      ( set "TB_FILE_NAME=%~2"    & shift & shift & goto :parse_opts )
if /i "%~1"=="/clk"     ( set "CLOCK_FILE_NAME=%~2" & shift & shift & goto :parse_opts )
if /i "%~1"=="/from"    ( set "FROM_STEP=%~2"       & shift & shift & goto :parse_opts )
if /i "%~1"=="/simtime" ( set "SIM_TIME=%~2"        & shift & shift & goto :parse_opts )
echo [WARN ] Unknown option ignored: %~1
shift
goto :parse_opts
:end_parse

:: -- Apply defaults for unset optional parameters
if "%TB_FILE_NAME%"==""    set "TB_FILE_NAME=%PROJECT_NAME%_%COMP_VERSION%_tb"
if "%CLOCK_FILE_NAME%"=="" set "CLOCK_FILE_NAME=%PROJECT_NAME%_%COMP_VERSION%_clk"

:: -- Validate /from
set /a "FROM_STEP_VAL=%FROM_STEP%" 2>nul
if not "%FROM_STEP_VAL%"=="%FROM_STEP%" (
    echo [FAIL ] /from must be a number between 1 and 5.
    goto :usage
)
if %FROM_STEP% lss 1 ( echo [FAIL ] /from must be between 1 and 5. & goto :usage )
if %FROM_STEP% gtr 5 ( echo [FAIL ] /from must be between 1 and 5. & goto :usage )
set /a "FROM_STEP_PREV=%FROM_STEP%-1"


:: ============================================================
::  Derived paths -- Do not modify
:: ============================================================
set "HLS_ROOT_DIR=%ROOT_DIR%\projects\%PROJECT_NAME%\%COMP_VERSION%"
set "HLS_WORK_DIR=.\%COMP_VERSION%_script"
set "CFG_FILE=.\hls_config.cfg"
set "IP_ZIP=.\%COMP_VERSION%_script\%COMP_NAME%.zip"
set "BUILD_DIR=%ROOT_DIR%\build\%PROJECT_NAME%\%COMP_VERSION%"
set "IP_REPO_DIR=%BUILD_DIR%\ip_repo"

mkdir "%BUILD_DIR%"   2>nul
mkdir "%IP_REPO_DIR%" 2>nul


echo.
echo ========================================================
echo  TARGET  : %COMP_VERSION%  (%COMP_NAME%)
echo  BUILD   : %BUILD_DIR%
echo  SIMTIME : %SIM_TIME%
if %FROM_STEP% gtr 1 (
    echo  START   : step %FROM_STEP%  ^(steps 1-%FROM_STEP_PREV% skipped^)
)
echo ========================================================

if %FROM_STEP%==5 goto :skip_cfg_check
cd /d "%HLS_ROOT_DIR%"
if not exist "%CFG_FILE%" (
    echo [FAIL ] HLS config not found: %CFG_FILE%
    goto :error
)
echo [INFO ] HLS config: %CFG_FILE%
:skip_cfg_check

:: -- Route to the requested start step
if %FROM_STEP%==1 goto :step1
if %FROM_STEP%==2 goto :step2
if %FROM_STEP%==3 goto :step3
if %FROM_STEP%==4 goto :step4
goto :step5


:step1
cd /d "%HLS_ROOT_DIR%"
echo.
echo.
echo ========================================================
echo  1. RUNNING C SIMULATION (vitis-run)
echo ========================================================
call vitis-run --mode hls --csim --config "%CFG_FILE%" --work_dir "%HLS_WORK_DIR%"
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
call v++ -c --mode hls --config "%CFG_FILE%" --work_dir "%HLS_WORK_DIR%"
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
call vitis-run --mode hls --cosim --config "%CFG_FILE%" --work_dir "%HLS_WORK_DIR%"
if %errorlevel% neq 0 (
    echo [FAIL ] C/RTL co-simulation failed ^(errorlevel: %errorlevel%^)
    goto :error
)
echo [ OK  ] C/RTL co-simulation completed


:step4
cd /d "%HLS_ROOT_DIR%"
echo.
echo.
echo ========================================================
echo  4. EXPORTING RTL IP (vitis-run)
echo ========================================================
call vitis-run --mode hls --package --config "%CFG_FILE%" --work_dir "%HLS_WORK_DIR%"
if %errorlevel% neq 0 (
    echo [FAIL ] IP export failed ^(errorlevel: %errorlevel%^)
    goto :error
)

if not exist "%IP_ZIP%" (
    echo [FAIL ] IP zip not found: %IP_ZIP%
    goto :error
)

echo [INFO ] Extracting IP to %IP_REPO_DIR%\%COMP_NAME%...
7z x "%IP_ZIP%" -o"%IP_REPO_DIR%\%COMP_NAME%" -y > nul
if %errorlevel% neq 0 (
    echo [FAIL ] IP extraction failed ^(errorlevel: %errorlevel%^)
    goto :error
)
echo [ OK  ] IP extracted in %IP_REPO_DIR%\%COMP_NAME%


:step5
cd /d "%BUILD_DIR%"
echo.
echo.
echo ========================================================
echo  5. RUNNING VIVADO POWER ANALYSIS
echo ========================================================
cd %BUILD_DIR%
call vivado -mode batch -notrace ^
    -source ..\..\..\scripts\vivado_power_report.tcl ^
    -tclargs "%PROJECT_NAME%" "%COMP_VERSION%" "%COMP_NAME%" "%TB_FILE_NAME%" "%CLOCK_FILE_NAME%" "%SIM_TIME%"
if %errorlevel% neq 0 (
    echo [FAIL ] Vivado power analysis failed ^(errorlevel: %errorlevel%^)
    goto :error
)
echo [ OK  ] Vivado power analysis completed


echo.
echo.
echo ========================================================
echo  WORKFLOW COMPLETED SUCCESSFULLY
echo  Target : %COMP_VERSION%  (%COMP_NAME%)
echo ========================================================
endlocal
exit /b 0

:: ============================================================
::  REPORT AGGREGATION (SUCCESS)
:: ============================================================
echo.
echo ========================================================
echo  SAVING REPORTS
echo ========================================================
call "%~dp0aggregate_reports.bat" "%PROJECT_NAME%" "%COMP_VERSION%" "%COMP_NAME%" SUCCESS

endlocal
exit /b 0


:usage
echo.
echo  USAGE:
echo    %~nx0 ^<PROJECT_NAME^> ^<COMP_VERSION^> ^<COMP_NAME^>
echo           [/tb ^<name^>] [/clk ^<name^>] [/from ^<1-5^>] [/simtime ^<duration^>]
echo.
echo  Positional ^(required^):
echo    PROJECT_NAME   Project directory      ^(e.g., project01_FIR^)
echo    COMP_VERSION   HLS component dir      ^(e.g., fir_baseline^)
echo    COMP_NAME      Top-level HLS function ^(e.g., fir^)
echo.
echo  Named ^(optional^):
echo    /tb       Testbench file  ^(default: ^<PROJECT_NAME^>_^<COMP_VERSION^>_tb^)
echo    /clk      Clock file      ^(default: ^<PROJECT_NAME^>_^<COMP_VERSION^>_clk^)
echo    /from     Step to start from, 1-5      ^(default: 1^)
echo    /simtime  Co-simulation duration        ^(default: %DEFAULT_SIM_TIME%^)
echo.
endlocal
exit /b 1

:error
echo.
echo ========================================================
echo  WORKFLOW INTERRUPTED -- Check the logs above
echo  Target : %COMP_VERSION%  (%COMP_NAME%)
echo ========================================================
endlocal
exit /b 1

:: ============================================================
::  REPORT AGGREGATION (FAILURE)
:: ============================================================
echo.
echo ========================================================
echo  SAVING REPORTS (PARTIAL EXPORT)
echo ========================================================
call "%~dp0aggregate_reports.bat" "%PROJECT_NAME%" "%COMP_VERSION%" "%COMP_NAME%" FAILURE

endlocal
exit /b 1
