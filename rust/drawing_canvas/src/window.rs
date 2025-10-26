//! Window and Event Loop Management
//!
//! This module contains the shared windowing logic used by both
//! WASM (lib.rs) and desktop (main.rs) entry points.

use crate::{App, Renderer};
use crate::debug;
use crate::input::{PointerEvent, PointerEventType};
use winit::application::ApplicationHandler;
use winit::event::{WindowEvent, ElementState, Force};
use winit::event_loop::ActiveEventLoop;
use winit::window::{Window, WindowAttributes, WindowId};

#[cfg(target_arch = "wasm32")]
use std::cell::RefCell;
use std::sync::{Mutex, OnceLock};

#[cfg(target_arch = "wasm32")]
thread_local! {
    static GLOBAL_APP_WRAPPER: RefCell<Option<*mut AppWrapper>> = RefCell::new(None);
}

// Global brush parameters that persist across app reinitialization
// This is separate from App state so settings don't get reset when canvas is recreated
static GLOBAL_BRUSH_PARAMS: OnceLock<Mutex<crate::brush::BrushParams>> = OnceLock::new();

/// Initialize global brush params if not already initialized
fn ensure_global_brush_params() -> &'static Mutex<crate::brush::BrushParams> {
    GLOBAL_BRUSH_PARAMS.get_or_init(|| {
        log::info!("Initializing global brush params with defaults");
        Mutex::new(crate::brush::BrushParams::default())
    })
}

/// Get the current global brush parameters (thread-safe)
fn get_global_brush_params() -> crate::brush::BrushParams {
    *ensure_global_brush_params().lock().unwrap()
}

/// Update global brush parameters (thread-safe)
fn update_global_brush_params<F>(updater: F)
where
    F: FnOnce(&mut crate::brush::BrushParams),
{
    let mut params = ensure_global_brush_params().lock().unwrap();
    updater(&mut *params);
    log::info!("Global brush params updated: size={}, flow={}, hardness={}", 
               params.size, params.flow, params.hardness);
}

/// Set the global app wrapper reference (WASM only)
#[cfg(target_arch = "wasm32")]
pub fn set_global_app_wrapper(wrapper: &mut AppWrapper) {
    GLOBAL_APP_WRAPPER.with(|global| {
        *global.borrow_mut() = Some(wrapper as *mut AppWrapper);
    });
}

/// Set blend color space from JavaScript (WASM only)
#[cfg(target_arch = "wasm32")]
pub fn set_blend_color_space_global(is_srgb: bool) {
    use crate::renderer::BlendColorSpace;
    
    GLOBAL_APP_WRAPPER.with(|global| {
        if let Some(wrapper_ptr) = *global.borrow() {
            unsafe {
                let wrapper = &mut *wrapper_ptr;
                if let (Some(app), Some(renderer)) = (&mut wrapper.app, &mut wrapper.renderer) {
                    let color_space = if is_srgb {
                        BlendColorSpace::Srgb
                    } else {
                        BlendColorSpace::Linear
                    };
                    
                    app.set_blend_color_space(color_space, renderer);
                    
                    // Request a redraw
                    if let Some(window) = &wrapper.window {
                        window.request_redraw();
                    }
                    
                    log::info!("✅ Blend color space changed to: {:?}", color_space);
                } else {
                    log::warn!("App or renderer not yet initialized");
                }
            }
        } else {
            log::warn!("Global app wrapper not set");
        }
    });
}

/// Set brush size from JavaScript (WASM only)
#[cfg(target_arch = "wasm32")]
pub fn set_brush_size_global(size: f32) {
    log::info!("set_brush_size_global called: {}", size);
    
    // Update global brush params (persists across app reinit)
    update_global_brush_params(|params| {
        params.size = size.max(0.1);
    });
    
    // Also update current app if it exists
    GLOBAL_APP_WRAPPER.with(|global| {
        if let Some(wrapper_ptr) = *global.borrow() {
            unsafe {
                let wrapper = &mut *wrapper_ptr;
                if let Some(app) = &mut wrapper.app {
                    app.brush_state_mut().params.size = size.max(0.1);
                    log::info!("Updated app brush size to: {}", size);
                }
            }
        }
    });
}

