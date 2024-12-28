@echo off
REM Get current folder name if no project name is provided
set "ProjectName=%1"
if "%ProjectName%"=="" (
    for %%I in (.) do set "ProjectName=%%~nxI"
)

REM Call the PowerShell script with the project name
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Initialize-GitRepo.ps1" -ProjectName "%ProjectName%"
