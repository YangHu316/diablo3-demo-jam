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

REM 依次尝试常见 Godot 路径
set "GODOT="
for %%P in (
  "%PROJECT_DIR%..\Godot_v4.6.3-stable_win64_console.exe"
  "%PROJECT_DIR%..\Godot_v4.6.3-stable_win64.exe"
  "%PROJECT_DIR%..\Godot_v4.6-stable_win64_console.exe"
  "%PROJECT_DIR%..\Godot_v4.6-stable_win64.exe"
  "%PROJECT_DIR%Godot_v4.6.3-stable_win64_console.exe"
  "%PROJECT_DIR%Godot_v4.6.3-stable_win64.exe"
) do (
  if exist "%%~P" (
    set "GODOT=%%~P"
    goto found
  )
)

echo [!] 没找到 Godot 4.6.x 可执行文件,尝试过的路径:
echo     %PROJECT_DIR%..\Godot_v4.6.3-stable_win64_console.exe
echo     %PROJECT_DIR%..\Godot_v4.6.3-stable_win64.exe
echo     %PROJECT_DIR%..\Godot_v4.6-stable_win64_console.exe
echo     %PROJECT_DIR%..\Godot_v4.6-stable_win64.exe
echo     %PROJECT_DIR%Godot_v4.6.3-stable_win64_console.exe
echo     %PROJECT_DIR%Godot_v4.6.3-stable_win64.exe
echo.
echo 解决:把 Godot 4.6.x 可执行文件放到上面任一路径,或编辑本脚本修 GODOT 变量
pause
exit /b 1

:found
echo [*] 找到 Godot: %GODOT%
echo [*] 项目: %PROJECT_DIR%
echo [*] 启动速通模式 (--speedrun)...
echo     生效后控制台应打印: [RiftManager] 速通模式生效: goal=15 守门人HP=4000
echo.

"%GODOT%" --path "%PROJECT_DIR%" -- --speedrun

echo.
echo [*] Godot 进程已结束,按任意键关闭窗口...
pause >nul

endlocal