/// Set brush flow from JavaScript (WASM only)
#[cfg(target_arch = "wasm32")]
pub fn set_brush_flow_global(flow: f32) {
    log::info!("set_brush_flow_global called: {}", flow);
    
    // Update global brush params (persists across app reinit)
    update_global_brush_params(|params| {
        params.flow = flow.clamp(0.0, 1.0);
    });
    
    // Also update current app if it exists
    GLOBAL_APP_WRAPPER.with(|global| {
        if let Some(wrapper_ptr) = *global.borrow() {
            unsafe {
                let wrapper = &mut *wrapper_ptr;
                if let Some(app) = &mut wrapper.app {
                    app.brush_state_mut().params.flow = flow.clamp(0.0, 1.0);
                    log::info!("Updated app brush flow to: {}", flow);
                }
            }
        }
    });
}

/// Set brush hardness from JavaScript (WASM only)
#[cfg(target_arch = "wasm32")]
pub fn set_brush_hardness_global(hardness: f32) {
    log::info!("set_brush_hardness_global called: {}", hardness);
    
    // Update global brush params (persists across app reinit)
    update_global_brush_params(|params| {
        params.hardness = hardness.clamp(0.0, 1.0);
    });
    
    // Also update current app if it exists
    GLOBAL_APP_WRAPPER.with(|global| {
        if let Some(wrapper_ptr) = *global.borrow() {
            unsafe {
                let wrapper = &mut *wrapper_ptr;
                if let Some(app) = &mut wrapper.app {
                    app.brush_state_mut().params.hardness = hardness.clamp(0.0, 1.0);
                    log::info!("Updated app brush hardness to: {}", hardness);
                }
            }
        }
    });
}

/// Set brush color from JavaScript (WASM only)
#[cfg(target_arch = "wasm32")]
pub fn set_brush_color_global(r: f32, g: f32, b: f32, a: f32) {
    log::info!("set_brush_color_global called: [{}, {}, {}, {}]", r, g, b, a);
    
    // Update global brush params (persists across app reinit)
    update_global_brush_params(|params| {
        params.color = [
            r.clamp(0.0, 1.0),
            g.clamp(0.0, 1.0),
            b.clamp(0.0, 1.0),
            a.clamp(0.0, 1.0),
        ];
    });
    
    // Also update current app if it exists
    GLOBAL_APP_WRAPPER.with(|global| {
        if let Some(wrapper_ptr) = *global.borrow() {
            unsafe {
                let wrapper = &mut *wrapper_ptr;
                if let Some(app) = &mut wrapper.app {
                    app.brush_state_mut().params.color = [
                        r.clamp(0.0, 1.0),
                        g.clamp(0.0, 1.0),
                        b.clamp(0.0, 1.0),
                        a.clamp(0.0, 1.0),
                    ];
                    log::info!("Updated app brush color to: [{}, {}, {}, {}]", r, g, b, a);
                }
            }
        }
    });
}

/// Clear canvas from JavaScript (WASM only)
#[cfg(target_arch = "wasm32")]
pub fn clear_canvas_global() {
    GLOBAL_APP_WRAPPER.with(|global| {
        if let Some(wrapper_ptr) = *global.borrow() {
            unsafe {
                let wrapper = &mut *wrapper_ptr;
                if let (Some(app), Some(renderer)) = (&mut wrapper.app, &mut wrapper.renderer) {
                    app.clear_canvas(renderer);
                    
                    // Request a redraw
                    if let Some(window) = &wrapper.window {
                        window.request_redraw();
                    }
                    
                    log::info!("Canvas cleared");
                } else {
                    log::warn!("App or renderer not yet initialized");
                }
            }
        } else {
            log::warn!("Global app wrapper not set");
        }
    });
}

