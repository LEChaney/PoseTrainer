//! wgpu Renderer
//!
//! This module handles all wgpu initialization and rendering.
//! It's designed to be independent of the windowing system where possible.

use wgpu;
use wgpu::util::DeviceExt;
use crate::brush::BrushDab;
use crate::debug;

/// Color blending mode for brush strokes
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BlendColorSpace {
    /// Blend in linear color space (physically correct)
    Linear,
    /// Blend in sRGB/gamma space (matches Procreate/CSP)
    Srgb,
}

/// Uniforms for brush shader (canvas size)
#[repr(C, align(16))]  // Force 16-byte alignment for WebGL compatibility
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
struct BrushUniforms {
    canvas_size: [f32; 2],
    _padding: [f32; 2],  // Align to 16 bytes
}

/// Uniforms for blit shader (blend mode)
#[repr(C, align(16))]  // Force 16-byte alignment for WebGL compatibility
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
struct BlitUniforms {
    blend_mode: u32,  // 0 = Linear, 1 = sRGB
    _padding: [u32; 3],  // Align to 16 bytes
}

/// Vertex data for a single brush dab instance
#[repr(C, align(16))]  // Force 16-byte alignment for WebGL compatibility
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
struct DabInstance {
    position: [f32; 2],
    size: f32,
    opacity: f32,
    color: [f32; 4],
    hardness: f32,
    _padding: [f32; 3],  // Align to 16 bytes
}

/// Renderer wraps the wgpu device, queue, and surface
pub struct Renderer {
    surface: wgpu::Surface<'static>,
    device: wgpu::Device,
    queue: wgpu::Queue,
    config: wgpu::SurfaceConfiguration,
    size: winit::dpi::PhysicalSize<u32>,
    max_texture_dimension: u32,
    canvas_format: wgpu::TextureFormat, // Current canvas texture format
    blend_color_space: BlendColorSpace,  // Current blending mode
    
    // Brush rendering pipelines (one for each target format)
    brush_pipeline: wgpu::RenderPipeline,  // For rendering to canvas
    brush_uniform_buffer: wgpu::Buffer,
    brush_bind_group: wgpu::BindGroup,
    
    // Canvas texture for accumulating strokes
    canvas_texture: wgpu::Texture,
    canvas_view: wgpu::TextureView,
    
    // Blit pipeline for copying canvas to surface
    blit_pipeline: wgpu::RenderPipeline,
    blit_uniform_buffer: wgpu::Buffer,
    blit_bind_group: wgpu::BindGroup,
    canvas_sampler: wgpu::Sampler,
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
        
        // Select an sRGB surface format
        // Prefer sRGB formats for proper color space handling
        let surface_format = surface_caps
            .formats
            .iter()
            .copied()
            .find(|f| f.is_srgb())
            .unwrap_or(surface_caps.formats[0]);
        
        log::info!("Selected surface format: {:?}", surface_format);

        let canvas_format = wgpu::TextureFormat::Rgba16Float;
        log::info!("Canvas texture format: {:?}", canvas_format);

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
            // Use Opaque alpha mode to prevent canvas transparency showing HTML background
            alpha_mode: wgpu::CompositeAlphaMode::Opaque,
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

        log::info!("✅ Renderer initialized: {}x{}, surface: {:?}, canvas: {:?}", 
                   size.width, size.height, surface_format, canvas_format);
        crate::debug::update_status("✅ Renderer complete!");

        // Create brush rendering pipelines for both linear canvas and sRGB surface
        let brush_pipeline = Self::create_brush_pipeline(&device, canvas_format);
        debug::update_status("Brush pipeline created...");
        log::info!("✅ Brush pipeline created for format: {:?}", canvas_format);

