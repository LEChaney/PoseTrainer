@echo off
REM Alternative wrapper that uses Git Bash to run the .sh script
REM This is useful if you prefer bash or want cross-platform consistency

REM Try to find Git Bash
set "GIT_BASH=C:\Program Files\Git\bin\bash.exe"

if not exist "%GIT_BASH%" (
    echo Error: Git Bash not found at %GIT_BASH%
    echo Please install Git for Windows from https://git-scm.com/download/win
    echo Or use post_build_web.bat instead ^(PowerShell version^)
    exit /b 1
)

REM Run the bash script
"%GIT_BASH%" "%~dp0post_build_web.sh"
exit /b %ERRORLEVEL%