/// Get canvas width from JavaScript (WASM only)
#[cfg(target_arch = "wasm32")]
pub fn get_canvas_width_global() -> u32 {
    GLOBAL_APP_WRAPPER.with(|global| {
        if let Some(wrapper_ptr) = *global.borrow() {
            unsafe {
                let wrapper = &*wrapper_ptr;
                if let Some(renderer) = &wrapper.renderer {
                    renderer.size().width
                } else {
                    0
                }
            }
        } else {
            0
        }
    })
}

/// Get canvas height from JavaScript (WASM only)
#[cfg(target_arch = "wasm32")]
pub fn get_canvas_height_global() -> u32 {
    GLOBAL_APP_WRAPPER.with(|global| {
        if let Some(wrapper_ptr) = *global.borrow() {
            unsafe {
                let wrapper = &*wrapper_ptr;
                if let Some(renderer) = &wrapper.renderer {
                    renderer.size().height
                } else {
                    0
                }
            }
        } else {
            0
        }
    })
}

/// Export canvas as RGBA8 image data from JavaScript (WASM only)
#[cfg(target_arch = "wasm32")]
pub async fn get_canvas_image_data_global() -> Result<js_sys::Uint8ClampedArray, wasm_bindgen::JsValue> {
    use wasm_bindgen::JsValue;
    
    // Read back GPU texture data - this is async and requires waiting for GPU->CPU transfer
    let result = GLOBAL_APP_WRAPPER.with(|global| -> Option<*mut Renderer> {
        if let Some(wrapper_ptr) = *global.borrow() {
            unsafe {
                let wrapper = &mut *wrapper_ptr;
                wrapper.renderer.as_mut().map(|r| r as *mut Renderer)
            }
        } else {
            None
        }
    });
    
    match result {
        Some(renderer_ptr) => {
            // Call async method outside the closure to avoid borrow issues
            let renderer = unsafe { &*renderer_ptr };
            let rgba8_data = renderer.read_canvas_rgba8()
                .await
                .map_err(|e| JsValue::from_str(&e))?;
            
            // Convert Vec<u8> to Uint8ClampedArray for JavaScript
            let js_array = js_sys::Uint8ClampedArray::new_with_length(rgba8_data.len() as u32);
            js_array.copy_from(&rgba8_data);
            
            log::info!("Exported canvas image data: {} bytes", rgba8_data.len());
            Ok(js_array)
        }
        None => Err(JsValue::from_str("Renderer not yet initialized"))
    }
}

