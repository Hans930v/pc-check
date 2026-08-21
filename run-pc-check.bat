@echo off
setlocal
title PC Check Report

echo ============================================================
echo                      PC CHECK
echo              PowerShell Policy Manager
echo ============================================================
echo.
echo This launcher will:
echo.
echo   1. Display the current PowerShell execution policies
echo   2. Temporarily set CurrentUser policy to Bypass
echo   3. Run PC Check
echo   4. Restore the ORIGINAL CurrentUser policy
echo   5. Display the policies again for verification
echo.
echo No other policy scope will be modified.
echo.
pause

echo.
echo ============================================================
echo                 CURRENT EXECUTION POLICIES
echo ============================================================
echo.

powershell.exe -NoProfile -Command "Get-ExecutionPolicy -List | Format-Table -AutoSize"

echo.
echo ============================================================
echo             TEMPORARILY SETTING POLICY
echo ============================================================
echo.

echo Saving original CurrentUser policy...

for /f "delims=" %%P in ('powershell.exe -NoProfile -Command "Get-ExecutionPolicy -Scope CurrentUser"') do set "ORIGINAL_POLICY=%%P"

echo Original CurrentUser policy: %ORIGINAL_POLICY%

echo.
echo Setting CurrentUser policy to Bypass...

powershell.exe -NoProfile -Command "Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force"

if errorlevel 1 (
    echo.
    echo ERROR: Failed to change PowerShell execution policy.
    echo No PC Check script was started.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo             POLICIES AFTER TEMPORARY BYPASS
echo ============================================================
echo.

powershell.exe -NoProfile -Command "Get-ExecutionPolicy -List | Format-Table -AutoSize"

echo.
echo ============================================================
echo                  STARTING PC CHECK
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PC-check.ps1"

set "PCCHECK_EXIT=%ERRORLEVEL%"

echo.
echo ============================================================
echo              PC CHECK PROCESS FINISHED
echo ============================================================
echo.
echo PC Check exit code: %PCCHECK_EXIT%
echo.

echo Restoring original CurrentUser execution policy:
echo %ORIGINAL_POLICY%
echo.

powershell.exe -NoProfile -Command "Set-ExecutionPolicy -ExecutionPolicy '%ORIGINAL_POLICY%' -Scope CurrentUser -Force"

if errorlevel 1 (
    echo.
    echo ============================================================
    echo WARNING: POLICY RESTORATION FAILED
    echo ============================================================
    echo.
    echo The original CurrentUser policy was:
    echo %ORIGINAL_POLICY%
    echo.
    echo Please restore it manually.
    echo.
    pause
    exit /b 2
)

echo.
echo ============================================================
echo             POLICIES AFTER RESTORATION
echo ============================================================
echo.

powershell.exe -NoProfile -Command "Get-ExecutionPolicy -List | Format-Table -AutoSize"

echo.
echo ============================================================
echo                   RESTORATION COMPLETE
echo ============================================================
echo.
echo Original CurrentUser policy:
echo %ORIGINAL_POLICY%
echo.
echo Current policies are shown above for verification.
echo.
echo PC Check exit code: %PCCHECK_EXIT%
echo.

pause

exit /b %PCCHECK_EXIT%