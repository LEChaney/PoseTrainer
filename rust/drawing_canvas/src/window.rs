//! Window and Event Loop Management
//!
//! This module contains the shared windowing logic used by both
//! WASM (lib.rs) and desktop (main.rs) entry points.

use crate::{App, Renderer};
use winit::application::ApplicationHandler;
use winit::event::WindowEvent;
use winit::event_loop::ActiveEventLoop;
use winit::window::{Window, WindowId};

/// Wrapper for the application window and state
pub struct AppWrapper {
    pub window: Option<std::sync::Arc<Window>>,
    pub renderer: Option<Renderer>,
    pub app: Option<App>,
}

impl AppWrapper {
    /// Create a new empty app wrapper
    pub fn new() -> Self {
        Self {
            window: None,
            renderer: None,
            app: None,
        }
    }
}

impl ApplicationHandler for AppWrapper {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        const WIDTH: u32 = 800;
        const HEIGHT: u32 = 600;
        if self.window.is_none() {
            let window_attributes = Window::default_attributes()
                .with_title("Drawing Canvas")
                .with_inner_size(winit::dpi::PhysicalSize::new(WIDTH, HEIGHT));

            let window = event_loop
                .create_window(window_attributes)
                .expect("Failed to create window");

            log::info!("Window created: {:?}", window.inner_size());

            #[cfg(target_arch = "wasm32")]
            {
                use winit::platform::web::WindowExtWebSys;

                let canvas = window.canvas().expect("Failed to get canvas from window");

                // Append canvas to DOM
                web_sys::window()
                    .and_then(|win| win.document())
                    .and_then(|doc| {
                        let container = doc.get_element_by_id("canvas-container")?;
                        container.append_child(&canvas).ok()?;
                        Some(())
                    })
                    .expect("Failed to append canvas to document");

               // NOW set the size (canvas is in DOM, so winit can apply CSS)
               // IMPORTANT: On web we can't set the canvas size until it's in the DOM.
               let desired_size = winit::dpi::PhysicalSize::new(WIDTH, HEIGHT);
               let _ = window.request_inner_size(desired_size);
               log::info!("✅ Canvas appended to DOM and size requested: {:?}", desired_size);

                log::info!("Canvas size: {:?} x {:?}", canvas.width(), canvas.height());
                log::info!("Canvas CSS: width={:?}, height={:?}", 
                    canvas.style().get_property_value("width").ok(),
                    canvas.style().get_property_value("height").ok()
                );

                // Wrap window in Arc and store it
                let window_arc = std::sync::Arc::new(window);
                self.window = Some(window_arc.clone());

                // Initialize renderer async
                log::info!("🔧 Initializing renderer with size: {:?}", desired_size);
                
                let window_for_renderer = window_arc.clone();
                let app_ptr = &mut self.app as *mut Option<App>;
                let renderer_ptr = &mut self.renderer as *mut Option<Renderer>;
                
                let window_for_redraw = window_arc.clone();

                wasm_bindgen_futures::spawn_local(async move {
                    let renderer = Renderer::new(window_for_renderer, desired_size).await;
                    let app = App::new();

                    unsafe {
                        *renderer_ptr = Some(renderer);
                        *app_ptr = Some(app);
                    }

                    log::info!("✅ Renderer initialized successfully");
                    
                    // Request initial frame now that we're ready
                    window_for_redraw.request_redraw();
                });
            }

            #[cfg(not(target_arch = "wasm32"))]
            {
                // Desktop: Wrap in Arc for 'static lifetime, then block on async initialization
                let initial_size = winit::dpi::PhysicalSize::new(WIDTH, HEIGHT);
                let window_arc = std::sync::Arc::new(window);
                
                let renderer = pollster::block_on(Renderer::new(window_arc.clone(), initial_size));
                let app = App::new();

                self.window = Some(window_arc);
                self.renderer = Some(renderer);
                self.app = Some(app);

                log::info!("✅ Renderer created (will be configured on first resize event)");
            }
        }
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, _id: WindowId, event: WindowEvent) {
        match event {
            WindowEvent::CloseRequested => {
                log::info!("Close requested, exiting");
                event_loop.exit();
            }
            WindowEvent::Resized(physical_size) => {
                log::info!("⚠️ RESIZE EVENT: {:?}", physical_size);
                
                // Log canvas state during resize
                #[cfg(target_arch = "wasm32")]
                {
                    if let Some(window) = &self.window {
                        use winit::platform::web::WindowExtWebSys;
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
                }
            }
            WindowEvent::RedrawRequested => {
                // Render if we have valid components (renderer will check surface validity)
                if let (Some(renderer), Some(app)) = (&mut self.renderer, &mut self.app) {
                    app.render(renderer);
                    // Don't request another redraw - we're in Wait mode, only redraw on events
                }
            }
            _ => {}
        }
    }
}
