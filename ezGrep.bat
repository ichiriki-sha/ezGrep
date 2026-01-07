@echo off
rem ============================================================================
rem サクラエディタ風Grep PowerShell スクリプト呼び出し
rem ============================================================================

set script_path=.\ezGrep.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%script_path%" %*
exit /b %ERRORLEVEL%