/// Check if canvas needs to be relocated to a new container (WASM only)
/// This is called on every init_drawing_canvas() to handle Flutter rebuilds
#[cfg(target_arch = "wasm32")]
pub fn check_and_relocate_canvas_global() {
    use wasm_bindgen::JsCast;
    use winit::platform::web::WindowExtWeb;
    
    GLOBAL_APP_WRAPPER.with(|global| {
        if let Some(wrapper_ptr) = *global.borrow() {
            unsafe {
                let wrapper = &*wrapper_ptr;
                
                // Only proceed if we have a window
                if let Some(window_arc) = &wrapper.window {
                    let canvas = match window_arc.canvas() {
                        Some(c) => c,
                        None => {
                            log::warn!("Failed to get canvas from window");
                            return;
                        }
                    };
                    
                    let document = web_sys::window()
                        .and_then(|win| win.document())
                        .expect("Failed to get document");
                    
                    // Find the canvas-container that doesn't have a canvas child yet
                    let containers = match document.query_selector_all("[data-canvas-container]") {
                        Ok(c) => c,
                        Err(e) => {
                            log::warn!("Failed to query canvas containers: {:?}", e);
                            return;
                        }
                    };
                    
                    log::info!("🔍 Checking {} container(s) for canvas relocation", containers.length());
                    
                    let mut empty_container: Option<web_sys::Element> = None;
                    for i in 0..containers.length() {
                        if let Some(elem) = containers.get(i) {
                            if let Ok(html_elem) = elem.dyn_into::<web_sys::HtmlElement>() {
                                let container_id = html_elem.id();
                                let has_canvas = html_elem.query_selector("canvas").ok().flatten().is_some();
                                log::info!("  Container '{}': has_canvas={}", container_id, has_canvas);
                                
                                // Check if this container already has a canvas child
                                if !has_canvas {
                                    empty_container = Some(html_elem.into());
                                    break;
                                }
                            }
                        }
                    }
                    
                    // If we found a new empty container, move the canvas there
                    if let Some(new_container) = empty_container {
                        // Check if canvas is in a different container
                        if let Some(current_parent) = canvas.parent_element() {
                            if current_parent.id() != new_container.id() {
                                log::info!("🔄 Moving canvas from container '{}' to '{}'", 
                                    current_parent.id(), new_container.id());
                                
                                // Move canvas to new container
                                if let Err(e) = new_container.append_child(&canvas) {
                                    log::error!("Failed to move canvas to new container: {:?}", e);
                                    return;
                                }
                                
                                log::info!("✅ Canvas moved to new container");
                            } else {
                                log::info!("Canvas already in correct container: {}", new_container.id());
                            }
                        } else {
                            // Canvas has no parent (orphaned), attach to new container
                            log::info!("🔄 Attaching orphaned canvas to container '{}'", new_container.id());
                            if let Err(e) = new_container.append_child(&canvas) {
                                log::error!("Failed to attach canvas to container: {:?}", e);
                                return;
                            }
                            log::info!("✅ Canvas attached to container");
                        }
                    } else {
                        log::info!("No empty container found (canvas already placed or no containers available)");
                    }
                }
            }
        } else {
            log::warn!("Global app wrapper not set");
        }
    });
}

/// Wrapper for the application window and state
pub struct AppWrapper {
    pub window: Option<std::sync::Arc<Box<dyn Window>>>,
    pub renderer: Option<Renderer>,
    pub app: Option<App>,
    cursor_position: Option<winit::dpi::PhysicalPosition<f64>>,
    last_pointer_move_time: f64, // Used for de-duplicating erroneous pointer move events on iOS webkit
    #[cfg(not(target_arch = "wasm32"))]
    start_time: Option<std::time::Instant>,
}

impl AppWrapper {
    /// Create a new empty app wrapper
    pub fn new() -> Self {
        Self {
            window: None,
            renderer: None,
            app: None,
            cursor_position: None,
            last_pointer_move_time: 0.0,
            #[cfg(not(target_arch = "wasm32"))]
            start_time: Some(std::time::Instant::now()),
        }
    }

    /// Extract pressure from Force enum
    fn extract_pressure(force: &Option<Force>) -> f32 {
        match force {
            Some(Force::Normalized(p)) => *p as f32,
            Some(Force::Calibrated { force, max_possible_force, .. }) => {
                (force / max_possible_force) as f32
            }
            None => 1.0,
        }
    }

    /// Extract tablet tool data (pressure, tilt, azimuth, twist) from TabletToolData
    fn extract_tablet_data(data: &winit::event::TabletToolData) -> (f32, Option<[f32; 2]>, Option<f32>, Option<f32>) {
        let pressure = Self::extract_pressure(&data.force);
        
        // Extract tilt (in degrees, 0-90) - need to clone since tilt() consumes self
        let tilt = data.clone().tilt().map(|t| [t.x as f32, t.y as f32]);
        
        // Extract azimuth/altitude angle (in radians) - need to clone since angle() consumes self
        let azimuth = data.clone().angle().map(|a| a.azimuth as f32);
        
        // Extract twist/rotation (in degrees, 0-359)
        let twist = data.twist.map(|t| t as f32);
        
        (pressure, tilt, azimuth, twist)
    }

