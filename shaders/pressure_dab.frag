// GLSL fragment shader for per-dab pressure-based opacity blending with clamp
// a_out = max(min(flowAlpha + (1 - flowAlpha) * a_dst, opacityClamp), a_dst)
// where flowAlpha = coverage * u_flow

#version 460 core
#include <flutter/runtime_effect.glsl>

precision mediump float;

// Uniforms must be declared in the same order the Dart code writes them
uniform float u_flow;            // 0..1 per-dab flow
uniform float u_opacity_clamp;   // 0..1 pressure opacity cap
uniform float u_core_ratio;      // 0..1 core fraction
uniform vec2 u_center;           // px
uniform float u_radius;          // px
uniform vec2 u_resolution;       // tile size in px
uniform sampler2D u_dst;         // previous accumulation (tile-sized)

out vec4 fragColor;

float coverage_at(vec2 p) {
  vec2 d = p - u_center;
  float dist = length(d);
  if (dist >= u_radius) return 0.0;
  float coreR = clamp(u_core_ratio, 0.0, 1.0) * u_radius;
  if (dist <= coreR) return 1.0;
  float t = (u_radius - dist) / max(1e-6, (u_radius - coreR));
  return clamp(t, 0.0, 1.0);
}

void main() {
  // FlutterFragCoord provides fragment coordinates in device pixels for the
  // drawn rectangle. Divide by u_resolution to get normalized UV for sampling.
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / u_resolution;
  vec4 dst = texture(u_dst, uv);
  float cov = coverage_at(fragCoord);
  float a_src = cov * clamp(u_flow, 0.0, 1.0);
  float a_so = a_src + (1.0 - a_src) * dst.a;          // SrcOver
  float a_clamped = min(a_so, clamp(u_opacity_clamp, 0.0, 1.0));
  float a_out = max(a_clamped, dst.a);
  fragColor = vec4(a_out, a_out, a_out, a_out);
}
