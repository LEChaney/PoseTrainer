use wgpu::InstanceDescriptor;

#[cfg(target_arch = "wasm32")]
use wasm_bindgen::{prelude::*, JsCast, JsValue};

#[cfg(target_arch = "wasm32")]
use wasm_bindgen_futures::spawn_local;

#[cfg(target_arch = "wasm32")]
use web_sys::window;

pub async fn run(is_web: bool) -> anyhow::Result<()> {
    // Create instance
    // wgpu 27: Instance::new takes &InstanceDescriptor; use defaults for broad compatibility.
    let instance = wgpu::Instance::new(&InstanceDescriptor::default());

    // Surface (optional): on web, create a canvas and attach; native prints adapter info only
    #[allow(unused_mut)]
    let mut width = 0u32;
    #[allow(unused_mut)]
    let mut height = 0u32;

    #[allow(unused_mut)]
    let mut surface: Option<wgpu::Surface> = None;

    #[cfg(target_arch = "wasm32")]
    if is_web {
        console_error_panic_hook::set_once();
        let win = window().ok_or_else(|| anyhow::anyhow!("no window"))?;
        let doc = win.document().ok_or_else(|| anyhow::anyhow!("no document"))?;
        let canvas = doc
            .create_element("canvas").map_err(js_err)?
            .dyn_into::<web_sys::HtmlCanvasElement>().map_err(|_| anyhow::anyhow!("element is not a canvas"))?;
        width = 640;
        height = 360;
        canvas.set_width(width);
        canvas.set_height(height);
        // Prefer appending to a specific container if present (for embedding in Flutter web)
        let root: web_sys::Element = doc
            .get_element_by_id("wgpu-probe-container")
            .map(|e| e.unchecked_into())
            .unwrap_or_else(|| doc.body().expect("no body").unchecked_into());
        root.append_child(&canvas).map_err(js_err)?;
        // Pass the target by value to satisfy either Into<SurfaceTarget> or &SurfaceTarget signatures.
        surface = Some(instance
            .create_surface(wgpu::SurfaceTarget::Canvas(canvas))
            .map_err(err_debug)?);
    }

    // Request adapter
    let adapter = instance
        .request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: surface.as_ref(),
            force_fallback_adapter: false,
        })
        .await
        .map_err(err_debug)?;

    let info = adapter.get_info();
    log_line(is_web, &format!(
        "Adapter: name='{}' backend={:?} device={:?} vendor={:#x}",
        info.name, info.backend, info.device, info.vendor
    ));

    // Device + queue
    let required_features = wgpu::Features::empty();
    #[cfg(target_arch = "wasm32")]
    let limits = wgpu::Limits::downlevel_webgl2_defaults();
    #[cfg(not(target_arch = "wasm32"))]
    let limits = wgpu::Limits::downlevel_webgl2_defaults().using_resolution(adapter.limits());
    let (device, queue) = adapter
        .request_device(&wgpu::DeviceDescriptor {
            required_features,
            required_limits: limits,
            label: Some("wgpu-probe-device"),
            memory_hints: wgpu::MemoryHints::default(),
            trace: wgpu::Trace::default(),
            experimental_features: Default::default(),
        })
        .await
        .map_err(err_debug)?;

    log_line(is_web, &format!("Features: {:?}", device.features()));
    log_line(is_web, &format!("Limits: {:#?}", device.limits()));

    // If we have a surface (web), configure and clear it
    if let Some(surface) = surface {
        let caps = surface.get_capabilities(&adapter);
        let format = caps.formats[0];
        surface.configure(&device, &wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format,
            width,
            height,
            present_mode: wgpu::PresentMode::Fifo,
            alpha_mode: caps.alpha_modes[0],
            view_formats: vec![],
            desired_maximum_frame_latency: 2,
        });
    let frame = surface.get_current_texture().map_err(err_debug)?;
        let view = frame.texture.create_view(&wgpu::TextureViewDescriptor::default());
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("clear") });
        {
            let _rpass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("clear pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    depth_slice: None,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color { r: 1.0, g: 0.1, b: 0.2, a: 1.0 }),
                        store: wgpu::StoreOp::Store
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
        }
        queue.submit(Some(encoder.finish()));
        frame.present();
        log_line(is_web, "Rendered a clear frame");
    }

    Ok(())
}

#[cfg(target_arch = "wasm32")]
#[wasm_bindgen(start)]
pub fn wasm_start() {
    spawn_local(async move {
        if let Err(err) = run(true).await {
            web_sys::console::error_1(&format!("wgpu-probe failed: {err:?}").into());
        }
    });
}

fn log_line(is_web: bool, msg: &str) {
    if is_web {
        #[cfg(target_arch = "wasm32")]
        {
            web_sys::console::log_1(&msg.into());
        }
    } else {
        println!("{msg}");
    }
}

#[cfg(target_arch = "wasm32")]
fn js_err(e: JsValue) -> anyhow::Error {
    // Convert JsValue into a readable anyhow::Error.
    // Prefer string if present; otherwise fall back to Debug.
    if let Some(s) = e.as_string() {
        anyhow::anyhow!(s)
    } else {
        anyhow::anyhow!(format!("JsValue error: {:?}", e))
    }
}

fn err_debug<E: core::fmt::Debug>(e: E) -> anyhow::Error {
    anyhow::anyhow!(format!("{e:?}"))
}