    /// Extract input data from ButtonSource (for PointerButton events)
    fn extract_button_data(button: &winit::event::ButtonSource) -> (f32, Option<[f32; 2]>, Option<f32>, Option<f32>) {
        match button {
            winit::event::ButtonSource::Mouse(_) => {
                // Mouse has no pressure or tilt
                (1.0, None, None, None)
            }
            winit::event::ButtonSource::Touch { force, .. } => {
                // Touch may have pressure via force
                let pressure = Self::extract_pressure(force);
                (pressure, None, None, None)
            }
            winit::event::ButtonSource::TabletTool { data, .. } => {
                // Stylus/tablet tool with full data!
                Self::extract_tablet_data(data)
            }
            winit::event::ButtonSource::Unknown(_) => {
                // Unknown source, assume no pressure
                (1.0, None, None, None)
            }
        }
    }

    /// Extract input data from PointerSource (for PointerMoved events)
    /// Returns (pressure, tilt, azimuth, twist, pointer_type_name)
    fn extract_pointer_data(source: &winit::event::PointerSource) -> (f32, Option<[f32; 2]>, Option<f32>, Option<f32>, &'static str) {
        match source {
            winit::event::PointerSource::Mouse => {
                // Mouse has no pressure or tilt
                (1.0, None, None, None, "Mouse")
            }
            winit::event::PointerSource::Touch { .. } => {
                // Touch may have pressure via force (NOT RELIABLE)
                // let pressure = Self::extract_pressure(force);
                (1.0, None, None, None, "Touch")
            }
            winit::event::PointerSource::TabletTool { data, .. } => {
                // Stylus/tablet tool with full data!
                let (pressure, tilt, azimuth, twist) = Self::extract_tablet_data(data);
                (pressure, tilt, azimuth, twist, "Stylus/Tablet")
            }
            winit::event::PointerSource::Unknown => {
                // Unknown source, assume no pressure
                (1.0, None, None, None, "Unknown")
            }
        }
    }

    /// Set up a ResizeObserver to watch the container and resize the canvas accordingly
    #[cfg(target_arch = "wasm32")]
    fn setup_resize_observer(container: &web_sys::Element, window: std::sync::Arc<Box<dyn Window>>) {
        use wasm_bindgen::prelude::*;
        use wasm_bindgen::JsCast;

        let window_clone = window.clone();

        let callback = Closure::<dyn Fn(js_sys::Array)>::new(move |entries: js_sys::Array| {
            // Get the first entry (our container)
            if let Some(entry) = entries.get(0).dyn_into::<web_sys::ResizeObserverEntry>().ok() {
                let content_rect = entry.content_rect();
                let width = content_rect.width() as u32;
                let height = content_rect.height() as u32;
                
                log::info!("📐 Container resized to: {}x{}", width, height);
                
                // Request the window to resize to match the container
                if width > 0 && height > 0 {
                    let new_size = winit::dpi::LogicalSize::new(width, height);
                    let _ = window_clone.request_surface_size(new_size.into());
                }
            }
        });

        let observer = web_sys::ResizeObserver::new(callback.as_ref().unchecked_ref())
            .expect("Failed to create ResizeObserver");
        
        observer.observe(container);
        
        log::info!("✅ ResizeObserver set up on canvas-container");
        
        // Keep the callback alive by leaking it (it needs to live for the app's lifetime)
        // TODO: Store callback somewhere to properly manage its lifetime? Maybe not needed if app
        // only lives as long as the page where it's embedded?
        callback.forget();
    }

