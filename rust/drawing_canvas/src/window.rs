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

#[cfg(target_arch = "wasm32")]
thread_local! {
    static GLOBAL_APP_WRAPPER: RefCell<Option<*mut AppWrapper>> = RefCell::new(None);
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

/// Wrapper for the application window and state
pub struct AppWrapper {
    pub window: Option<std::sync::Arc<Box<dyn Window>>>,
    pub renderer: Option<Renderer>,
    pub app: Option<App>,
    cursor_position: Option<winit::dpi::PhysicalPosition<f64>>,
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
            winit::event::PointerSource::Touch { force, .. } => {
                // Touch may have pressure via force
                let pressure = Self::extract_pressure(force);
                (pressure, None, None, None, "Touch")
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

    /// Get timestamp in milliseconds since app start
    fn get_timestamp(&self) -> f64 {
        #[cfg(not(target_arch = "wasm32"))]
        {
            self.start_time
                .map(|start| start.elapsed().as_secs_f64() * 1000.0)
                .unwrap_or(0.0)
        }
        
        #[cfg(target_arch = "wasm32")]
        {
            // On WASM, use the browser's performance.now() API
            web_sys::window()
                .and_then(|win| win.performance())
                .map(|perf| perf.now())
                .unwrap_or(0.0)
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
                let mut app = App::new();
                
                // Clear canvas to initial color
                app.clear_canvas(&mut renderer);

                unsafe {
                    *renderer_ptr = Some(renderer);
                    *app_ptr = Some(app);
                }

                log::info!("✅ Renderer initialized successfully");
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
            let mut app = App::new();
            
            // Clear canvas to initial color
            app.clear_canvas(&mut renderer);

            self.renderer = Some(renderer);
            self.app = Some(app);

            log::info!("✅ Renderer created (will be configured on first resize event)");
        }
    }
}

impl ApplicationHandler for AppWrapper {
    fn can_create_surfaces(&mut self, event_loop: &dyn ActiveEventLoop) {
        debug::update_stage("Creating window...");
        let initial_size = winit::dpi::PhysicalSize::new(800, 600);
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

                // Get canvas reference - this borrows it briefly
                let canvas = window_arc.canvas().expect("Failed to get canvas from window");

                // Append canvas to DOM
                let container = web_sys::window()
                    .and_then(|win| win.document())
                    .and_then(|doc| doc.get_element_by_id("canvas-container"))
                    .expect("Failed to find canvas-container element");

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

                if let (Some(renderer), Some(app)) = (&mut self.renderer, &mut self.app) {
                    renderer.resize(physical_size);
                    app.clear_canvas(renderer);
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
            WindowEvent::PointerButton { button, state, primary, .. } => {
                // Handle pointer button press/release (mouse, stylus, touch)
                // For now, only respond to primary button (left click, stylus tip, finger)
                if primary {
                    if let Some(cursor_pos) = self.cursor_position {
                        let timestamp = self.get_timestamp();
                        
                        // Extract pressure and tablet data from the button source
                        let (pressure, tilt, azimuth, twist) = Self::extract_button_data(&button);
                        
                        let event = PointerEvent {
                            position: [cursor_pos.x as f32, cursor_pos.y as f32],
                            pressure,
                            tilt,
                            azimuth,
                            twist,
                            timestamp,
                            event_type: match state {
                                ElementState::Pressed => PointerEventType::Down,
                                ElementState::Released => PointerEventType::Up,
                            },
                        };

                        if let Some(app) = &mut self.app {
                            app.queue_input_event(event);
                            log::debug!("Pointer button {:?} at {:?}, pressure={}", state, cursor_pos, pressure);
                        }

                        // Request redraw to process the input
                        if let Some(window) = &self.window {
                            window.request_redraw();
                        }
                    }
                }
            }
            WindowEvent::PointerMoved { source, position, .. } => {
                // Track cursor position
                self.cursor_position = Some(position);
                
                // Get timestamp before borrowing app
                let timestamp = self.get_timestamp();
                
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
                        timestamp,
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
