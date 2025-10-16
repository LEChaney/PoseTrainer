# Drawing Canvas - Rust/wgpu

A high-performance drawing canvas built with Rust and wgpu, designed for WASM deployment and future Flutter integration.

## Current Status: Milestone 1 - Clear to Color ✨

The canvas currently clears to a constant dark gray color (#2C2C2C) to verify the rendering pipeline works correctly.

## Architecture

```
drawing_canvas/
├── src/
│   ├── lib.rs       # Library entry point (for future Flutter FFI)
│   ├── main.rs      # Standalone app entry point
│   ├── app.rs       # Core application state and logic
│   └── renderer.rs  # wgpu initialization and rendering
├── www/             # Web assets for standalone testing
│   ├── index.html   # HTML wrapper
│   └── package.json # Build scripts
└── Cargo.toml       # Dependencies
```

### Design Principles

- **Separation of concerns**: App logic is independent of windowing
- **Platform agnostic core**: Renderer can be used from different contexts
- **Future FFI ready**: Structured for Flutter integration via C ABI
- **WASM first**: Optimized for web deployment

## Prerequisites

Install the Rust toolchain and wasm-pack:

```bash
# Install Rust (if not already installed)
# Visit: https://rustup.rs/

# Install wasm-pack for building WASM
cargo install wasm-pack

# Add WASM target
rustup target add wasm32-unknown-unknown
```

## Building

### For Web (WASM)

**Option 1: Using wasm-pack (easier, production)**
```bash
# Build the WASM module
wasm-pack build --target web --out-dir www/pkg

# Or use the npm script
cd www
npm run build
```

**Option 2: Manual build with debug symbols (for debugging)**
```bash
# Install wasm-bindgen CLI once
cargo install wasm-bindgen-cli

# Build the library for WASM
cargo build --lib --target wasm32-unknown-unknown

# Generate bindings with debug symbols
wasm-bindgen --keep-debug \
  --target web \
  --out-dir www/pkg \
  ./target/wasm32-unknown-unknown/debug/drawing_canvas.wasm
```

### For Desktop (Native)

```bash
# Build and run natively
cargo run --bin drawing_canvas_app

# Or just build
cargo build --bin drawing_canvas_app
```

## Running

### Web

```bash
# Serve the web files (from the www/ directory)
cd www
python -m http.server 8080
# Or: npm run serve

# Then open http://localhost:8080 in your browser
```

### Desktop

```bash
cargo run
```

## Dependencies

- **wgpu** (22.0) - Cross-platform graphics API (WebGPU on web, Vulkan/DX12/Metal on native)
- **winit** (0.30) - Cross-platform windowing and events
- **wasm-bindgen** (0.2) - Rust↔JavaScript interop
- **web-sys** - Web API bindings for WASM

## Next Steps

- [ ] Add mouse/touch input handling
- [ ] Implement basic brush stroke rendering
- [ ] Add stroke buffering and optimization
- [ ] Implement pressure sensitivity (if available)
- [ ] Add stroke color and opacity control
- [ ] Implement undo/redo
- [ ] Add FFI exports for Flutter integration
- [ ] Support multiple render backends (WebGL2 fallback)

## Flutter Integration (Future)

The library is structured to support Flutter embedding:

1. Export C-compatible FFI functions from `lib.rs`
2. Create Flutter platform channels or use `flutter_rust_bridge`
3. Pass texture IDs or pixel buffers between Rust and Dart
4. Handle input events from Flutter and forward to app logic

## Troubleshooting

### WASM build fails

- Ensure `wasm-pack` is installed: `cargo install wasm-pack`
- Check that you have the WASM target: `rustup target add wasm32-unknown-unknown`

### Canvas doesn't appear

- Check browser console for errors
- Ensure WebGPU is supported (Chrome/Edge 113+, Firefox with flag)
- Verify `www/pkg/` contains the built WASM files

### Performance issues

- Build with `--release` flag: `wasm-pack build --target web --release`
- Check browser's GPU acceleration is enabled

## License

Part of the PoseTrainer project.