    fn create_app_and_renderer(&mut self, window: std::sync::Arc<Box<dyn Window>>, initial_size: winit::dpi::PhysicalSize<u32>) {
        #[cfg(target_arch = "wasm32")]
        {
            // WASM: Initialize asynchronously
            let window_for_renderer = window.clone();
            let app_ptr = &mut self.app as *mut Option<App>;
            let renderer_ptr = &mut self.renderer as *mut Option<Renderer>;
            let window_for_redraw = window.clone();

            wasm_bindgen_futures::spawn_local(async move {
                debug::update_status("Creating renderer...");
                let mut renderer = Renderer::new(window_for_renderer, initial_size).await;
                
                // Create app with global brush params (persists across reinit)
                let brush_params = get_global_brush_params();
                log::info!("Initializing app with global brush params: size={}, flow={}, hardness={}", 
                           brush_params.size, brush_params.flow, brush_params.hardness);
                let mut app = App::with_brush_params(brush_params);
                
                // Clear canvas to initial color
                app.clear_canvas(&mut renderer);

                unsafe {
                    *renderer_ptr = Some(renderer);
                    *app_ptr = Some(app);
                }

                log::info!("✅ Renderer initialized successfully with persisted brush settings");
                debug::update_status("✅ Renderer ready");
                debug::update_stage("Ready to draw!");
                
                // Request initial frame now that we're ready
                window_for_redraw.request_redraw();
            });
        }

        #[cfg(not(target_arch = "wasm32"))]
        {
            // Desktop: Block on async initialization
            let mut renderer = pollster::block_on(Renderer::new(window.clone(), initial_size));
            
            // Create app with global brush params (persists across reinit)
            let brush_params = get_global_brush_params();
            log::info!("Initializing app with global brush params: size={}, flow={}, hardness={}", 
                       brush_params.size, brush_params.flow, brush_params.hardness);
            let mut app = App::with_brush_params(brush_params);
            
            // Clear canvas to initial color
            app.clear_canvas(&mut renderer);

            self.renderer = Some(renderer);
            self.app = Some(app);

            log::info!("✅ Renderer created with persisted brush settings");
        }
    }
}

