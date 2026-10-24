@echo off
rem Runs Half-Life 2: Kart with Godot 4.7.
rem Uses the GODOT environment variable if set, otherwise the Steam copy of
rem Godot Engine, otherwise "godot" from PATH.
setlocal
if defined GODOT goto run
for %%D in (C D E F G H) do (
  if exist "%%D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" (
    set GODOT=%%D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe
    goto run
  )
)
if exist "%ProgramFiles(x86)%\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" (
  set "GODOT=%ProgramFiles(x86)%\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
  goto run
)
where godot >nul 2>nul && (set GODOT=godot& goto run)
echo Godot 4.7 was not found. Install it from Steam or godotengine.org,
echo or set GODOT to the full path of the Godot executable.
pause
exit /b 1
:run
if not exist "%~dp0assets\data\models.json" (
  echo The game assets are not built yet. Run first:  python tools\setup_assets.py
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0."
