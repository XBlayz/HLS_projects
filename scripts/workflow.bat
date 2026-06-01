@echo off
setlocal enabledelayedexpansion

:: Change working directory to project root (parent of scripts\)
:: This allows the script to work whether called from CLI or via double-click.
cd /d "%~dp0.."
set "ROOT_DIR=%CD%"


:: ============================================================
::  USAGE
::
::    workflow.bat <PROJECT_NAME> <COMP_VERSION> <COMP_NAME>
::                 [/wf <power|clk>]
::                 [workflow-specific options...]
::
::  Positional (required):
::    PROJECT_NAME   Project directory name        (e.g., project01_FIR)
::    COMP_VERSION   HLS component directory name  (e.g., fir_baseline)
::    COMP_NAME      Top-level HLS function name   (e.g., fir)
::
::  Named (optional):
::    /wf       Workflow to run (default: power)
::                power = Full HLS pipeline + Vivado power analysis
::                clk   = Clock sweep: csim + synthesis + cosim
::
::  All remaining options are forwarded as-is to the selected workflow.
::  Run the individual scripts with no arguments to see their full usage.
::
::  Examples:
::    workflow.bat project01_FIR fir_baseline fir
::    workflow.bat project01_FIR fir_baseline fir /wf power /from 3
::    workflow.bat project01_FIR fir_baseline fir /wf clk 10ns
::    workflow.bat project01_FIR fir_baseline fir /wf clk 100MHz /from 2
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

:: -- Scan for /wf before forwarding the remaining args.
::    All other options are collected verbatim for the delegate script.
set "WORKFLOW=power"
set "FORWARD_ARGS="

:parse_opts
if "%~1"=="" goto :end_parse
if /i "%~1"=="/wf" (
    set "WORKFLOW=%~2"
    shift & shift
    goto :parse_opts
)
:: Accumulate every other argument for forwarding
set "FORWARD_ARGS=%FORWARD_ARGS% %~1"
shift
goto :parse_opts
:end_parse

:: -- Validate /wf value
if /i not "%WORKFLOW%"=="power" if /i not "%WORKFLOW%"=="clk" (
    echo [FAIL ] Unknown workflow: %WORKFLOW%  -- valid values: power, clk
    goto :usage
)


:: ============================================================
::  Dispatch
:: ============================================================
if /i "%WORKFLOW%"=="power" goto :dispatch_power
if /i "%WORKFLOW%"=="clk"   goto :dispatch_clk


:dispatch_power
call "%ROOT_DIR%\scripts\power_workflow.bat" "%PROJECT_NAME%" "%COMP_VERSION%" "%COMP_NAME%"%FORWARD_ARGS%
exit /b %errorlevel%


:dispatch_clk
call "%ROOT_DIR%\scripts\clk_workflow.bat" "%PROJECT_NAME%" "%COMP_VERSION%" "%COMP_NAME%"%FORWARD_ARGS%
exit /b %errorlevel%


:usage
echo.
echo  USAGE:
echo    %~nx0 ^<PROJECT_NAME^> ^<COMP_VERSION^> ^<COMP_NAME^>
echo           [/wf ^<power^|clk^>] [workflow-specific options...]
echo.
echo  Positional ^(required^):
echo    PROJECT_NAME   Project directory      ^(e.g., project01_FIR^)
echo    COMP_VERSION   HLS component dir      ^(e.g., fir_baseline^)
echo    COMP_NAME      Top-level HLS function ^(e.g., fir^)
echo.
echo  Named ^(optional^):
echo    /wf   Workflow to run ^(default: power^)
echo            power  Full HLS pipeline + Vivado power analysis
echo            clk    Clock sweep: csim + synthesis + cosim
echo.
echo  Power workflow options ^(/wf power^):
echo    /tb       Testbench file name  ^(default: ^<PROJECT_NAME^>_^<COMP_VERSION^>_tb^)
echo    /clk      Clock file name      ^(default: ^<PROJECT_NAME^>_^<COMP_VERSION^>_clk^)
echo    /from     Step to start from, 0-5 ^(default: 1^)
echo    /simtime  Co-simulation duration   ^(default: 1000ns^)
echo.
echo  Clock workflow options ^(/wf clk^):
echo    ^<CLK_VAL^>  Clock target value ^(required, e.g., 10ns, 100MHz^)
echo    /from       Step to start from, 0-3 ^(default: 1^)
echo.
echo  Examples:
echo    %~nx0 project01_FIR fir_baseline fir
echo    %~nx0 project01_FIR fir_baseline fir /wf power /from 3
echo    %~nx0 project01_FIR fir_baseline fir /wf clk 10ns
echo    %~nx0 project01_FIR fir_baseline fir /wf clk 100MHz /from 2
echo.
endlocal
exit /b 1
