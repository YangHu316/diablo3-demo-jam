@echo off
REM ============================================================
REM run_speedrun.bat - launch 1-min speedrun test mode
REM Pass --speedrun via cmdline; RiftManager reads speedrun_test.csv
REM ============================================================
chcp 65001 >nul
setlocal

set "PROJECT_DIR=%~dp0"
set "GODOT="

if exist "%PROJECT_DIR%..\Godot_v4.6.3-stable_win64_console.exe" set "GODOT=%PROJECT_DIR%..\Godot_v4.6.3-stable_win64_console.exe"
if not defined GODOT if exist "%PROJECT_DIR%..\Godot_v4.6.3-stable_win64.exe" set "GODOT=%PROJECT_DIR%..\Godot_v4.6.3-stable_win64.exe"
if not defined GODOT if exist "%PROJECT_DIR%..\Godot_v4.6-stable_win64_console.exe" set "GODOT=%PROJECT_DIR%..\Godot_v4.6-stable_win64_console.exe"
if not defined GODOT if exist "%PROJECT_DIR%..\Godot_v4.6-stable_win64.exe" set "GODOT=%PROJECT_DIR%..\Godot_v4.6-stable_win64.exe"
if not defined GODOT if exist "%PROJECT_DIR%Godot_v4.6.3-stable_win64_console.exe" set "GODOT=%PROJECT_DIR%Godot_v4.6.3-stable_win64_console.exe"
if not defined GODOT if exist "%PROJECT_DIR%Godot_v4.6.3-stable_win64.exe" set "GODOT=%PROJECT_DIR%Godot_v4.6.3-stable_win64.exe"

if not defined GODOT (
  echo [!] Godot 4.6.x not found. Tried:
  echo     %PROJECT_DIR%..\Godot_v4.6.3-stable_win64_console.exe
  echo     %PROJECT_DIR%..\Godot_v4.6.3-stable_win64.exe
  echo     %PROJECT_DIR%..\Godot_v4.6-stable_win64_console.exe
  echo     %PROJECT_DIR%..\Godot_v4.6-stable_win64.exe
  echo     %PROJECT_DIR%Godot_v4.6.3-stable_win64_console.exe
  echo     %PROJECT_DIR%Godot_v4.6.3-stable_win64.exe
  echo.
  echo Put Godot 4.6.x exe at one of those paths, or edit GODOT in this bat.
  pause
  exit /b 1
)

echo [*] Godot: %GODOT%
echo [*] Project: %PROJECT_DIR%
echo [*] Launching speedrun mode (--speedrun)...
echo     Look for: [RiftManager] speedrun mode active: goal=15 boss_hp=4000
echo.

"%GODOT%" --path "%PROJECT_DIR%" -- --speedrun

echo.
echo [*] Godot exited. Press any key to close.
pause >nul

endlocal
