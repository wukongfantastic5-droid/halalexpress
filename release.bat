@echo off
cd /d "%~dp0"
echo ============================================
^>  Building APK + Creating GitHub Release
echo ============================================
powershell -ExecutionPolicy Bypass -File "scripts\release.ps1" %*
if %errorlevel% neq 0 (
  echo.
  echo [ERROR] Release failed!
  pause
  exit /b %errorlevel%
)
echo.
echo Done! Press any key to close.
pause
