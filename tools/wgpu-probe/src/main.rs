#[cfg(not(target_arch = "wasm32"))]
fn main() {
    // Native entry: call into the library's async runner.
    pollster::block_on(async move {
        if let Err(err) = wgpu_probe::run(false).await {
            eprintln!("wgpu-probe failed: {err:?}");
            std::process::exit(1);
        }
    });
}

#[cfg(target_arch = "wasm32")]
fn main() {
    // Trunk builds the bin for wasm too; provide a no-op main.
}
