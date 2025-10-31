//! Drawing Canvas Library
//!
//! This crate provides a wgpu-based drawing canvas that can run:
//! - Standalone in a browser (via WASM)
//! - Embedded in Flutter (via FFI) - TODO: future work
//!
//! The library is structured to separate the core rendering logic from
//! platform-specific initialization (windowing, canvas element creation).

mod app;
mod brush;
mod color;
pub mod debug;
mod input;
mod renderer;
mod window;

pub use app::App;
pub use brush::{BrushDab, BrushParams, BrushState, InputFilterMode, PressureMapping};
pub use input::{InputQueue, PointerEvent, PointerEventType};
pub use renderer::{BlendColorSpace, Renderer};
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
    // Try to initialize logger, but don't panic if it's already initialized
    // This allows multiple drawing canvas instances or reinitialization
    
    // Use Error level in release builds to suppress verbose debug/info logs
    // Use Debug level in debug builds for development
    #[cfg(debug_assertions)]
    let log_level = log::Level::Debug;
    #[cfg(not(debug_assertions))]
    let log_level = log::Level::Error;
    
    let _ = console_log::init_with_level(log_level);
}

/// Initialize the WASM drawing canvas
/// Call this explicitly from JavaScript when you're ready to start the canvas
/// This can be called multiple times - only the event loop will be created once,
/// but new canvas instances will be created each time
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen::prelude::wasm_bindgen]
pub fn init_drawing_canvas() {
    use std::sync::atomic::{AtomicBool, Ordering};
    
    // One-time initialization (event loop, panic hook, logger)
    // These should only be initialized once per page load
    static EVENT_LOOP_STARTED: AtomicBool = AtomicBool::new(false);
    
    // Always initialize panic hook and logger (they're idempotent)
    init_panic_hook();
    init_logging();
    
    // Only start the event loop once
    if !EVENT_LOOP_STARTED.swap(true, Ordering::SeqCst) {
        log::info!("🚀 Drawing Canvas WASM module initializing (first time)");
        
        // Spawn the event loop
        wasm_bindgen_futures::spawn_local(async {
            run_event_loop();
        });
        
        log::info!("✅ Drawing Canvas event loop spawned");
    } else {
        log::info!("🔄 Drawing Canvas reinitialized (reusing existing event loop)");
        
        // Check if we need to relocate the canvas to a new container
        // This handles Flutter rebuilding the widget tree (layout changes, navigation, etc.)
        window::check_and_relocate_canvas_global();
    }
}

#[cfg(target_arch = "wasm32")]
fn run_event_loop() {
    use winit::event_loop::{EventLoop, ControlFlow};
    
    let event_loop = EventLoop::new().expect("Failed to create event loop");
    event_loop.set_control_flow(ControlFlow::Wait);
    
    let mut app_wrapper = AppWrapper::new();
    
    // Store reference for JS callbacks
    window::set_global_app_wrapper(&mut app_wrapper);
    
    let _ = event_loop.run_app(&mut app_wrapper);
}

/// Set the blend color space from JavaScript
/// 
/// # Arguments
/// * `is_srgb` - true for sRGB gamma-space blending, false for linear blending
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen::prelude::wasm_bindgen]
pub fn set_blend_color_space(is_srgb: bool) {
    window::set_blend_color_space_global(is_srgb);
}

/// Set brush size (diameter in pixels)
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen::prelude::wasm_bindgen]
pub fn set_brush_size(size: f32) {
    window::set_brush_size_global(size);
}

/// Set brush flow/opacity per dab (0.0-1.0)
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen::prelude::wasm_bindgen]
pub fn set_brush_flow(flow: f32) {
    window::set_brush_flow_global(flow);
}

/// Set brush edge hardness (0.0=soft, 1.0=hard)
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen::prelude::wasm_bindgen]
pub fn set_brush_hardness(hardness: f32) {
    window::set_brush_hardness_global(hardness);
}

/// Set brush color (sRGB values 0.0-1.0)
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen::prelude::wasm_bindgen]
pub fn set_brush_color(r: f32, g: f32, b: f32, a: f32) {
    window::set_brush_color_global(r, g, b, a);
}

/// Set input filter mode
/// 
/// # Arguments
/// * `pen_only` - true for pen-only mode, false for pen+touch mode
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen::prelude::wasm_bindgen]
pub fn set_input_filter_mode(pen_only: bool) {
    window::set_input_filter_mode_global(pen_only);
}

/// Clear the canvas to the current clear color
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen::prelude::wasm_bindgen]
pub fn clear_canvas() {
    window::clear_canvas_global();
}

/// Get canvas width in pixels
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen::prelude::wasm_bindgen]
pub fn get_canvas_width() -> u32 {
    window::get_canvas_width_global()
}

/// Get canvas height in pixels
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen::prelude::wasm_bindgen]
pub fn get_canvas_height() -> u32 {
    window::get_canvas_height_global()
}

/// Export canvas as RGBA8 image data
/// Returns a Uint8ClampedArray containing RGBA pixel data (width * height * 4 bytes)
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen::prelude::wasm_bindgen]
pub async fn get_canvas_image_data() -> Result<js_sys::Uint8ClampedArray, wasm_bindgen::JsValue> {
    window::get_canvas_image_data_global().await
}

// Future: FFI exports for Flutter integration
// #[no_mangle]
// pub extern "C" fn drawing_canvas_create() -> *mut App { ... }
// #[no_mangle]
// pub extern "C" fn drawing_canvas_render(app: *mut App) { ... }
// etc.
