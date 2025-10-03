Place the wasm-bindgen build outputs here so Flutter web can serve them at
  /wgpu-probe/wgpu-probe.js
  /wgpu-probe/wgpu-probe_bg.wasm

If using Trunk, you can copy from tools/wgpu-probe/target/wasm-bindgen/release/ after a build:
  wgpu-probe.js -> web/wgpu-probe/wgpu-probe.js
  wgpu-probe_bg.wasm -> web/wgpu-probe/wgpu-probe_bg.wasm
