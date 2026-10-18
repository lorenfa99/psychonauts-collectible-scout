@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Install.ps1" %*
set "SCOUT_INSTALL_EXIT_CODE=%ERRORLEVEL%"
if not "%SCOUT_INSTALL_EXIT_CODE%"=="0" echo Installation did not finish. See the message above.
pause
exit /b %SCOUT_INSTALL_EXIT_CODE%
