@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: Define the list of clock periods to test (in nanoseconds)
:: Modify this list to test different timing constraints
:: ============================================================================
set CLOCK_VALUES=2.0 2.5 3.0 3.5 4.0 4.5 5.0 6.0 7.0 8.0 9.0 10.0 15.0 20.0 25.0

echo Starting HLS clock exploration...

:: Iterate through each specified clock value
for %%C in (%CLOCK_VALUES%) do (
    echo.
    echo ============================================================================
    echo Testing Solutions with CLK_VAL = %%C ns
    echo ============================================================================

    :: Execute the workflow for the selected solutions
    call .\scripts\workflow.bat project01_FIR 03_ap-int fir /wf clk %%C
    call .\scripts\workflow.bat project01_FIR 07_loop-fission-array-partition fir /wf clk %%C
    call .\scripts\workflow.bat project01_FIR 10_total-unroll fir /wf clk %%C
)

echo.
echo ============================================================================
echo All workflow executions completed.
echo ============================================================================
endlocal
