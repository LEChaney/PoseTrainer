// Blit Shader
// Simple full-screen quad that copies a texture to the screen

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@group(0) @binding(0)
var canvas_texture: texture_2d<f32>;

@group(0) @binding(1)
var canvas_sampler: sampler;

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

// Fragment shader: Sample and output texture
@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    return textureSample(canvas_texture, canvas_sampler, input.uv);
}
