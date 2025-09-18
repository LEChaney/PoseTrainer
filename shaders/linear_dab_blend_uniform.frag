// linear_dab_blend_uniform.frag (Flutter GLSL Runtime Effect)
// Linear-light compositing of soft-disc dabs using uniform arrays.

#include <flutter/runtime_effect.glsl>

uniform sampler2D bgImage;     // existing tile (sRGB premul)
uniform float dabCount;        // number of dabs provided (<= MAX_DABS)
uniform float tileSize;        // tile edge length in pixels
uniform float hardness;        // 0..1
uniform vec3 brushColorLin;    // 0..1 pre-converted to linear space
uniform vec4 dabs[64];        // (cx, cy, r, alpha) in tile-local px

out vec4 fragColor;

// SkSL requires loop bounds to be compile-time constants.
const int MAX_DABS = 64;

vec3 srgbToLinear(vec3 c) {
  vec3 lo = c / 12.92;
  vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
  return mix(lo, hi, step(vec3(0.04045), c));
}

vec3 linearToSrgb(vec3 c) {
  vec3 lo = c * 12.92;
  vec3 hi = 1.055 * pow(c, vec3(1.0/2.4)) - 0.055;
  return mix(lo, hi, step(vec3(0.0031308), c));
}

float coverageSoftDisc(vec2 p, vec2 center, float radius, float hardness) {
// Debug: hard mask for quick inspection — full coverage inside radius, zero outside.
// Keep original soft-disc code below (commented) so it can be restored easily.
float d = distance(p, center);
if (d <= radius) {
    return 1.0;
}
return 0.0;

/* Original implementation:
float d = distance(p, center);
if (d >= radius) return 0.0;
float core = mix(0.45, 0.8, hardness) * radius;
if (d <= core) return 1.0;
float t = (d - core) / max(1e-5, (radius - core));
float k = mix(1.5, 3.0, hardness);
t = clamp(t, 0.0, 1.0);
float fall = 1.0 - smoothstep(0.0, 1.0, pow(t, k));
return fall;
*/
}

void main() {
  vec2 xy = FlutterFragCoord();               // pixel in tile space (top-left origin)
  vec2 uv = xy / tileSize;                    // normalized sampling
  vec4 dst = texture(bgImage, uv);            // sRGB premul
  vec3 accLin = srgbToLinear(dst.rgb);
  float accAlpha = dst.a;

  int count = int(clamp(dabCount, 0.0, float(MAX_DABS)) + 0.5);
  for (int i = 0; i < MAX_DABS; i++) {
    if (i >= count) break;
    vec4 dab = dabs[i];
    vec2 center = dab.xy;
    float radius = dab.z;
    float alpha = dab.w;
    float cov = coverageSoftDisc(xy, center, radius, hardness);
    float srcAlpha = alpha * cov;
    if (srcAlpha <= 0.0) continue;
    vec3 srcLin = brushColorLin * srcAlpha;
    accLin = srcLin + accLin * (1.0 - srcAlpha);
    accAlpha = srcAlpha + accAlpha * (1.0 - srcAlpha);
  }

  vec3 outRgb = linearToSrgb(accLin);
  fragColor = vec4(outRgb, accAlpha);
}
