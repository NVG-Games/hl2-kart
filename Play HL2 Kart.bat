@echo off
rem Runs Half-Life 2: Kart with Godot 4.7.
rem The release download carries Godot in runtime\godot. From source it uses the
rem GODOT environment variable, the Steam copy of Godot Engine, or "godot" on PATH.
rem On the first start the game builds its content from your Half-Life 2 and Half-Life.
setlocal
if exist "%~dp0runtime\godot\godot.exe" (
  set "GODOT=%~dp0runtime\godot\godot.exe"
  goto run
)
if defined GODOT goto run
for %%D in (C D E F G H) do (
  if exist "%%D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" (
    set "GODOT=%%D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
    goto run
  )
)
if exist "%ProgramFiles(x86)%\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" (
  set "GODOT=%ProgramFiles(x86)%\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
  goto run
)
where godot >nul 2>nul && (set GODOT=godot& goto run)
echo Godot 4.7 was not found. Download the release from
echo https://github.com/NVG-Games/hl2-kart/releases (it includes everything),
echo or install Godot 4.7 and set GODOT to its path.
pause
exit /b 1
:run
start "" "%GODOT%" --path "%~dp0."
