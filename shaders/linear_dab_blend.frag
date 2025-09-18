// linear_dab_blend.frag (Flutter GLSL Runtime Effect)
// Linear-light compositing of soft-disc dabs over a background tile.

#include <flutter/runtime_effect.glsl>

uniform sampler2D bgImage;     // existing tile (sRGB premul)
uniform sampler2D dabBuffer;   // 2D texture height=1, two texels per dab
uniform float dabCount;        // number of dabs in buffer
uniform float tileSize;        // tile edge length in pixels
uniform float hardness;        // 0..1
uniform vec3 brushColor;       // sRGB 0..1

out vec4 fragColor;

// SkSL requires loop bounds to be compile-time constants.
const int MAX_DABS = 512;

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

struct Dab { vec2 c; float r; float a; };

Dab loadDab(int i, float texWidth) {
  int t0 = i * 2;
  int t1 = t0 + 1;
  float u0 = (float(t0) + 0.5) / texWidth;
  float u1 = (float(t1) + 0.5) / texWidth;
  vec4 px0 = texture(dabBuffer, vec2(u0, 0.5));
  vec4 px1 = texture(dabBuffer, vec2(u1, 0.5));
  // Decode adaptive fixed:
  // centers: signed with bias and per-dab shift scale (2^s), stored relative to tile center
  // radius: unsigned integer pixels
  float cxRaw = (px0.r * 255.0 + px0.g * 65280.0);
  float cyRaw = (px0.b * 255.0 + px0.a * 65280.0);
  float rRaw  = (px1.r * 255.0 + px1.g * 65280.0);
  float aa = px1.b; // 0..1 alpha
  float shift = px1.a * 255.0; // 0..255, we use 0..15
  float scale = exp2(shift);
  float cx = (cxRaw - 32768.0) / scale + tileSize * 0.5;
  float cy = (cyRaw - 32768.0) / scale + tileSize * 0.5;
  float rr = rRaw; // integer pixel radius
  Dab d;
  d.c = vec2(cx, cy);
  d.r = rr;
  d.a = aa;
  return d;
}

float coverageSoftDisc(vec2 p, vec2 c, float r, float hardness) {
  float d = distance(p, c);
  if (d >= r) return 0.0;
  float core = mix(0.45, 0.8, hardness) * r;
  if (d <= core) return 1.0;
  float t = (d - core) / max(1e-5, (r - core));
  float k = mix(1.5, 3.0, hardness);
  t = clamp(t, 0.0, 1.0);
  float fall = 1.0 - smoothstep(0.0, 1.0, pow(t, k));
  return fall;
}

void main() {
  vec2 xy = FlutterFragCoord();               // pixel in tile space (top-left origin)
  vec2 uv = xy / tileSize;                    // normalized sampling
  vec4 dst = texture(bgImage, uv);            // sRGB premul
  float da = dst.a;
  // Un-premultiply before color space conversion, then re-premultiply in linear.
  vec3 dstSrgb = (da > 0.0) ? (dst.rgb / max(da, 1e-8)) : vec3(0.0);
  vec3 accLin = srgbToLinear(dstSrgb) * da;   // premul linear
  float accA = da;

  // Dab buffer width = max(2, dabCount*2).
  float dabWidth = max(2.0, dabCount * 2.0);
  int count = int(max(0.0, dabCount + 0.5));
  // Precompute brush color in linear space (non-premultiplied).
  vec3 brushLin = srgbToLinear(brushColor);
  for (int i = 0; i < MAX_DABS; i++) {
    if (i >= count) break;
    Dab d = loadDab(i, dabWidth);
    float cov = coverageSoftDisc(xy, d.c, d.r, hardness);
    float sa = d.a * cov; // src alpha
    if (sa <= 0.0) continue;
    vec3 srcLin = brushLin * sa;
    accLin = srcLin + accLin * (1.0 - sa);
    accA = sa + accA * (1.0 - sa);
  }

  vec3 outRgb = vec3(0.0);
  if (accA > 0.0) outRgb = linearToSrgb(accLin / accA);
  fragColor = vec4(outRgb * accA, accA);
}
