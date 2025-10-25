// Blit Shader
// Copies canvas texture to display surface
//
// Linear mode:
//   - Canvas: Rgba16Float (stores linear values)
//   - Blit samples: linear → linear (no conversion)
//   - Blit outputs: linear values
//   - Surface: Rgba8UnormSrgb (auto-converts linear → sRGB on write)
//
// sRGB mode:
//   - Canvas: Rgba16Float (stores sRGB-encoded values as raw floats)
//   - Blit samples: sRGB values (no auto-conversion, float format)
//   - Blit converts: sRGB → linear
//   - Surface: Rgba8UnormSrgb (auto-converts linear → sRGB on write)
//   - Result: sRGB → linear → sRGB preserves original colors

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

struct BlitUniforms {
    blend_mode: u32,  // 0 = Linear, 1 = sRGB
    _padding0: u32,
    _padding1: u32,
    _padding2: u32,
}

@group(0) @binding(0)
var canvas_texture: texture_2d<f32>;

@group(0) @binding(1)
var canvas_sampler: sampler;

@group(0) @binding(2)
var<uniform> blit_uniforms: BlitUniforms;

// Vertex shader: Generate full-screen quad
@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
    var output: VertexOutput;
    
    // Generate full-screen quad vertices (6 vertices = 2 triangles)
    let vertex_id = vertex_index % 6u;
    var pos: vec2<f32>;
    var uv: vec2<f32>;
    
    switch vertex_id {
        case 0u: {
            pos = vec2<f32>(-1.0, -1.0);  // Bottom-left
            uv = vec2<f32>(0.0, 1.0);
        }
        case 1u: {
            pos = vec2<f32>(1.0, -1.0);   // Bottom-right
            uv = vec2<f32>(1.0, 1.0);
        }
        case 2u: {
            pos = vec2<f32>(-1.0, 1.0);   // Top-left
            uv = vec2<f32>(0.0, 0.0);
        }
        case 3u: {
            pos = vec2<f32>(-1.0, 1.0);   // Top-left
            uv = vec2<f32>(0.0, 0.0);
        }
        case 4u: {
            pos = vec2<f32>(1.0, -1.0);   // Bottom-right
            uv = vec2<f32>(1.0, 1.0);
        }
        default: {
            pos = vec2<f32>(1.0, 1.0);    // Top-right
            uv = vec2<f32>(1.0, 0.0);
        }
    }
    
    output.position = vec4<f32>(pos, 0.0, 1.0);
    output.uv = uv;
    
    return output;
}

// sRGB → linear conversion per component (correct piecewise function)
fn srgb_to_linear(c: f32) -> f32 {
    if (c <= 0.04045) {
        return c / 12.92;
    } else {
        return pow((c + 0.055) / 1.055, 2.4);
    }
}

// Fragment shader: Sample canvas and convert based on blend mode
// Shader handles different color space conversions for each mode
@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    // Sample color from canvas
    let canvas_color = textureSample(canvas_texture, canvas_sampler, input.uv);
    
    // Check blend mode
    if (blit_uniforms.blend_mode == 1u) {
        // sRGB mode: Canvas stores sRGB-encoded values in Rgba16Float
        // Need to convert sRGB → linear so surface's linear → sRGB is a no-op
        // Using correct sRGB piecewise function
        return vec4<f32>(
            srgb_to_linear(canvas_color.r),
            srgb_to_linear(canvas_color.g),
            srgb_to_linear(canvas_color.b),
            canvas_color.a
        );
    } else {
        // Linear mode: Canvas already has linear values, pass through
        // Surface will auto-convert linear → sRGB
        return canvas_color;
    }
}
