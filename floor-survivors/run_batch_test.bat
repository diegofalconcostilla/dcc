@echo off
setlocal

set "GODOT=C:\Users\diego\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
set "GAMEDIR=%~dp0"
if "%GAMEDIR:~-1%"=="\" set "GAMEDIR=%GAMEDIR:~0,-1%"

tasklist /FI "IMAGENAME eq ollama.exe" 2>NUL | find /I "ollama.exe" >NUL
if errorlevel 1 (
    echo Starting Ollama server...
    start "Ollama" /MIN ollama serve
    timeout /T 3 /NOBREAK >NUL
) else (
    echo Ollama already running.
)

echo Running LLM content batch test (headless)...
"%GODOT%" --headless --path "%GAMEDIR%" --script res://scripts/llm_batch_test.gd
