//! Drawing Canvas Library
//!
//! This crate provides a wgpu-based drawing canvas that can run:
//! - Standalone in a browser (via WASM)
//! - Embedded in Flutter (via FFI) - TODO: future work
//!
//! The library is structured to separate the core rendering logic from
//! platform-specific initialization (windowing, canvas element creation).

mod app;
mod renderer;
mod window;

pub use app::App;
pub use renderer::Renderer;
pub use window::AppWrapper;

// Re-export for WASM builds
#[cfg(target_arch = "wasm32")]
pub use wasm_bindgen;

/// Initialize panic hook for better error messages in WASM
#[cfg(target_arch = "wasm32")]
pub fn init_panic_hook() {
    console_error_panic_hook::set_once();
}

/// Initialize logging for WASM (logs go to browser console)
#[cfg(target_arch = "wasm32")]
pub fn init_logging() {
    console_log::init_with_level(log::Level::Debug).expect("Failed to initialize logger");
}

/// WASM entry point - called when the module is loaded
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen::prelude::wasm_bindgen(start)]
pub fn wasm_start() {
    init_panic_hook();
    init_logging();
    
    log::info!("🚀 Drawing Canvas WASM module started");
    
    // Spawn the event loop
    wasm_bindgen_futures::spawn_local(async {
        run_event_loop();
    });
}

#[cfg(target_arch = "wasm32")]
fn run_event_loop() {
    use winit::event_loop::{EventLoop, ControlFlow};
    
    let event_loop = EventLoop::new().expect("Failed to create event loop");
    event_loop.set_control_flow(ControlFlow::Wait);
    
    let mut app_wrapper = AppWrapper::new();
    
    let _ = event_loop.run_app(&mut app_wrapper);
}

// Future: FFI exports for Flutter integration
// #[no_mangle]
// pub extern "C" fn drawing_canvas_create() -> *mut App { ... }
// #[no_mangle]
// pub extern "C" fn drawing_canvas_render(app: *mut App) { ... }
// etc.
