@echo off
REM Wrapper for post_build_web.ps1 to avoid execution policy issues
powershell -ExecutionPolicy Bypass -File "%~dp0post_build_web.ps1"
