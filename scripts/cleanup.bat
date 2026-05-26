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
::  Cleanup HLS project
:: ============================================================
rmdir /s /q .\projects\%PROJECT_NAME%\%COMP_VERSION%\%COMP_VERSION%_script

:: ============================================================
::  Cleanup build directory
:: ============================================================
rmdir /s /q .\build
