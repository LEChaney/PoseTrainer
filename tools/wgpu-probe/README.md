# wgpu-probe

Minimal Rust + wgpu adapter/device probe to validate platform/browser support.

What it does
- Queries wgpu for an adapter and device.
- Logs adapter info (backend, name, features, limits).
- Creates a small surface (on web: a canvas) and clears it.

Native (Windows/macOS/Linux)
1. Install Rust (https://rustup.rs/).
2. From this folder:
```powershell
cargo run --release
```

Web (WASM, via trunk)
1. Install trunk and wasm32 target:
```powershell
cargo install trunk
rustup target add wasm32-unknown-unknown
```
2. From this folder:
```powershell
trunk serve --release
```
3. Open the printed localhost URL in multiple browsers (Chrome, Firefox, Safari).

Troubleshooting
- If adapter selection fails, check console logs.
- Some browsers disable WebGPU behind flags. Chromium: chrome://flags → WebGPU enabled.
- If WebGPU isn’t available, wgpu will fall back or fail depending on build; this sample prints helpful details.
