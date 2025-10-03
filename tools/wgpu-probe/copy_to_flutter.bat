@echo off
REM Copy wasm-bindgen outputs to Flutter web assets after Trunk build

set WGPU_TARGET=target\wasm-bindgen\release
set FLUTTER_WEB=..\..\web\wgpu-probe

echo Copying WASM artifacts from %WGPU_TARGET% to %FLUTTER_WEB%...

if not exist "%WGPU_TARGET%\wgpu-probe.js" (
    echo Error: %WGPU_TARGET%\wgpu-probe.js not found!
    echo Run 'trunk build --release' first.
    exit /b 1
)

if not exist "%FLUTTER_WEB%" mkdir "%FLUTTER_WEB%"

copy /Y "%WGPU_TARGET%\wgpu-probe.js" "%FLUTTER_WEB%\wgpu-probe.js"
copy /Y "%WGPU_TARGET%\wgpu-probe_bg.wasm" "%FLUTTER_WEB%\wgpu-probe_bg.wasm"

echo Done! WASM files copied to Flutter web assets.
echo Run 'flutter run -d chrome' to test.
