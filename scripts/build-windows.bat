@echo off
rem SPDX-License-Identifier: GPL-3.0-or-later
rem Copyright (C) 2026 Simorg
rem
rem Runs build-windows.ps1 from an ordinary Command Prompt, or from a
rem double-click in Explorer.
rem
rem   scripts\build-windows.bat                 both architectures
rem   scripts\build-windows.bat x64             just one
rem   scripts\build-windows.bat -Config dev     point the build at localhost
rem   scripts\build-windows.bat -InstallQt      fetch Qt first, then build
rem   scripts\build-windows.bat -Help
rem
rem -ExecutionPolicy Bypass is here because a freshly installed Windows refuses
rem to run an unsigned .ps1 at all, and the alternative is telling everybody to
rem change a machine-wide security setting before they can build anything.

setlocal
set "SCRIPT=%~dp0build-windows.ps1"

rem PowerShell 7 where it is installed, Windows PowerShell otherwise. The script
rem runs on both; the newer one is simply faster at making the .zip.
where /q pwsh.exe && (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
) || (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
)

set EXITCODE=%ERRORLEVEL%

rem A double-click gets its own console window, which would close on the last
rem line and take the output with it. Started from a prompt, this is skipped.
echo %CMDCMDLINE% | find /i "%~0" >nul && (
    echo.
    pause
)

exit /b %EXITCODE%