impl ApplicationHandler for AppWrapper {
    fn can_create_surfaces(&mut self, event_loop: &dyn ActiveEventLoop) {
        debug::update_stage("Creating window...");
        let initial_size = winit::dpi::PhysicalSize::new(800, 600);
        
        // On WASM, we need to check if we should move the canvas to a new container
        // This handles layout changes where Flutter destroys the old container
        #[cfg(target_arch = "wasm32")]
        if self.window.is_some() {
            use winit::platform::web::WindowExtWeb;
            use wasm_bindgen::JsCast;
            
            let window_arc = self.window.as_ref().unwrap();
            let canvas = window_arc.canvas().expect("Failed to get canvas from window");
            
            let document = web_sys::window()
                .and_then(|win| win.document())
                .expect("Failed to get document");
            
            // Find the canvas-container that doesn't have a canvas child yet
            let containers = document.query_selector_all("[data-canvas-container]")
                .expect("Failed to query canvas containers");
            
            let mut empty_container: Option<web_sys::Element> = None;
            for i in 0..containers.length() {
                if let Some(elem) = containers.get(i) {
                    if let Ok(html_elem) = elem.dyn_into::<web_sys::HtmlElement>() {
                        // Check if this container already has a canvas child
                        if html_elem.query_selector("canvas").ok().flatten().is_none() {
                            empty_container = Some(html_elem.into());
                            break;
                        }
                    }
                }
            }
            
            // If we found a new empty container, move the canvas there
            if let Some(new_container) = empty_container {
                // Check if canvas is in a different container
                if let Some(current_parent) = canvas.parent_element() {
                    if current_parent.id() != new_container.id() {
                        log::info!("🔄 Moving canvas from container '{}' to '{}'", 
                            current_parent.id(), new_container.id());
                        
                        // Move canvas to new container
                        new_container.append_child(&canvas)
                            .expect("Failed to move canvas to new container");
                        
                        log::info!("✅ Canvas moved to new container");
                    } else {
                        log::info!("Canvas already in correct container: {}", new_container.id());
                    }
                } else {
                    // Canvas has no parent (orphaned), attach to new container
                    log::info!("🔄 Attaching orphaned canvas to container '{}'", new_container.id());
                    new_container.append_child(&canvas)
                        .expect("Failed to attach canvas to container");
                    log::info!("✅ Canvas attached to container");
                }
            }
            
            drop(canvas);
            return; // Window already exists, just needed to move canvas
        }
        
        if self.window.is_none() {
            // Create the window
            let window_attributes = WindowAttributes::default()
                .with_title("Drawing Canvas")
                .with_surface_size(initial_size);

            let window = event_loop
                .create_window(window_attributes)
                .expect("Failed to create window");

            log::info!("Window created: {:?}", window.surface_size());
            debug::update_status("✅ Window created");

            let window_arc = std::sync::Arc::new(window);
            self.window = Some(window_arc.clone());

            // On WASM, append the canvas to the DOM now
            #[cfg(target_arch = "wasm32")]
            {
                use winit::platform::web::WindowExtWeb;
                use wasm_bindgen::JsCast;

                // Get canvas reference - this borrows it briefly
                let canvas = window_arc.canvas().expect("Failed to get canvas from window");

                // Append canvas to DOM
                let document = web_sys::window()
                    .and_then(|win| win.document())
                    .expect("Failed to get document");
                
                // Find the canvas-container that doesn't have a canvas child yet
                // This handles multiple practice sessions where old containers may still exist
                let containers = document.query_selector_all("[data-canvas-container]")
                    .expect("Failed to query canvas containers");
                
                let mut container: Option<web_sys::Element> = None;
                for i in 0..containers.length() {
                    if let Some(elem) = containers.get(i) {
                        if let Ok(html_elem) = elem.dyn_into::<web_sys::HtmlElement>() {
                            // Check if this container already has a canvas child
                            if html_elem.query_selector("canvas").ok().flatten().is_none() {
                                container = Some(html_elem.into());
                                break;
                            }
                        }
                    }
                }
                
                let container = container.expect("Failed to find empty canvas-container element");
                log::info!("Found empty canvas container: {:?}", container.id());

                container.append_child(&canvas)
                    .expect("Failed to append canvas to container");
                
                // Drop the canvas reference before continuing
                drop(canvas);

               // NOW set the size (canvas is in DOM, so winit can apply CSS)
               // IMPORTANT: On web we can't set the canvas size until it's in the DOM.
               let _ = window_arc.request_surface_size(initial_size.into());
               log::info!("✅ Canvas appended to DOM and size requested: {:?}", initial_size);
               debug::update_status("✅ Canvas in DOM");
               debug::update_stage("Initializing renderer...");

                // Log canvas info (get a fresh reference)
                let canvas = window_arc.canvas().expect("Failed to get canvas from window");
                log::info!("Canvas size: {:?} x {:?}", canvas.width(), canvas.height());
                log::info!("Canvas CSS: width={:?}, height={:?}", 
                    canvas.style().get_property_value("width").ok(),
                    canvas.style().get_property_value("height").ok()
                );
                drop(canvas);

                // Set up ResizeObserver to watch container and update canvas size
                let window_for_resize = window_arc.clone();
                Self::setup_resize_observer(&container, window_for_resize);

                // Initialize renderer async
                log::info!("🔧 Initializing renderer with size: {:?}", initial_size);
            }

            self.create_app_and_renderer(window_arc.clone(), initial_size);
        }
    }

    fn resumed(&mut self, _: &dyn ActiveEventLoop) {
        log::info!("Application resumed");
    }