        // Create uniform buffer for canvas size
        let brush_uniforms = BrushUniforms {
            canvas_size: [clamped_width as f32, clamped_height as f32],
            _padding: [0.0; 2],
        };
        let brush_uniform_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Brush Uniform Buffer"),
            contents: bytemuck::cast_slice(&[brush_uniforms]),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });
        
        // Create bind group for uniforms (both pipelines share the same layout)
        let brush_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Brush Bind Group"),
            layout: &brush_pipeline.get_bind_group_layout(0),
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: brush_uniform_buffer.as_entire_binding(),
            }],
        });
        
        // Create canvas texture for accumulating strokes (uses LINEAR format)
        let (canvas_texture, canvas_view) = Self::create_canvas_texture(
            &device,
            clamped_width,
            clamped_height,
            canvas_format,
        );
        log::info!("✅ Canvas texture created: {}x{}, format: {:?}", clamped_width, clamped_height, canvas_format);

        // Create blit pipeline for copying canvas to surface (handles color space conversion)
        let (blit_pipeline, blit_bind_group_layout) = Self::create_blit_pipeline(&device, surface_format);
        log::info!("✅ Blit pipeline created");
        
        // Create sampler for canvas texture
        let canvas_sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("Canvas Sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            address_mode_w: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::FilterMode::Nearest,
            ..Default::default()
        });
        
        // Create blit uniform buffer (blend mode)
        // TODO: Set blend mode on app initialization and plumb through here
        let blend_color_space = BlendColorSpace::Srgb; // Default to sRGB blending
        let blit_uniforms = BlitUniforms {
            blend_mode: match blend_color_space {
                BlendColorSpace::Linear => 0,
                BlendColorSpace::Srgb => 1,
            },
            _padding: [0; 3],
        };
        let blit_uniform_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Blit Uniform Buffer"),
            contents: bytemuck::cast_slice(&[blit_uniforms]),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });
        
        // Create bind group for blit pipeline
        let blit_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Blit Bind Group"),
            layout: &blit_bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(&canvas_view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&canvas_sampler),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: blit_uniform_buffer.as_entire_binding(),
                },
            ],
        });

        Self {
            surface,
            device,
            queue,
            config,
            size,
            max_texture_dimension,
            canvas_format,
            blend_color_space: blend_color_space,
            brush_pipeline,
            brush_uniform_buffer,
            brush_bind_group,
            canvas_texture,
            canvas_view,
            blit_pipeline,
            blit_uniform_buffer,
            blit_bind_group,
            canvas_sampler,
        }
    }

    /// Create the brush rendering pipeline
    fn create_brush_pipeline(device: &wgpu::Device, target_format: wgpu::TextureFormat) -> wgpu::RenderPipeline {
        // Load shader
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Brush Shader"),
            source: wgpu::ShaderSource::Wgsl(include_str!("shaders/brush.wgsl").into()),
        });
        debug::update_status("Creating brush pipeline...");
        
        // Create bind group layout for uniforms
        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("Brush Bind Group Layout"),
            entries: &[wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::VERTEX,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            }],
        });
        debug::update_status("Brush bind group layout created...");
        
        // Create pipeline layout
        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Brush Pipeline Layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        debug::update_status("Creating vertex buffer layout...");
        
        // Vertex buffer layout for dab instances
        let vertex_buffer_layout = wgpu::VertexBufferLayout {
            array_stride: std::mem::size_of::<DabInstance>() as wgpu::BufferAddress,
            step_mode: wgpu::VertexStepMode::Instance,
            attributes: &[
                // position
                wgpu::VertexAttribute {
                    offset: 0,
                    shader_location: 0,
                    format: wgpu::VertexFormat::Float32x2,
                },
                // size
                wgpu::VertexAttribute {
                    offset: 8,
                    shader_location: 1,
                    format: wgpu::VertexFormat::Float32,
                },
                // opacity
                wgpu::VertexAttribute {
                    offset: 12,
                    shader_location: 2,
                    format: wgpu::VertexFormat::Float32,
                },
                // color
                wgpu::VertexAttribute {
                    offset: 16,
                    shader_location: 3,
                    format: wgpu::VertexFormat::Float32x4,
                },
                // hardness
                wgpu::VertexAttribute {
                    offset: 32,
                    shader_location: 4,
                    format: wgpu::VertexFormat::Float32,
                },
            ],
        };

        debug::update_status("Creating brush render pipeline...");
        
        // Create the render pipeline
        device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Brush Pipeline"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs_main"),
                buffers: &[vertex_buffer_layout],
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_main"),
                targets: &[Some(wgpu::ColorTargetState {
                    format: target_format,
                    blend: Some(wgpu::BlendState {
                        // Premultiplied alpha blend mode
                        // Source RGB is already multiplied by alpha in shader
                        color: wgpu::BlendComponent {
                            src_factor: wgpu::BlendFactor::One,
                            dst_factor: wgpu::BlendFactor::OneMinusSrcAlpha,
                            operation: wgpu::BlendOperation::Add,
                        },
                        alpha: wgpu::BlendComponent {
                            src_factor: wgpu::BlendFactor::One,
                            dst_factor: wgpu::BlendFactor::OneMinusSrcAlpha,
                            operation: wgpu::BlendOperation::Add,
                        },
                    }),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
                compilation_options: Default::default(),
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                strip_index_format: None,
                front_face: wgpu::FrontFace::Ccw,
                cull_mode: None,
                polygon_mode: wgpu::PolygonMode::Fill,
                unclipped_depth: false,
                conservative: false,
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            multiview: None,
            cache: None,
        })
    }

    /// Create canvas texture for accumulating strokes
    fn create_canvas_texture(
        device: &wgpu::Device,
        width: u32,
        height: u32,
        format: wgpu::TextureFormat,
    ) -> (wgpu::Texture, wgpu::TextureView) {
        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("Canvas Texture"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT 
                | wgpu::TextureUsages::TEXTURE_BINDING
                | wgpu::TextureUsages::COPY_SRC,
            view_formats: &[],
        });
        
        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        
        (texture, view)
    }

    /// Recreate the blit bind group with current canvas view and uniform buffer
    fn recreate_blit_bind_group(&mut self) {
        self.blit_bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Blit Bind Group"),
            layout: &self.blit_pipeline.get_bind_group_layout(0),
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(&self.canvas_view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&self.canvas_sampler),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: self.blit_uniform_buffer.as_entire_binding(),
                },
            ],
        });
    }

    /// Create the blit pipeline for copying canvas to surface
    fn create_blit_pipeline(
        device: &wgpu::Device,
        target_format: wgpu::TextureFormat,
    ) -> (wgpu::RenderPipeline, wgpu::BindGroupLayout) {
        // Load shader
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Blit Shader"),
            source: wgpu::ShaderSource::Wgsl(include_str!("shaders/blit.wgsl").into()),
        });
        
        // Create bind group layout for texture, sampler, and uniforms
        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("Blit Bind Group Layout"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        multisampled: false,
                        view_dimension: wgpu::TextureViewDimension::D2,
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
            ],
        });
        
        // Create pipeline layout
        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Blit Pipeline Layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });
        
        // Create the render pipeline
        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Blit Pipeline"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs_main"),
                buffers: &[],
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_main"),
                targets: &[Some(wgpu::ColorTargetState {
                    format: target_format,
                    blend: None,
                    write_mask: wgpu::ColorWrites::ALL,
                })],
                compilation_options: Default::default(),
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                strip_index_format: None,
                front_face: wgpu::FrontFace::Ccw,
                cull_mode: None,
                polygon_mode: wgpu::PolygonMode::Fill,
                unclipped_depth: false,
                conservative: false,
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            multiview: None,
            cache: None,
        });
        
        (pipeline, bind_group_layout)
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

            // Recreate canvas texture with new size
            let (canvas_texture, canvas_view) = Self::create_canvas_texture(
                &self.device,
                clamped_width,
                clamped_height,
                self.canvas_format,
            );
            self.canvas_texture = canvas_texture;
            self.canvas_view = canvas_view;
            
            // Recreate blit bind group with new canvas view
            self.recreate_blit_bind_group();
            
            // Update uniform buffer with new canvas size
            let brush_uniforms = BrushUniforms {
                canvas_size: [clamped_width as f32, clamped_height as f32],
                _padding: [0.0; 2],
            };
            self.queue.write_buffer(
                &self.brush_uniform_buffer,
                0,
                bytemuck::cast_slice(&[brush_uniforms]),
            );

            log::debug!("Surface and canvas resized to: {}x{}, format: {:?}", clamped_width, clamped_height, self.canvas_format);
        }
    }

    /// Render brush dabs to the canvas texture
    pub fn render_dabs(&mut self, dabs: &[BrushDab]) {
        if dabs.is_empty() {
            return;
        }
        
        // Convert dabs to instance data
        // Brush colors are stored in sRGB in BrushDab, always convert to linear for shader
        let instances: Vec<DabInstance> = dabs.iter().map(|&dab| {
            // Always convert sRGB brush color to linear for shader math
            let color = match self.blend_color_space {
                BlendColorSpace::Linear => crate::color::srgb_to_linear_rgba(dab.color),
                BlendColorSpace::Srgb => dab.color,  // sRGB blending uses sRGB colors directly
            };
            
            DabInstance {
                position: dab.position,
                size: dab.size,
                opacity: dab.opacity,
                color,
                hardness: dab.hardness,
                _padding: [0.0; 3],
            }
        }).collect();
        
        // Create instance buffer
        let instance_buffer = self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Dab Instance Buffer"),
            contents: bytemuck::cast_slice(&instances),
            usage: wgpu::BufferUsages::VERTEX,
        });
        
        // Create command encoder
        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("Brush Render Encoder"),
        });
        
        // Render dabs to canvas texture
        {
            let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Brush Render Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &self.canvas_view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Load,  // Keep existing canvas content
                        store: wgpu::StoreOp::Store,
                    },
                    depth_slice: None,
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
            
            render_pass.set_pipeline(&self.brush_pipeline);
            render_pass.set_bind_group(0, &self.brush_bind_group, &[]);
            render_pass.set_vertex_buffer(0, instance_buffer.slice(..));
            
            // Draw 6 vertices per instance (2 triangles = 1 quad per dab)
            render_pass.draw(0..6, 0..instances.len() as u32);
        }
        
        self.queue.submit(std::iter::once(encoder.finish()));
        log::debug!("Rendered {} brush dabs", dabs.len());
    }

    pub fn is_valid_surface(&self) -> bool {
        self.config.width > 0 
        && self.config.height > 0 
        && self.surface.get_current_texture().is_ok()
    }

    /// Render a frame (blit canvas to surface)
    pub fn render(&mut self) {
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

        // Blit canvas texture to surface using full-screen quad
        {
            let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Blit Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                        store: wgpu::StoreOp::Store,
                    },
                    depth_slice: None,
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });

            render_pass.set_pipeline(&self.blit_pipeline);
            render_pass.set_bind_group(0, &self.blit_bind_group, &[]);
            render_pass.draw(0..6, 0..1);
        }

        // Submit commands
        self.queue.submit(std::iter::once(encoder.finish()));
        output.present();
    }

    /// Clear the canvas to a color
    pub fn clear_canvas(&self, clear_color: &[f64; 4]) {
        let clear_color = match self.blend_color_space {
            BlendColorSpace::Linear => crate::color::srgb_to_linear_rgba_f64(clear_color),
            BlendColorSpace::Srgb => *clear_color,
        };

        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("Clear Canvas Encoder"),
        });

        {
            let _render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Clear Canvas Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &self.canvas_view,
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

        self.queue.submit(std::iter::once(encoder.finish()));
        log::debug!("Canvas cleared to color: {:?}", clear_color);
    }

    /// Get the current surface size
    pub fn size(&self) -> winit::dpi::PhysicalSize<u32> {
        self.size
    }

    /// Get the current blend color space
    pub fn blend_color_space(&self) -> BlendColorSpace {
        self.blend_color_space
    }

    /// Set the blend color space
    pub fn set_blend_color_space(&mut self, color_space: BlendColorSpace) {
        if self.blend_color_space == color_space {
            return;
        }

        log::info!("Switching blend color space from {:?} to {:?}", self.blend_color_space, color_space);
        self.blend_color_space = color_space;

        // Update uniform buffer with new blend mode value
        let blit_uniforms = BlitUniforms {
            blend_mode: match self.blend_color_space {
                BlendColorSpace::Linear => 0,
                BlendColorSpace::Srgb => 1,
            },
            _padding: [0; 3],
        };
        self.queue.write_buffer(
            &self.blit_uniform_buffer,
            0,
            bytemuck::cast_slice(&[blit_uniforms]),
        );
    }

    /// Read canvas texture back to CPU as RGBA8 data
    /// This is an expensive operation requiring GPU->CPU transfer
    #[cfg(target_arch = "wasm32")]
    pub async fn read_canvas_rgba8(&self) -> Result<Vec<u8>, String> {
        // Use canvas texture dimensions, not surface config dimensions
        let width = self.canvas_texture.width();
        let height = self.canvas_texture.height();
        let pixel_count = (width * height) as usize;
        
        log::info!("Reading canvas texture: {}x{} pixels", width, height);
        
        // Create a buffer to copy texture data into
        // Canvas is Rgba16Float (8 bytes per pixel: 4 channels * 2 bytes per f16)
        let bytes_per_pixel = 8;
        let bytes_per_row_unpadded = width * bytes_per_pixel;
        // Align to 256 bytes per row as required by WebGPU
        let bytes_per_row_padded = ((bytes_per_row_unpadded + 255) / 256) * 256;
        let buffer_size = (bytes_per_row_padded * height) as u64;
        
        log::debug!(
            "Buffer layout: unpadded={}, padded={}, buffer_size={}",
            bytes_per_row_unpadded, bytes_per_row_padded, buffer_size
        );
        
        // Validate that padded row is sufficient
        if bytes_per_row_padded < bytes_per_row_unpadded {
            return Err(format!(
                "Invalid padding: padded ({}) < unpadded ({})",
                bytes_per_row_padded, bytes_per_row_unpadded
            ));
        }
        
        let output_buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Canvas Readback Buffer"),
            size: buffer_size,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        
        // Create command encoder for copy operation
        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("Canvas Readback Encoder"),
        });
        
        // Copy canvas texture to buffer
        encoder.copy_texture_to_buffer(
            wgpu::TexelCopyTextureInfo {
                texture: &self.canvas_texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::TexelCopyBufferInfo {
                buffer: &output_buffer,
                layout: wgpu::TexelCopyBufferLayout {
                    offset: 0,
                    bytes_per_row: Some(bytes_per_row_padded),
                    rows_per_image: Some(height),
                },
            },
            wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
        );
        
        self.queue.submit(std::iter::once(encoder.finish()));
        
        // Map the buffer to read data back
        let buffer_slice = output_buffer.slice(..);
        let (tx, rx) = futures::channel::oneshot::channel();
        
        buffer_slice.map_async(wgpu::MapMode::Read, move |result| {
            let _ = tx.send(result);
        });
        
        // Wait for mapping to complete (device.poll happens internally in WASM)
        rx.await
            .map_err(|_| "Failed to receive buffer map result".to_string())?
            .map_err(|e| format!("Failed to map buffer: {:?}", e))?;
        
        // Read the data
        let mapped_data = buffer_slice.get_mapped_range();
        
        // Canvas texture is Rgba16Float, so we need to convert to RGBA8
        // The data in the buffer is f16 values (2 bytes per channel)
        let mut rgba8_data = Vec::with_capacity(pixel_count * 4);
        
        for y in 0..height {
            let row_offset = (y * bytes_per_row_padded) as usize;
            for x in 0..width {
                let pixel_offset = row_offset + (x * 8) as usize; // 8 bytes per pixel (4 * f16)
                
                // Read f16 values and convert to u8
                for channel in 0..4 {
                    let offset = pixel_offset + channel * 2;
                    if offset + 1 < mapped_data.len() {
                        let f16_bytes = [mapped_data[offset], mapped_data[offset + 1]];
                        let f16_val = half::f16::from_le_bytes(f16_bytes);
                        let f32_val = f16_val.to_f32();
                        // Convert 0.0-1.0 float to 0-255 u8, clamping for safety
                        let u8_val = (f32_val * 255.0).clamp(0.0, 255.0) as u8;
                        rgba8_data.push(u8_val);
                    } else {
                        rgba8_data.push(0); // Fallback for out-of-bounds
                    }
                }
            }
        }
        
        drop(mapped_data);
        output_buffer.unmap();
        
        log::info!("Canvas texture read back: {}x{} pixels ({} bytes)", width, height, rgba8_data.len());
        Ok(rgba8_data)
    }
}

