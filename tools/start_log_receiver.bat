@echo off
REM Simple Windows batch file to run the log receiver
REM Double-click this file to start the log receiver server

echo ============================================
echo PoseTrainer Debug Log Receiver
echo ============================================
echo.

REM Check if Python is available
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python from https://python.org
    echo.
    pause
    exit /b 1
)

echo Starting log receiver server...
echo.
echo Instructions:
echo 1. Make sure your phone/device is on the same WiFi network
echo 2. Note the IP address shown below  
echo 3. In the app, go to Debug Settings and enter: http://YOUR_IP:8080/logs
echo 4. Enable network logging in the app
echo.

python "%~dp0log_receiver.py"

echo.
echo Log receiver stopped.
pause