//! wgpu Renderer
//!
//! This module handles all wgpu initialization and rendering.
//! It's designed to be independent of the windowing system where possible.

use wgpu;

/// Renderer wraps the wgpu device, queue, and surface
pub struct Renderer {
    surface: wgpu::Surface<'static>,
    device: wgpu::Device,
    queue: wgpu::Queue,
    config: wgpu::SurfaceConfiguration,
    size: winit::dpi::PhysicalSize<u32>,
    max_texture_dimension: u32,
}

impl Renderer {
    /// Create a new renderer
    /// 
    /// # Arguments
    /// * `window` - The window to render to
    /// 
    /// # Returns
    /// A new renderer instance
    pub async fn new(window: impl Into<wgpu::SurfaceTarget<'static>>, size: winit::dpi::PhysicalSize<u32>) -> Self {
        log::info!("🔧 Renderer::new() starting...");
        crate::debug::update_status("Creating wgpu instance...");
        
        // Create wgpu instance
        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends: wgpu::Backends::all() & !wgpu::Backends::BROWSER_WEBGPU,
            ..Default::default()
        });
        log::info!("✅ wgpu instance created");
        crate::debug::update_status("Creating surface...");

        // Create surface
        log::info!("🔍 About to create surface from window target...");
        let surface = match instance.create_surface(window) {
            Ok(surf) => {
                log::info!("✅ Surface created successfully");
                surf
            }
            Err(e) => {
                let err_msg = format!("❌ Failed to create surface: {:?}", e);
                log::error!("{}", err_msg);
                crate::debug::update_status(&err_msg);
                panic!("{}", err_msg);
            }
        };
        log::info!("✅ Surface created");
        crate::debug::update_status("Requesting adapter...");

        // Request adapter
        log::info!("🔍 Requesting adapter (this may take a moment)...");
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::default(),
                compatible_surface: Some(&surface),
                force_fallback_adapter: false,
            })
            .await
            .expect("Failed to find suitable adapter");
        
        let adapter_info = adapter.get_info();
        log::info!("✅ Adapter acquired: {:?} (backend: {:?})", adapter_info.name, adapter_info.backend);
        crate::debug::update_status(&format!("Using: {:?}", adapter_info.backend));
        
        // Get adapter limits to check max texture size
        let adapter_limits = adapter.limits();
        let max_texture_dimension = adapter_limits.max_texture_dimension_2d;
        log::info!("📏 Max texture dimension: {}", max_texture_dimension);
        
        crate::debug::update_status("Creating device...");

        // Request device and queue
        log::info!("🔍 Requesting device and queue...");
        
        // Use the adapter's actual limits instead of defaults to match device capabilities
        // This is important for both web (WebGL2 limits) and desktop (high-res canvases)
        let mut device_limits = if cfg!(target_arch = "wasm32") {
            wgpu::Limits::downlevel_webgl2_defaults()
        } else {
            wgpu::Limits::default()
        };
        
        // Override texture dimension limits with adapter's actual capabilities
        device_limits.max_texture_dimension_2d = adapter_limits.max_texture_dimension_2d;
        device_limits.max_texture_dimension_1d = adapter_limits.max_texture_dimension_1d;
        log::info!("📏 Using adapter limits: max_texture_2d={}, max_texture_1d={}", 
                   device_limits.max_texture_dimension_2d, device_limits.max_texture_dimension_1d);
        
        let (device, queue) = adapter
            .request_device(&wgpu::DeviceDescriptor {
                label: Some("Drawing Canvas Device"),
                required_features: wgpu::Features::empty(),
                required_limits: device_limits,
                memory_hints: Default::default(),
                trace: Default::default(),
                experimental_features: Default::default(),
            })
            .await
            .expect("Failed to create device");
        log::info!("✅ Device and queue created");
        crate::debug::update_status("Configuring surface...");

        // Get surface capabilities and configure
        let surface_caps = surface.get_capabilities(&adapter);
        log::info!("Surface capabilities: formats={:?}, present_modes={:?}", 
                   surface_caps.formats, surface_caps.present_modes);
        let surface_format = surface_caps
            .formats
            .iter()
            .copied()
            .find(|f| f.is_srgb())
            .unwrap_or(surface_caps.formats[0]);

        // Clamp size to max texture dimension to avoid WebGL limits
        let clamped_width = size.width.min(max_texture_dimension);
        let clamped_height = size.height.min(max_texture_dimension);
        
        if clamped_width != size.width || clamped_height != size.height {
            log::warn!("⚠️ Canvas size {}x{} exceeds max texture size {}, clamping to {}x{}", 
                       size.width, size.height, max_texture_dimension, clamped_width, clamped_height);
            crate::debug::update_status(&format!("⚠️ Clamped to {}x{}", clamped_width, clamped_height));
        }

        let config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format: surface_format,
            width: clamped_width,
            height: clamped_height,
            present_mode: surface_caps.present_modes[0],
            alpha_mode: surface_caps.alpha_modes[0],
            view_formats: vec![],
            desired_maximum_frame_latency: 2,
        };

        // Only configure if size is valid, otherwise wait for resize
        if config.width > 0 && config.height > 0 {
            log::info!("Configuring surface with size: {}x{}", config.width, config.height);
            surface.configure(&device, &config);
            log::info!("✅ Surface configured");
        } else {
            log::warn!("Skipping surface configuration (invalid size: {}x{})", config.width, config.height);
        }

        log::info!("✅ Renderer initialized: {}x{}, format: {:?}", size.width, size.height, surface_format);
        crate::debug::update_status("✅ Renderer complete!");

        Self {
            surface,
            device,
            queue,
            config,
            size,
            max_texture_dimension,
        }
    }

    /// Resize the surface
    pub fn resize(&mut self, new_size: winit::dpi::PhysicalSize<u32>) {
        if new_size.width > 0 && new_size.height > 0 {
            self.size = new_size;
            
            // Clamp to max texture dimension
            let clamped_width = new_size.width.min(self.max_texture_dimension);
            let clamped_height = new_size.height.min(self.max_texture_dimension);
            
            if clamped_width != new_size.width || clamped_height != new_size.height {
                log::warn!("⚠️ Resize {}x{} exceeds max texture size {}, clamping to {}x{}", 
                           new_size.width, new_size.height, self.max_texture_dimension, 
                           clamped_width, clamped_height);
            }
            
            self.config.width = clamped_width;
            self.config.height = clamped_height;
            self.surface.configure(&self.device, &self.config);
            log::debug!("Surface resized to: {}x{}", clamped_width, clamped_height);
        }
    }

    pub fn is_valid_surface(&self) -> bool {
        self.config.width > 0 
        && self.config.height > 0 
        && self.surface.get_current_texture().is_ok()
    }

    /// Render a frame
    pub fn render(&mut self, clear_color: [f64; 4]) {
        if !self.is_valid_surface() {
            log::warn!("Invalid surface state, skipping render");
            return;
        }

        // Get the next frame
        let output = match self.surface.get_current_texture() {
            Ok(output) => output,
            Err(e) => {
                log::error!("Failed to get surface texture: {:?}", e);
                return;
            }
        };

        let view = output
            .texture
            .create_view(&wgpu::TextureViewDescriptor::default());

        // Create command encoder
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Render Encoder"),
            });

        // Clear to color
        {
            log::debug!("Clearing frame to color: {:?}", clear_color);
            let _render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Clear Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color {
                            r: clear_color[0],
                            g: clear_color[1],
                            b: clear_color[2],
                            a: clear_color[3],
                        }),
                        store: wgpu::StoreOp::Store,
                    },
                    depth_slice: None,
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
        }

        // Submit commands
        self.queue.submit(std::iter::once(encoder.finish()));
        output.present();
    }

    /// Get the current surface size
    pub fn size(&self) -> winit::dpi::PhysicalSize<u32> {
        self.size
    }
}
