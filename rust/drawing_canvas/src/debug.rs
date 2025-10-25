//! Debug overlay utilities for web platform
//! 
//! Provides functions to update the on-screen debug display
//! for tracking initialization stages and pointer input data.

#[cfg(target_arch = "wasm32")]
use wasm_bindgen::prelude::*;

/// Update the debug status line
#[cfg(target_arch = "wasm32")]
pub fn update_status(status: &str) {
    #[wasm_bindgen]
    extern "C" {
        #[wasm_bindgen(js_name = updateDebugStatus)]
        fn update_debug_status(status: &str);
    }
    update_debug_status(status);
}

/// Update the current stage indicator
#[cfg(target_arch = "wasm32")]
pub fn update_stage(stage: &str) {
    #[wasm_bindgen]
    extern "C" {
        #[wasm_bindgen(js_name = updateDebugStage)]
        fn update_debug_stage(stage: &str);
    }
    update_debug_stage(stage);
}

/// Update pointer information in the debug overlay
#[cfg(target_arch = "wasm32")]
pub fn update_pointer(
    ptr_type: &str,
    x: Option<f32>,
    y: Option<f32>,
    pressure: Option<f32>,
    tilt: Option<[f32; 2]>,
    azimuth: Option<f32>,
    twist: Option<f32>,
) {
    #[wasm_bindgen]
    extern "C" {
        #[wasm_bindgen(js_name = updateDebugPointer)]
        fn update_debug_pointer(
            ptr_type: &str,
            x: Option<f32>,
            y: Option<f32>,
            pressure: Option<f32>,
            tilt_x: Option<f32>,
            tilt_y: Option<f32>,
            azimuth: Option<f32>,
            twist: Option<f32>,
        );
    }
    
    let (tilt_x, tilt_y) = tilt.map(|t| (Some(t[0]), Some(t[1]))).unwrap_or((None, None));
    update_debug_pointer(ptr_type, x, y, pressure, tilt_x, tilt_y, azimuth, twist);
}

/// Increment the frame counter
#[cfg(target_arch = "wasm32")]
pub fn increment_frame_count() {
    #[wasm_bindgen]
    extern "C" {
        #[wasm_bindgen(js_name = incrementFrameCount)]
        fn increment_frame_count_js();
    }
    increment_frame_count_js();
}

// No-op versions for non-WASM platforms
#[cfg(not(target_arch = "wasm32"))]
pub fn update_status(_status: &str) {}

#[cfg(not(target_arch = "wasm32"))]
pub fn update_stage(_stage: &str) {}

#[cfg(not(target_arch = "wasm32"))]
pub fn update_pointer(
    _ptr_type: &str,
    _x: Option<f32>,
    _y: Option<f32>,
    _pressure: Option<f32>,
    _tilt: Option<[f32; 2]>,
    _azimuth: Option<f32>,
    _twist: Option<f32>,
) {}

#[cfg(not(target_arch = "wasm32"))]
pub fn increment_frame_count() {}

/// Check if sRGB blend mode is enabled (WASM only)
#[cfg(target_arch = "wasm32")]
pub fn is_srgb_blend_mode() -> bool {
    let window = match web_sys::window() {
        Some(w) => w,
        None => return false,
    };

    let js_val = js_sys::Reflect::get(&window, &wasm_bindgen::JsValue::from_str("blendColorSpaceIsSrgb"))
        .unwrap_or(wasm_bindgen::JsValue::FALSE);
    
    js_val.as_bool().unwrap_or(false)
}

#[cfg(not(target_arch = "wasm32"))]
pub fn is_srgb_blend_mode() -> bool {
    false
}
