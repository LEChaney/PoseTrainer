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
        // Create wgpu instance
        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends: wgpu::Backends::all(),
            ..Default::default()
        });

        // Create surface
        let surface = instance
            .create_surface(window)
            .expect("Failed to create surface");

        // Request adapter
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::default(),
                compatible_surface: Some(&surface),
                force_fallback_adapter: false,
            })
            .await
            .expect("Failed to find suitable adapter");

        // Request device and queue
        let (device, queue) = adapter
            .request_device(&wgpu::DeviceDescriptor {
                label: Some("Drawing Canvas Device"),
                required_features: wgpu::Features::empty(),
                required_limits: if cfg!(target_arch = "wasm32") {
                    wgpu::Limits::downlevel_webgl2_defaults()
                } else {
                    wgpu::Limits::default()
                },
                memory_hints: Default::default(),
                trace: Default::default(),
                experimental_features: Default::default(),
            })
            .await
            .expect("Failed to create device");

        // Get surface capabilities and configure
        let surface_caps = surface.get_capabilities(&adapter);
        let surface_format = surface_caps
            .formats
            .iter()
            .copied()
            .find(|f| f.is_srgb())
            .unwrap_or(surface_caps.formats[0]);

        let config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format: surface_format,
            width: size.width,
            height: size.height,
            present_mode: surface_caps.present_modes[0],
            alpha_mode: surface_caps.alpha_modes[0],
            view_formats: vec![],
            desired_maximum_frame_latency: 2,
        };

        // Only configure if size is valid, otherwise wait for resize
        if config.width > 0 && config.height > 0 {
            surface.configure(&device, &config);
        }

        log::info!("Renderer initialized: {}x{}, format: {:?}", size.width, size.height, surface_format);

        Self {
            surface,
            device,
            queue,
            config,
            size,
        }
    }

    /// Resize the surface
    pub fn resize(&mut self, new_size: winit::dpi::PhysicalSize<u32>) {
        if new_size.width > 0 && new_size.height > 0 {
            self.size = new_size;
            self.config.width = new_size.width;
            self.config.height = new_size.height;
            self.surface.configure(&self.device, &self.config);
            log::debug!("Surface resized to: {}x{}", new_size.width, new_size.height);
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
