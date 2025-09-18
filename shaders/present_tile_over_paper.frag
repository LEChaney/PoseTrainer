// present_tile_over_paper.frag
// Composites a premultiplied sRGB tile over an sRGB paper color,
// performing SrcOver in linear space and outputting opaque sRGB.

#include <flutter/runtime_effect.glsl>

uniform sampler2D tileImage;   // tile contents, premultiplied sRGB
uniform float tileSize;        // square tile edge in pixels
uniform vec3 paperLinPremul;   // paper color in Linear space, premultiplied

out vec4 fragColor;

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

void main() {
  vec2 xy = FlutterFragCoord();
  vec2 local_xy = mod(xy, vec2(tileSize)); // pixel in tile space (top-left origin)
  vec2 uv = local_xy / tileSize;
  vec4 t = texture(tileImage, uv);

  vec3 srcLinPremul = srgbToLinear(t.rgb);
  float srcAlpha = t.a;

  // Linear SrcOver: out = src + dst * (1 - src.a)
  vec3 outLinPremul = srcLinPremul + paperLinPremul * (1.0 - srcAlpha);

  vec3 outSrgb = linearToSrgb(outLinPremul);
  fragColor = vec4(outSrgb, 1.0);
}
