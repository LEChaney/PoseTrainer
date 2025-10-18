// Brush Dab Shader
// Renders circular brush stamps with variable size, opacity, and hardness

struct VertexInput {
    @builtin(vertex_index) vertex_index: u32,
    @location(0) dab_position: vec2<f32>,  // Center position of dab in pixels
    @location(1) dab_size: f32,            // Diameter in pixels
    @location(2) dab_opacity: f32,         // Opacity (0.0-1.0)
    @location(3) dab_color: vec4<f32>,     // Linear RGBA color
    @location(4) dab_hardness: f32,        // Edge hardness (0.0-1.0)
}

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,           // UV coordinates relative to dab center (-1 to 1)
    @location(1) color: vec4<f32>,
    @location(2) opacity: f32,
    @location(3) hardness: f32,
}

struct Uniforms {
    canvas_size: vec2<f32>,  // Canvas dimensions in pixels
    _padding: vec2<f32>,
}

@group(0) @binding(0)
var<uniform> uniforms: Uniforms;

// Vertex shader: Generate a quad for each brush dab instance
@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
    var output: VertexOutput;
    
    // Generate quad vertices (6 vertices = 2 triangles)
    // Vertex layout: 0,1,2 = first triangle, 2,1,3 = second triangle
    let vertex_id = input.vertex_index % 6u;
    var quad_pos: vec2<f32>;
    
    switch vertex_id {
        case 0u: { quad_pos = vec2<f32>(-1.0, -1.0); }  // Bottom-left
        case 1u: { quad_pos = vec2<f32>(1.0, -1.0); }   // Bottom-right
        case 2u: { quad_pos = vec2<f32>(-1.0, 1.0); }   // Top-left
        case 3u: { quad_pos = vec2<f32>(-1.0, 1.0); }   // Top-left
        case 4u: { quad_pos = vec2<f32>(1.0, -1.0); }   // Bottom-right
        default: { quad_pos = vec2<f32>(1.0, 1.0); }    // Top-right
    }
    
    // Scale quad by dab size (radius = size / 2)
    let radius = input.dab_size * 0.5;
    let world_pos = input.dab_position + quad_pos * radius;
    
    // Convert to NDC (normalized device coordinates)
    // Canvas space: (0,0) top-left, (width,height) bottom-right
    // NDC space: (-1,-1) bottom-left, (1,1) top-right
    let ndc_x = (world_pos.x / uniforms.canvas_size.x) * 2.0 - 1.0;
    let ndc_y = 1.0 - (world_pos.y / uniforms.canvas_size.y) * 2.0;
    
    output.position = vec4<f32>(ndc_x, ndc_y, 0.0, 1.0);
    output.uv = quad_pos;
    output.color = input.dab_color;
    output.opacity = input.dab_opacity;
    output.hardness = input.dab_hardness;
    
    return output;
}

// Fragment shader: Draw circular brush stamp with soft/hard edges
@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    // Calculate distance from center of dab (UV space is -1 to 1)
    let dist = length(input.uv);
    
    // Discard pixels outside the circle
    if dist > 1.0 {
        discard;
    }
    
    // Apply hardness to create soft or hard edges
    // hardness = 0.0: very soft (linear falloff)
    // hardness = 1.0: very hard (sharp edge)
    let falloff = smoothstep(input.hardness, 1.0, dist);
    let alpha = (1.0 - falloff) * input.opacity;
    
    // Return premultiplied alpha for correct blending
    // Premultiply: RGB = RGB * A
    return vec4<f32>(input.color.rgb * alpha, alpha);
}
