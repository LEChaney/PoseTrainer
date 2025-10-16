//! Standalone Drawing Canvas Application (Desktop)
//!
//! This binary runs the drawing canvas as a native desktop application.
//! For WASM/web builds, the entry point is in lib.rs (wasm_start).

use drawing_canvas::AppWrapper;
use winit::event_loop::{EventLoop, ControlFlow};

fn main() {
    env_logger::init();
    
    log::info!("🚀 Starting drawing canvas desktop app");
    
    let event_loop = EventLoop::new().expect("Failed to create event loop");
    event_loop.set_control_flow(ControlFlow::Wait);
    
    let mut app_wrapper = AppWrapper::new();
    
    event_loop.run_app(&mut app_wrapper).expect("Event loop error");
}
