@echo off
setlocal enabledelayedexpansion

:: Change working directory to project root (parent of scripts\)
:: This allows the script to work whether called from CLI or via double-click.
cd /d "%~dp0.."


:: ============================================================
::  CONFIGURATION -- Modify these parameters for each run
::
::  PROJECT_NAME : name of the project directory
::                 (e.g., project01_FIR)
::  COMP_VERSION : name of the HLS component directory
::                 (e.g., fir_baseline, fir_pipelined)
::  COMP_NAME    : name of the top-level HLS function
::                 (e.g., fir — must match hls_config.cfg)
:: ============================================================
set PROJECT_NAME=project01_FIR
set COMP_VERSION=fir_baseline
set COMP_NAME=fir


:: ============================================================
::  Derived paths -- Do not modify
:: ============================================================
set HLS_ROOT_DIR=.\projects\%PROJECT_NAME%\%COMP_VERSION%\
set HLS_WORK_DIR=.\%COMP_VERSION%_script
set CFG_FILE=.\hls_config.cfg
set IP_ZIP=%HLS_WORK_DIR%\%COMP_NAME%.zip
set BUILD_DIR=.\build\%PROJECT_NAME%\%COMP_VERSION%
set IP_REPO_DIR=%BUILD_DIR%\ip_repo

mkdir %BUILD_DIR%  2>nul
mkdir %IP_REPO_DIR% 2>nul


cd %HLS_ROOT_DIR%

echo.
echo ========================================================
echo  TARGET: %COMP_VERSION%  (%COMP_NAME%)
echo  BUILD : %BUILD_DIR%
echo ========================================================

if not exist "%CFG_FILE%" (
    echo [FAIL ] HLS config not found: %CFG_FILE%
    goto :error
)
echo [INFO ] HLS config: %CFG_FILE%


echo.
echo.
echo ========================================================
echo  1. RUNNING C SIMULATION (vitis-run)
echo ========================================================
call vitis-run --mode hls --csim --config %CFG_FILE% --work_dir %HLS_WORK_DIR%
if %errorlevel% neq 0 (
    echo [FAIL ] C simulation failed ^(errorlevel: %errorlevel%^)
    goto :error
)
echo [ OK  ] C simulation completed


echo.
echo.
echo ========================================================
echo  2. RUNNING HIGH-LEVEL SYNTHESIS (v++)
echo ========================================================
call v++ -c --mode hls --config %CFG_FILE% --work_dir %HLS_WORK_DIR%
if %errorlevel% neq 0 (
    echo [FAIL ] HLS synthesis failed ^(errorlevel: %errorlevel%^)
    goto :error
)
echo [ OK  ] HLS synthesis completed


echo.
echo.
echo ========================================================
echo  3. RUNNING C/RTL CO-SIMULATION (vitis-run)
echo ========================================================
call vitis-run --mode hls --cosim --config %CFG_FILE% --work_dir %HLS_WORK_DIR%
if %errorlevel% neq 0 (
    echo [FAIL ] C/RTL co-simulation failed ^(errorlevel: %errorlevel%^)
    goto :error
)
echo [ OK  ] C/RTL co-simulation completed


echo.
echo.
echo ========================================================
echo  4. EXPORTING RTL IP (vitis-run)
echo ========================================================
call vitis-run --mode hls --package --config %CFG_FILE% --work_dir %HLS_WORK_DIR%
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

cd ..\..\..\


echo.
echo.
echo ========================================================
echo  5. RUNNING VIVADO POWER ANALYSIS
echo ========================================================
cd %BUILD_DIR%
call vivado -mode batch -notrace ^
    -source ..\..\..\scripts\vivado_power_report.tcl ^
    -tclargs %PROJECT_NAME% %COMP_VERSION% %COMP_NAME%
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
echo  Report : %BUILD_DIR%\reports\post_synth_power_report.txt
echo ========================================================
endlocal
pause
exit /b 0


:error
echo.
echo ========================================================
echo  WORKFLOW INTERRUPTED -- Check the logs above
echo  Target : %COMP_VERSION%  (%COMP_NAME%)
echo ========================================================
endlocal
pause
exit /b 1
