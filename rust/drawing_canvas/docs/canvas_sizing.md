# Canvas Creation and Sizing - Technical Details

## Overview

This document explains how the drawing canvas is created, sized, and hooked up to the wgpu renderer, following winit's recommended patterns.

## The Correct Approach: Let winit Control Canvas Size

Based on winit maintainer guidance:
- **winit expects exclusive control over the canvas size**
- Don't override canvas CSS styles or width/height attributes directly
- Use `Window::set_inner_size()` if you need to control size programmatically
- **Initialize wgpu with any size, then wait for `WindowEvent::Resized` before drawing**

See: 
- https://github.com/rust-windowing/winit/issues/1491
- https://github.com/rust-windowing/winit/discussions/3262

## The Solution: Placeholder Init + Resize-Driven Configuration

### Step-by-Step Flow (All Platforms)

#### 1. Window Creation (`window.rs:33`)
```rust
let window = event_loop.create_window(
    Window::default_attributes()
        .with_title("Drawing Canvas")
        .with_inner_size(winit::dpi::PhysicalSize::new(800, 600))
).expect("Failed to create window");
```
- Creates a winit `Window` (wraps `HTMLCanvasElement` on web)
- `with_inner_size(800, 600)` is a **hint** for the initial size
- winit will handle CSS and canvas attributes automatically

#### 2. Append to DOM (WASM only) (`window.rs:46-56`)
```rust
let canvas = window.canvas().expect("Failed to get canvas from window");

web_sys::window()
    .and_then(|win| win.document())
    .and_then(|doc| {
        let container = doc.get_element_by_id("canvas-container")?;
        container.append_child(&canvas).ok()?;
        Some(())
    })
    .expect("Failed to append canvas to document");
```
- Extracts the `HtmlCanvasElement` from winit
- Appends to `#canvas-container` in index.html
- **Don't modify canvas CSS or attributes** - let winit handle it

#### 3. Initialize Renderer with Placeholder Size (`window.rs:63-81`)
```rust
let placeholder_size = winit::dpi::PhysicalSize::new(1, 1);

spawn_local(async move {
    let renderer = Renderer::new(window_arc, placeholder_size).await;
    let app = App::new();
    // ...
});
```
- Use a minimal placeholder size (1×1)
- This creates the wgpu surface and device
- **Surface is not properly configured yet** - we'll do that on resize

#### 4. Wait for WindowEvent::Resized (`window.rs:124-147`)
```rust
WindowEvent::Resized(physical_size) => {
    // Skip invalid sizes
    if physical_size.width == 0 || physical_size.height == 0 {
        log::warn!("Ignoring resize to zero size");
        return;
    }
    
    if let Some(renderer) = &mut self.renderer {
        renderer.resize(physical_size);
        
        // Mark as initialized after first valid resize
        if !self.initialized {
            self.initialized = true;
            log::info!("✅ Surface configured with size: {:?}", physical_size);
            
            // Request first frame
            window.request_redraw();
        }
    }
}
```
- **First resize event** provides the actual canvas size from the browser
- Call `renderer.resize()` to reconfigure the surface with correct dimensions
- Set `initialized = true` to start rendering
- Request first frame

#### 5. Render Only After Initialization (`window.rs:150-161`)
```rust
WindowEvent::RedrawRequested => {
    // Only render if we've been properly initialized
    if !self.initialized {
        return;
    }
    
    if let (Some(window), Some(renderer), Some(app)) =
        (&self.window, &mut self.renderer, &mut self.app)
    {
        app.render(renderer);
        window.request_redraw();
    }
}
```
- Skip rendering until we've received a valid resize event
- This prevents trying to render to a 1×1 or 0×0 surface

### In `renderer.rs`

#### Surface Reconfiguration (`renderer.rs:99-108`)
```rust
pub fn resize(&mut self, new_size: winit::dpi::PhysicalSize<u32>) {
    if new_size.width > 0 && new_size.height > 0 {
        self.size = new_size;
        self.config.width = new_size.width;
        self.config.height = new_size.height;
        self.surface.configure(&self.device, &self.config);
    }
}
```
- Updates surface configuration with new dimensions
- Validates size is non-zero before reconfiguring

## Why This Approach Works

1. ✅ **winit has full control** → no conflicts with CSS/attribute manipulation
2. ✅ **Placeholder init** → renderer created immediately, no async timing issues
3. ✅ **Resize-driven config** → surface gets correct size from browser layout
4. ✅ **Deferred rendering** → never tries to render before surface is ready
5. ✅ **Handles DPR automatically** → winit scales canvas backing store on web

## Key Concepts

### Physical vs Logical Pixels (winit handles this)

On web, winit automatically:
- Sets CSS size based on logical pixels (what you pass to `with_inner_size`)
- Sets canvas width/height attributes = logical size × devicePixelRatio
- Reports physical pixels in `WindowEvent::Resized`

You **don't need to manually calculate DPR** - winit does it for you!

### Why Not Use inner_size() Immediately?

```rust
// ❌ DON'T DO THIS
let size = window.inner_size(); // May return 0×0 on web!
let renderer = Renderer::new(window, size).await;
```

On WASM, `inner_size()` can return `0×0` if:
- Canvas isn't in DOM yet
- Browser hasn't done layout pass yet
- Container has `display: none` or similar

Instead, wait for `WindowEvent::Resized` which is guaranteed to have valid dimensions.

## Initialization Sequence

```
1. Create window with size hint (800×600)
   ↓
2. Append canvas to DOM (web only)
   ↓
3. Initialize renderer with placeholder (1×1)
   ↓
4. Browser does layout, determines actual size
   ↓
5. WindowEvent::Resized fired with real size
   ↓
6. renderer.resize(actual_size)
   ↓
7. Set initialized = true
   ↓
8. Start rendering
```

## HTML Container Setup

Your `#canvas-container` in index.html can use CSS to control size:

```css
#canvas-container {
    width: 800px;    /* Or 100%, 80vw, etc. */
    height: 600px;   /* Or 100vh, etc. */
    /* Container controls visible size */
}
```

winit will:
- Make canvas fill its container
- Set canvas backing store = container size × DPR
- Report physical size in resize events

## Desktop vs WASM

| Aspect | Desktop | WASM |
|--------|---------|------|
| Window creation | OS native window | `HTMLCanvasElement` |
| Initial resize | Fired immediately | Fired after layout |
| DPR handling | System scale factor | devicePixelRatio |
| Canvas control | Full winit control | Full winit control |

Both platforms follow the same pattern: placeholder init → wait for resize → start rendering.

## Future Improvements

- [ ] Support responsive canvas sizing (CSS-driven)
- [ ] Handle orientation changes on mobile
- [ ] Add explicit `Window::set_inner_size()` for programmatic resizing
- [ ] Debounce resize events for performance

## References

- [winit: Don't override canvas CSS](https://github.com/rust-windowing/winit/issues/1491)
- [winit: Wait for resize before drawing](https://github.com/rust-windowing/winit/discussions/3262)
- [wgpu surface configuration](https://docs.rs/wgpu/latest/wgpu/struct.SurfaceConfiguration.html)