    fn window_event(&mut self, event_loop: &dyn ActiveEventLoop, _id: WindowId, event: WindowEvent) {
        match event {
            WindowEvent::CloseRequested => {
                log::info!("Close requested, exiting");
                event_loop.exit();
            }
            WindowEvent::SurfaceResized(physical_size) => {
                log::info!("⚠️ RESIZE EVENT: {:?}", physical_size);
                debug::update_stage(&format!("Resized: {}x{}", physical_size.width, physical_size.height));
                
                // Log canvas state during resize
                #[cfg(target_arch = "wasm32")]
                {
                    if let Some(window) = &self.window {
                        use winit::platform::web::WindowExtWeb;
                        let canvas = window.canvas().expect("Canvas should exist");
                        log::info!("  Canvas attributes: {}x{}", canvas.width(), canvas.height());
                        log::info!("  Canvas CSS: width={:?}, height={:?}", 
                            canvas.style().get_property_value("width").ok(),
                            canvas.style().get_property_value("height").ok()
                        );
                    }
                }
                
                // Skip invalid sizes
                if physical_size.width == 0 || physical_size.height == 0 {
                    log::warn!("Ignoring resize to zero size: {:?}", physical_size);
                    return;
                }

                if let Some(renderer) = &mut self.renderer {
                    renderer.resize(physical_size);
                    log::info!("✅ Surface configured with size: {:?}", physical_size);
                    debug::update_status(&format!("Surface: {}x{}", physical_size.width, physical_size.height));
                }
            }
            WindowEvent::RedrawRequested => {
                // Render if we have valid components (renderer will check surface validity)
                if let (Some(renderer), Some(app)) = (&mut self.renderer, &mut self.app) {
                    app.render(renderer);
                    debug::increment_frame_count();
                    // Don't request another redraw - we're in Wait mode, only redraw on events
                }
            }
            WindowEvent::PointerButton { button, state, primary, position, time_stamp, .. } => {
                // Handle pointer button press/release (mouse, stylus, touch)
                // Respond to primary button (left click, stylus tip) or any touch input
                let is_touch = matches!(button, winit::event::ButtonSource::Touch { .. });
                let should_handle = primary || is_touch;
                
                if should_handle {
                    // Use position from the event itself - this is more reliable than cursor_position
                    // especially for touch Up events where there may not be a final Move event
                    let event_pos = position;
                    
                    // Also update cursor_position for consistency
                    self.cursor_position = Some(event_pos);
                    
                    // Extract pressure and tablet data from the button source
                    let (pressure, tilt, azimuth, twist) = Self::extract_button_data(&button);
                    
                    let event = PointerEvent {
                        position: [event_pos.x as f32, event_pos.y as f32],
                        pressure,
                        tilt,
                        azimuth,
                        twist,
                        timestamp: time_stamp,
                        event_type: match state {
                            ElementState::Pressed => PointerEventType::Down,
                            ElementState::Released => PointerEventType::Up,
                        },
                    };

                    if let Some(app) = &mut self.app {
                        app.queue_input_event(event);
                        let input_type = if is_touch { "touch" } else { "pointer" };
                        log::debug!("{} button {:?} at ({}, {}), pressure={}", 
                            input_type, state, event_pos.x, event_pos.y, pressure);
                    }

                    // Request redraw to process the input
                    if let Some(window) = &self.window {
                        window.request_redraw();
                    }
                }
            }
            WindowEvent::PointerMoved { source, position, time_stamp, .. } => {
                if time_stamp <= self.last_pointer_move_time {
                    // Duplicate or out-of-order event, ignore
                    return;
                }
                self.last_pointer_move_time = time_stamp;

                // Track cursor position
                self.cursor_position = Some(position);
                
                // Extract pressure and tablet data from the pointer source
                let (pressure, tilt, azimuth, twist, ptr_type) = Self::extract_pointer_data(&source);
                
                // Update debug overlay with pointer info
                debug::update_pointer(
                    ptr_type,
                    Some(position.x as f32),
                    Some(position.y as f32),
                    Some(pressure),
                    tilt,
                    azimuth,
                    twist,
                );
                
                // Handle pointer movement
                if let Some(app) = &mut self.app {
                    let event = PointerEvent {
                        position: [position.x as f32, position.y as f32],
                        pressure,
                        tilt,
                        azimuth,
                        twist,
                        timestamp: time_stamp,
                        event_type: PointerEventType::Move,
                    };

                    app.queue_input_event(event);

                    // Only request redraw if we have pending input (drawing)
                    if app.has_pending_input() {
                        if let Some(window) = &self.window {
                            window.request_redraw();
                        }
                    }
                }
            }
            _ => {}
        }
    }
}
