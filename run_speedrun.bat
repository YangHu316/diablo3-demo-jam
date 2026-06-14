@echo off
REM ============================================================
REM  run_speedrun.bat — 一键启动「1分钟速通」测试模式
REM  原理: 命令行 -- --speedrun → RiftManager 读 speedrun_test.csv
REM         套差量 (进度条目标 106->15 / 守门人HP 24000->4000)。
REM  不带 --speedrun 启动 = 走正式值, 零污染 (见 数值表/测试-1分钟速通)。
REM ============================================================
setlocal

REM 项目根 = 本脚本所在目录
set "PROJECT_DIR=%~dp0"

REM Godot 可执行文件 (本机在 Downloads, 即项目上一级)。
REM 控制台版可看 stdout 日志; 若只想正常窗口玩, 把下行换成无 _console 的 GUI 版。
set "GODOT=%PROJECT_DIR%..\Godot_v4.6.3-stable_win64_console.exe"

if not exist "%GODOT%" (
  echo [!] 找不到 Godot: %GODOT%
  echo     请改本脚本里的 GODOT 路径指向你的 Godot 4.6.3 可执行文件。
  pause
  exit /b 1
)

echo [*] 启动速通测试模式...
echo     Godot : %GODOT%
echo     项目  : %PROJECT_DIR%
echo     生效后控制台应打印: [RiftManager] 速通模式生效: goal=15 守门人HP=4000
echo.

"%GODOT%" --path "%PROJECT_DIR%" -- --speedrun

endlocal
