You: 

In flutter, when using the custom painter functionality, how does skia handle srgb and blending? Is the framebuffer (dst buffer) something like kR8G8B8A8UNormIntSRGB (flutter platform agnostic srgb normalised 8 bit format). Will blending happen in linear space? With the image written back to srgb?

ChatGPT: 

Thought for 2m 11s

Short answer:

-   **Skia blends in the destination color space.** By default it does **not** linearize, blend, then re-encode. If your destination surface is sRGB-encoded, Skia applies the usual blend equations **on the sRGB-encoded numbers** (perceptually non-linear), which is mathematically “wrong” but historically expected. To get correct results, the destination surface itself must be linear. [Skia+1](https://skia.org/docs/dev/design/raster_tragedy/)
    
-   **The actual framebuffer format in Flutter is platform/backend dependent.** You shouldn’t assume a single “kR8G8B8A8UnormSRGB” across all targets. On modern Flutter, surfaces are typically 8-bit RGBA/BGRA with premultiplied alpha; with Impeller (the default on iOS/Android now), the engine also supports wide-gamut/extended spaces (e.g., Display-P3 and “extended sRGB”). Which one you get depends on device and backend. [docs.flutter.dev+2docs.flutter.dev+2](https://docs.flutter.dev/perf/impeller?utm_source=chatgpt.com)
    
-   **Will blending happen in linear space?** Only if the **destination surface is linear** (e.g., Skia surface created with a linear sRGB color space or a linear F16 surface). Otherwise, blending happens in the destination’s transfer function (sRGB if that’s your surface). [Skia+1](https://skia.org/docs/dev/design/raster_tragedy/)
    
-   **Is the image written back to sRGB?** If your render target is sRGB-encoded, Skia/GPU backends store encoded values there (and the window system will ultimately present in the display’s space). If you render to a linear surface, you’d typically convert to sRGB (or the display’s space) at presentation or when sampling into an sRGB target. (Exact timing of conversions is backend-specific, but Skia’s rule of thumb is “convert sources to the destination’s color space, then blend in that space.”) [Skia](https://skia.org/docs/dev/design/raster_tragedy/)
    

### What this means for `CustomPainter`

-   In Flutter you don’t directly pick the SkSurface/attachment format from `CustomPainter`. Your paints land on whatever surface the engine set up for that frame (sRGB/extendedSRGB/DisplayP3 varies by device/backend). As a result, **you can’t force linear-space blending for Skia’s fixed-function blends from Dart** today; it follows the destination’s space. [docs.flutter.dev+1](https://docs.flutter.dev/release/breaking-changes/wide-gamut-framework?utm_source=chatgpt.com)
    
-   If you **must** ensure linear math for certain ops:
    
    -   Do your compositing in a **shader** (Flutter `FragmentProgram`) that linearizes inputs, does the math, then re-encodes before writing—this avoids intermediate fixed-function blending. (SkSL even exposes helpers `toLinearSrgb`/`fromLinearSrgb`.) [Skia](https://skia.org/docs/user/sksl/?utm_source=chatgpt.com)
        
    -   Or render into an offscreen target that the engine configures as **linear** (where supported) and then present—this control is available at the engine layer (C++/Impeller), but not directly from `CustomPainter`.
        

#### References

-   Skia design note on blending (“Raster Tragedy”): convert sources to **destination** color space; blending happens **in that space**; linear blending requires a **linearly encoded destination**. [Skia](https://skia.org/docs/dev/design/raster_tragedy/)
    
-   Skia team guidance: `SkColor` is assumed sRGB; to get linear blending, create a surface with a **linear** color space. [groups.google.com](https://groups.google.com/g/skia-discuss/c/jN0SllyXJ3c?utm_source=chatgpt.com)
    
-   Skia API note on using SRGB-linear/linear surfaces for correct blending. [groups.google.com](https://groups.google.com/g/skia-discuss/c/gi_WWpnOJno?utm_source=chatgpt.com)
    
-   Flutter/Impeller wide-gamut/extended color support and `dart:ui ColorSpace` docs (sRGB, extendedSRGB, DisplayP3). [docs.flutter.dev+2docs.flutter.dev+2](https://docs.flutter.dev/perf/impeller?utm_source=chatgpt.com)
    

If you tell me the specific platform(s) you’re targeting (iOS/Android/Desktop) and what you’re blending (images, gradients, text), I can sketch concrete shader snippets or a rendering approach that guarantees linear math end-to-end.

You: 

How can I blend in linear space using flutter in web?

ChatGPT: 

Thought for 1m 11s

Short version: on Flutter Web you can’t make the browser/Skia do **fixed-function blending in linear** for you. The WebGL backbuffer is effectively sRGB and browsers don’t expose a “linear backbuffer” switch, so Skia (via CanvasKit) blends in the destination space (sRGB) just like on other platforms unless the destination surface itself is linear—which you can’t reliably request on the web today. [GitHub+1](https://github.com/KhronosGroup/WebGL/issues/2474?utm_source=chatgpt.com)

That said, you *can* get **linear-space results** by doing the math inside a fragment shader (so you avoid fixed-function blending), then writing the result to the sRGB canvas. Flutter Web supports runtime fragment shaders (`FragmentProgram`). SkSL provides handy intrinsics to convert between the working (dest) space and **linear sRGB**: `toLinearSrgb()` / `fromLinearSrgb()`. [docs.flutter.dev+2Skia+2](https://docs.flutter.dev/ui/design/graphics/fragment-shaders?utm_source=chatgpt.com)

## Practical recipe (works on Flutter Web)

1.  **Use a runtime fragment shader** for the compositing you care about (gradients, glows, “SrcOver” with known background, etc.). Linearize, do math, then re-encode:
    
    ```glsl
    // myshader.sksl
    uniform shader srcImage;   // your source (e.g., color/texture)
    uniform shader bgImage;    // background you’re compositing onto (optional)
    uniform float  opacity;    // 0..1
    
    half4 main(float2 xy) {
      half4 src = srcImage.eval(xy);
      half4 bg  = bgImage.eval(xy);
    
      // Convert to linear sRGB
      half3 sLin = toLinearSrgb(src.rgb);
      half3 bLin = toLinearSrgb(bg.rgb);
    
      // Do linear “SrcOver”
      half a = src.a * opacity;
      half3 outLin = sLin + (1.0 - a) * bLin;
    
      // Convert back to display space (usually sRGB)
      half3 outEnc = fromLinearSrgb(outLin);
      return half4(outEnc, a + (1.0 - a) * bg.a);
    }
    ```
    
    Those `toLinearSrgb` / `fromLinearSrgb` intrinsics are built into SkSL specifically for this use case. [Skia+1](https://skia.org/docs/user/sksl/?utm_source=chatgpt.com)
    
2.  **Feed it from Dart** with `FragmentProgram` on web (CanvasKit renderer). You load the shader and bind textures (your source & background) as `ImageShader`s; set `opacity` as a uniform; then paint a rect with a `Paint()..shader = fragmentShader`. Flutter’s web docs cover loading and using fragment shaders. [docs.flutter.dev](https://docs.flutter.dev/ui/design/graphics/fragment-shaders?utm_source=chatgpt.com)
    
3.  **Avoid fixed-function blending.** When drawing the shader quad, use the default `BlendMode.src` (or paint to an offscreen layer first) so the browser doesn’t re-blend your already-composited pixels in sRGB. (The whole point is: you *did* the blend in linear inside the shader; don’t let the backbuffer blend again.) Why? Because the WebGL backbuffer is not linear-blendable. [GitHub](https://github.com/KhronosGroup/WebGL/issues/2474?utm_source=chatgpt.com)
    

### What about arbitrary background content?

You can’t read the true framebuffer in a Flutter shader. To composite correctly you need the **actual background as an input texture**:

-   If you control the scene graph, render the background into an `Image` (e.g., via `PictureRecorder` + `toImage`) and pass it as `bgImage` to the shader, then draw your linear-composited result. (It’s an extra pass and can be costly on web.)
    
-   If you *can’t* capture the background, you can still use the linear shader for self-contained effects (procedural gradients, image filters, lighting) and draw them opaquely or onto known solid backgrounds to avoid sRGB-space blending at the edges.
    

### Why not just “make the surface linear”?

Today the web stack doesn’t offer a reliable, portable way to request a **linear** destination surface/backbuffer for WebGL/CanvasKit; the long-standing Khronos thread explains the limitation. So the **only portable route** to linear blending on Flutter Web is “do the math in the shader.” [GitHub](https://github.com/KhronosGroup/WebGL/issues/2474?utm_source=chatgpt.com)

---

If you want, tell me what you’re blending (images over photos? gradient fields? glow passes?) and I’ll tailor a minimal Dart setup that wires two `ImageShader`s into a `FragmentProgram` and shows the correct linear “SrcOver.”

You: 

Can you show how I could use this to create linearly blended paint dabs on a surface. Using drawcircle for the dabs

ChatGPT: 

Thought for 36s

Yep—here’s a practical way to get **linearly blended paint dabs** on Flutter Web while still using `drawCircle` to author each dab.

The trick:

1.  draw each dab onto a **transparent offscreen image** (so `drawCircle` never touches the real framebuffer),
    
2.  **linearly composite** that dab over your running “surface” using a **runtime fragment shader**, and
    
3.  update the accumulation image.
    

This avoids the browser’s fixed-function sRGB blending.

---

# 1) Shader (linear SrcOver)

Create `shaders/linear_blend.sksl`:

```glsl
// linear_blend.sksl
// Composites srcImage over bgImage in *linear sRGB* and outputs encoded sRGB.

uniform shader bgImage;   // accumulation so far
uniform shader srcImage;  // the dab image (transparent outside the circle)

half3 srgbToLinear(half3 c) {
  half3 lt = c / 12.92;
  half3 gt = pow((c + 0.055) / 1.055, 2.4);
  return mix(lt, gt, step(0.04045, c));
}

half3 linearToSrgb(half3 c) {
  half3 lt = c * 12.92;
  half3 gt = 1.055 * pow(max(c, 0.0h), 1.0/2.4) - 0.055;
  return mix(lt, gt, step(0.0031308, c));
}

half4 main(float2 xy) {
  half4 bg  = bgImage.eval(xy);   // encoded sRGB, premul
  half4 src = srcImage.eval(xy);  // encoded sRGB, premul

  // Un-premultiply for accurate color math (avoid NaNs)
  half3 bgRgb  = (bg.a > 0.0h)  ? bg.rgb / bg.a  : half3(0);
  half3 srcRgb = (src.a > 0.0h) ? src.rgb / src.a: half3(0);

  // Convert to linear sRGB
  half3 bLin = srgbToLinear(bgRgb);
  half3 sLin = srgbToLinear(srcRgb);

  // Linear SrcOver
  half aOut   = src.a + (1.0h - src.a) * bg.a;
  half3 cOutL = (sLin * src.a) + (bLin * bg.a * (1.0h - src.a));
  half3 cOutU = (aOut > 0.0h) ? (cOutL / aOut) : half3(0);

  // Back to encoded sRGB and premultiply
  half3 enc = linearToSrgb(cOutU);
  return half4(enc * aOut, aOut);
}
```

Compile this with `flutter build` (Flutter will compile `.sksl` to `.spirv` on web automatically when you load it as a runtime shader).

---

# 2) Dart: offscreen dab + linear composite

Below is a minimal example. It:

-   Keeps an **accumulation** image the size of the canvas.
    
-   For each dab, it draws a circle onto a transparent offscreen image using **`drawCircle`**.
    
-   Runs the shader to blend `dab` over `accum` **in linear** to produce a new `accum`.
    
-   Paints the final `accum` to the screen.
    

```dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class LinearDabsDemo extends StatefulWidget {
  const LinearDabsDemo({super.key});
  @override
  State<LinearDabsDemo> createState() => _LinearDabsDemoState();
}

class _LinearDabsDemoState extends State<LinearDabsDemo> {
  ui.Image? _accum;
  late final Future<FragmentProgram> _progFut;

  @override
  void initState() {
    super.initState();
    _progFut = FragmentProgram.fromAsset('shaders/linear_blend.sksl');
  }

  Future<ui.Image> _blankImage(Size size) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(Offset.zero & size, Paint()..blendMode = BlendMode.src);
    final pic = rec.endRecording();
    return pic.toImage(size.width.ceil(), size.height.ceil());
  }

  Future<ui.Image> _drawDab(Size size, Offset center, double radius, Color color, {double opacity = 1.0}) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);

    // Transparent background; use src so we don't accidentally blend into it.
    final p = Paint()
      ..blendMode = BlendMode.src
      ..color = color.withOpacity(opacity);
    c.drawCircle(center, radius, p);

    final pic = rec.endRecording();
    return pic.toImage(size.width.ceil(), size.height.ceil());
  }

  Future<ui.Image> _linearComposite({
    required Size size,
    required FragmentProgram program,
    required ui.Image bg,   // accumulation so far
    required ui.Image src,  // dab image
  }) async {
    final shader = program.fragmentShader();

    // Build child shaders for bg and src
    final bgShader = ImageShader(
      bg, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage,
    );
    final srcShader = ImageShader(
      src, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage,
    );

    // Compose: paint a full-rect filled by our fragment shader
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final paint = Paint()
      ..shader = ShaderBuilder(shader)
          .child('bgImage', bgShader)
          .child('srcImage', srcShader)
          .build();

    // IMPORTANT: avoid fixed-function blending; we already composited in the shader.
    paint.blendMode = BlendMode.src;

    canvas.drawRect(Offset.zero & size, paint);

    final pic = rec.endRecording();
    return pic.toImage(size.width.ceil(), size.height.ceil());
  }

  // Tiny helper to attach child shaders to a runtime fragment shader by name.
  // (Works with CanvasKit; if you use a different API, adapt as needed.)
  ShaderBuilder get ShaderBuilder => _ShaderBuilder;
  // Minimal builder that mirrors how child shaders are set by name.
}

// ---------------- Painter UI ----------------

class _Canvas extends StatelessWidget {
  final ui.Image? accum;
  const _Canvas({required this.accum});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _Painter(accum),
      size: const Size(double.infinity, double.infinity),
    );
  }
}

class _Painter extends CustomPainter {
  final ui.Image? accum;
  _Painter(this.accum);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src); // known background
    if (accum != null) {
      final paint = Paint()..blendMode = BlendMode.srcOver;
      canvas.drawImage(accum!, Offset.zero, paint);
    }
  }

  @override
  bool shouldRepaint(_Painter old) => old.accum != accum;
}

// ---------------- Putting it together ----------------

class _ShaderBuilder {
  final FragmentShader shader;
  final Map<String, Shader> _children = {};
  _ShaderBuilder(this.shader);
  _ShaderBuilder child(String name, Shader s) { _children[name] = s; return this; }
  Shader build() {
    // CanvasKit matches child names in declaration order; when using SkSL,
    // Flutter binds "uniform shader <name>;" children by position, not strings.
    // If your Flutter version needs positional binding, you can use
    // FragmentShader.setShader(i, shader) before 3.22; adapt as needed.
    // Below is a fallback that just returns the bg child (so we can attach it
    // via Paint.shader). In practice, use the official `FragmentShader`
    // child-binding API available in your Flutter version.
    return _children.values.first;
  }
}

class DabsPage extends StatefulWidget {
  const DabsPage({super.key});
  @override
  State<DabsPage> createState() => _DabsPageState();
}

class _DabsPageState extends State<DabsPage> {
  ui.Image? _accum;
  FragmentProgram? _program;

  @override
  void initState() {
    super.initState();
    FragmentProgram.fromAsset('shaders/linear_blend.sksl').then((p) {
      setState(() => _program = p);
    });
  }

  Future<void> _ensureAccum(Size size) async {
    if (_accum == null) {
      _accum = await _blankImage(size);
      setState(() {});
    }
  }

  Future<void> _addDab(TapDownDetails d, Size size) async {
    await _ensureAccum(size);
    final dab = await _drawDab(size, d.localPosition, 40, Colors.orange, opacity: 0.6);
    final next = await _linearComposite(
      size: size,
      program: _program!,
      bg: _accum!,
      src: dab,
    );
    _accum!.dispose();
    _accum = next;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _addDab(d, size),
        child: _Canvas(accum: _accum),
      );
    });
  }

  // --- offscreen helpers reused (same as earlier) ---
  Future<ui.Image> _blankImage(Size size) async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Offset.zero & size, Paint()..blendMode = BlendMode.src);
    final pic = rec.endRecording();
    return pic.toImage(size.width.ceil(), size.height.ceil());
  }

  Future<ui.Image> _drawDab(Size size, Offset center, double radius, Color color, {double opacity = 1.0}) async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final paint = Paint()
      ..blendMode = BlendMode.src
      ..color = color.withOpacity(opacity);
    canvas.drawCircle(center, radius, paint);
    final pic = rec.endRecording();
    return pic.toImage(size.width.ceil(), size.height.ceil());
  }

  Future<ui.Image> _linearComposite({
    required Size size,
    required FragmentProgram program,
    required ui.Image bg,
    required ui.Image src,
  }) async {
    final shader = program.fragmentShader();
    // If your Flutter version exposes explicit child setters, bind `bg` to
    // index 0 and `src` to index 1 here. Otherwise, wrap in ImageShaders
    // and use a helper as shown earlier (implementation varies by version).
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);

    // Build child shaders
    final bgSh = ImageShader(bg, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage);
    final srcSh = ImageShader(src, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage);

    // Attach (adapt child binding to your Flutter version)
    final paint = Paint()
      ..shader = _ShaderBuilder(shader)
          .child('bgImage', bgSh)
          .child('srcImage', srcSh)
          .build()
      ..blendMode = BlendMode.src; // Prevent sRGB backbuffer re-blend.

    canvas.drawRect(Offset.zero & size, paint);
    final pic = rec.endRecording();
    return pic.toImage(size.width.ceil(), size.height.ceil());
  }
}
```

> ⚠️ Binding child shaders
> 
> Flutter’s runtime-shader API has evolved. In recent versions you can bind **child shaders** by index on `FragmentShader` (e.g., `setSampler(i, shader)`), or via generated helpers. If the little `_ShaderBuilder` shim above doesn’t match your Flutter version, replace it with the official calls for your SDK. The key idea remains: pass **two child shaders** (`bgImage` and `srcImage`) into the fragment shader.

---

## Performance notes (Web)

-   `toImage()` on web goes through CanvasKit → WebGL readbacks and isn’t cheap. For many small dabs per frame, batch several circles into one **dab layer** (draw multiple `drawCircle`s onto the same transparent picture) before a single shader composite.
    
-   If all dabs are the same radius/softness, consider a **procedural circle** in the shader (no offscreen dab image at all): just pass center/radius as uniforms and run one full-screen composite per batch.
    
-   Always set the **final draw** that uses the fragment shader to `BlendMode.src` to avoid a second sRGB-space reblend.
    

If you tell me your Flutter version, I’ll swap in the exact child-binding API for `FragmentShader` and (optionally) show the procedural-circle version (no offscreen dab image).

You: 

A full screen composite seems slow, my accumulation image is alert tiled, so it makes sense to render only touched tiles for compositing. Is there a good way to batch multiple dabs in one draw call as well? With different radius / color/ opacity

ChatGPT: 

Thought for 25s

Great idea—tile the accumulation and only touch the tiles you actually hit. You’ve got two good batching paths on Flutter Web:

---

# Option A (simpler, often fastest): “dab layer per tile” → 1 composite draw

**Idea:** For each touched tile, record **all** the `drawCircle` dabs onto a *tile-sized transparent picture/image* (that’s just CPU command recording → one GPU texture). Then do **one** shader composite of that tile over your accumulation in **linear** space.

-   You still get linearly correct blending (the **composite** happens in your shader).
    
-   Recording multiple `drawCircle`s to the **same** offscreen picture doesn’t cost multiple backbuffer draws; it builds one tile texture you use once.
    
-   This avoids per-fragment loops in the shader.
    

**Flow per tile:**

1.  `PictureRecorder` (tile rect only)
    
2.  Draw N circles with `BlendMode.src` onto that recording
    
3.  `toImage(tileW, tileH)` → `tileDabImage`
    
4.  Run your **linear-blend** shader once for that tile:
    
    -   `bgImage` = the tile region of the accumulation
        
    -   `srcImage` = `tileDabImage`
        
    -   draw a rect clipped to the tile with `BlendMode.src` (no fixed-function reblend)
        

This is usually the best “bang for buck” unless tiles get hundreds of dabs every frame (where step 2’s recording might become your bottleneck).

---

# Option B (one draw per tile, all dabs procedurally in the shader)

If you want **one draw call** per tile even as the number of dabs grows, push the dab parameters to the fragment shader and loop there. You’ll avoid building an intermediate image, at the cost of more ALU.

## SkSL: batched linear SrcOver for many dabs

Below uses *fixed-size* uniform arrays (SkSL needs a const bound). Increase `MAX_DABS` to taste; if you exceed it, split into multiple passes for that tile (still cheap—they’re tiny).

```glsl
// shaders/linear_dabs_tile.sksl
// Composites many circles (varying center/radius/color/opacity) over bg in *linear sRGB*.
// Draw only over the tile's rect, with BlendMode.src on the paint (we already composite here).

uniform shader bgImage;     // accumulation so far (encoded sRGB, premultiplied)
uniform int     dabCount;   // how many active dabs <= MAX_DABS
uniform float2  tileOrigin; // top-left of this tile in canvas coordinates

const int MAX_DABS = 64; // tune this

// Per-dab packed params (arrays must be const-sized in SkSL runtime effects)
uniform float2  dabCenter[MAX_DABS];  // in canvas coords
uniform float   dabRadius[MAX_DABS];  // pixels
uniform half4   dabColor[MAX_DABS];   // encoded sRGB, premultiplied; alpha is dab opacity

// Helpers (SkSL also offers toLinearSrgb/fromLinearSrgb intrinsics if available)
half3 srgbToLinear(half3 c) {
  half3 lt = c / 12.92;
  half3 gt = pow((c + 0.055) / 1.055, 2.4);
  return mix(lt, gt, step(0.04045, c));
}
half3 linearToSrgb(half3 c) {
  half3 lt = c * 12.92;
  half3 gt = 1.055 * pow(max(c, 0.0h), 1.0/2.4) - 0.055;
  return mix(lt, gt, step(0.0031308, c));
}

half4 main(float2 fragPos) {
  // Sample background at this pixel
  half4 bg = bgImage.eval(fragPos);
  half aAcc   = bg.a;
  half3 cAccU = (aAcc > 0.0h) ? (bg.rgb / aAcc) : half3(0);
  half3 cAccL = srgbToLinear(cAccU); // work in linear

  // Composite dabs (painter’s order = array order)
  // Early reject by tile-local distance
  for (int i = 0; i < dabCount; ++i) {
    float2 center = dabCenter[i];
    float  r      = dabRadius[i];

    // Cheap circle mask
    float2 d = fragPos - center;
    if (dot(d,d) > r*r) {
      continue;
    }

    half4 src = dabColor[i]; // premultiplied sRGB
    // Unpremul → linear
    half  aS   = src.a;
    if (aS <= 0.0h) { continue; }
    half3 cSU  = src.rgb / aS;
    half3 cSL  = srgbToLinear(cSU);

    // Linear SrcOver: cAccL = cS*aS + cAccL*(1 - aS)
    cAccL = cSL * aS + cAccL * (1.0h - aAcc * 0.0h - aS); // note: bg is already in cAccL
    // Alpha accumulates in non-premul SrcOver:
    aAcc  = aS + (1.0h - aS) * aAcc;
  }

  // Encode back to sRGB and premultiply
  half3 cOutU = (aAcc > 0.0h) ? (cAccL / aAcc) : half3(0);
  half3 enc   = linearToSrgb(cOutU);
  return half4(enc * aAcc, aAcc);
}
```

> Implementation note: if your SkSL supports `toLinearSrgb` / `fromLinearSrgb`, you can replace the helper functions with those intrinsics for clarity and speed.

## Dart side (per tile)

-   Keep your **dab list per tile** (sorted by paint order).
    
-   Upload packed uniforms once per tile, draw **one** rect (the tile bounds).
    
-   Use `BlendMode.src` for the shader draw so the browser doesn’t re-blend.
    

Pseudo-wiring (leaving out boilerplate):

```dart
final prog = await FragmentProgram.fromAsset('shaders/linear_dabs_tile.sksl');
final fs   = prog.fragmentShader();

void compositeTile({
  required Rect tileRect,
  required ui.Image bgTile, // the current accumulation tile (as an ImageShader)
  required List<Dab> dabs,  // centers/radii/colors for this tile
  required Canvas canvas,
}) {
  // Build child shader for bg
  final bgShader = ImageShader(
    bgTile, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage,
  );

  // Bind child shader [0] = bgImage (API differs slightly by Flutter version)
  // Then push uniforms in the declared order:
  // int dabCount; float2 tileOrigin; arrays...
  final floats = <double>[];
  // Some runtimes need alignment; keep it simple and contiguous.

  // dabCount is often set as float due to API; or use setUniforms with i32 if supported.
  final dabCount = dabs.length.clamp(0, 64);
  floats.add(dabCount.toDouble());

  floats.addAll([tileRect.left, tileRect.top]);

  // centers
  for (var i = 0; i < 64; ++i) {
    final d = (i < dabs.length) ? dabs[i] : null;
    floats.add(d?.center.dx ?? 0);
    floats.add(d?.center.dy ?? 0);
  }
  // radii
  for (var i = 0; i < 64; ++i) {
    floats.add(i < dabs.length ? dabs[i].radius : 0);
  }
  // colors (premultiplied sRGB)
  Color premul(Color c) => c; // Flutter Colors are premultiplied in shaders; keep RGBA as usual
  for (var i = 0; i < 64; ++i) {
    final c = i < dabs.length ? premul(dabs[i].color.withOpacity(dabs[i].opacity)) : const Color(0x00000000);
    floats.addAll([c.red/255.0, c.green/255.0, c.blue/255.0, c.alpha/255.0]);
  }

  // Set uniforms & child shader (API depends on Flutter version; examples):
  // fs.setImageSampler(0, bgShader);
  // fs.setFloat(0, floats); // or setBytes(...) depending on your SDK

  final paint = Paint()
    ..shader = fs
    ..blendMode = BlendMode.src; // we've already composited linearly

  canvas.save();
  canvas.clipRect(tileRect);
  canvas.drawRect(tileRect, paint);
  canvas.restore();
}
```

> Uniform binding differs slightly across Flutter versions (3.19–3.24 changed the runtime shader API). If your SDK exposes generated wrapper classes for your shader, use those to set `dabCount`, `tileOrigin`, and the arrays cleanly; otherwise, pack into a `Float32List` in the same order as the uniforms and use the generic setter.

---

## Which option should you pick?

-   **Option A (dab layer image)**: Best overall when most tiles get *a handful to a few dozen* dabs. It minimizes shader ALU and memory traffic; you pay one `toImage` per touched tile.
    
-   **Option B (procedural loop)**: Best if you want *strictly one draw call per tile* and can accept higher fragment cost. Also good when you want super-dynamic dab shapes/softness without rebuilding images.
    

### Extra batching tips (both options)

-   **Touch map:** Track touched tiles in a `HashSet<Point<int>>`; only composite those.
    
-   **Per-tile queues:** Append dabs to the tile they intersect. If a dab spans multiple tiles, split it (cheap).
    
-   **Order:** Preserve paint order if you rely on over/under effects (use the list order in your loop).
    
-   **Culling:** Before uploading/looping, drop dabs that don’t intersect the tile’s bounds (AABB check).
    
-   **Soft edges:** If you want soft brushes, in Option B compute a smoothstep falloff and treat alpha = falloff \* opacity; in Option A render the circle with a radial gradient.
    

If you tell me your Flutter version (so I can match the exact `FragmentShader` uniform/child binding calls) and your tile size, I’ll drop in ready-to-paste code for either Option A or B—including a soft-edge brush and a fast AABB cull.

You: 

How can we render multiple draw circles to the same tile without non-linear blending of these dabs in option A though. It doesn’t seem like this would work.

ChatGPT: 

Thought for 22s

You’re absolutely right: with **Option A**, as soon as two dabs overlap inside the tile image, the *recording* of those circles (via `drawCircle`) will be blended by the offscreen surface in **sRGB**. That breaks linear correctness before your one big “linear composite” even happens. On Flutter Web you can’t request a linear offscreen surface, so there’s no way to make Option A linear when there’s overlap.

So the workable paths are:

## 1) All-in-shader per tile (recommended)

Do the dab math in a **tile fragment shader** (linearize → loop all dabs → SrcOver in linear → encode). That gives you **one draw per touched tile** and stays perfectly linear no matter how many overlaps, with varying radius/color/opacity.

**SkSL (soft dabs, linear SrcOver):**

```glsl
// shaders/linear_dabs_tile.sksl
uniform shader bgImage;     // sRGB-encoded, premul
uniform int     dabCount;   // <= MAX_DABS
const int MAX_DABS = 64;

uniform float2 dabCenter[MAX_DABS]; // canvas coords
uniform float  dabRadius[MAX_DABS]; // px
uniform half   dabHardness[MAX_DABS]; // 0..1 (0=soft edge, 1=hard)
uniform half4  dabColor[MAX_DABS]; // sRGB-encoded, premul; alpha = opacity

inline half3 toLin(half3 c) {
  half3 lt = c / 12.92;
  half3 gt = pow((c + 0.055) / 1.055, 2.4);
  return mix(lt, gt, step(0.04045, c));
}
inline half3 fromLin(half3 c) {
  half3 lt = c * 12.92;
  half3 gt = 1.055 * pow(max(c, 0.0h), 1.0/2.4) - 0.055;
  return mix(lt, gt, step(0.0031308, c));
}

half smoothMask(float dist, float r, half hard) {
  // soft falloff ~3 px by default, scaled by hardness
  float feather = max(1.0, mix(3.0, 0.5, hard));
  return saturate(1.0 - smoothstep(r - feather, r + feather, dist));
}

half4 main(float2 fragPos) {
  // start from bg in linear, non-premul working color
  half4 bg = bgImage.eval(fragPos);
  half  aAcc   = bg.a;
  half3 cAccU  = (aAcc > 0.0h) ? (bg.rgb / aAcc) : half3(0);
  half3 cAccL  = toLin(cAccU);

  // painter’s order = array order
  for (int i = 0; i < dabCount; ++i) {
    float2 d    = fragPos - dabCenter[i];
    float  r    = dabRadius[i];
    float  d2   = dot(d, d);
    if (d2 > (r + 4.0)*(r + 4.0)) continue; // cheap reject with feather margin

    half  m     = smoothMask(sqrt(d2), r, dabHardness[i]); // 0..1
    if (m <= 0.0h) continue;

    half4 src   = dabColor[i];          // premul sRGB
    half  aS    = src.a * m;            // apply mask to alpha
    if (aS <= 0.0h) continue;

    half3 cSU   = src.rgb / max(src.a, 1e-6h); // unpremul color
    half3 cSL   = toLin(cSU);

    // linear SrcOver on non-premul colors/alphas
    cAccL = cSL * aS + cAccL * (1.0h - aS);
    aAcc  = aS + (1.0h - aS) * aAcc;
  }

  half3 cOutU = (aAcc > 0.0h) ? (cAccL / aAcc) : half3(0);
  half3 enc   = fromLin(cOutU);
  return half4(enc * aAcc, aAcc); // premul out
}
```

**Dart side (per touched tile):**

-   Gather all dabs intersecting the tile.
    
-   Pack uniforms (centers/radii/hardness/colors) up to `MAX_DABS` (split into multiple passes if you exceed).
    
-   Bind `bgImage` to an `ImageShader` sampling the tile from your accumulation image.
    
-   Draw **one rect** (the tile bounds) with `BlendMode.src` (so the browser doesn’t reblend).
    
-   Write the shader output back into the accumulation tile image (replace the tile).
    

This is linear, supports varying radius/color/opacity/softness, and keeps your draw count to **1 per tile** (or `ceil(count/MAX_DABS)` if you exceed the uniform cap).

## 2) Hybrid batching (chunked)

If some tiles occasionally have, say, 200+ dabs, keep the same shader but run it in **chunks** of 64–128 dabs (set `dabCount` each pass). That reduces per-tile draws from N to ~N/64 while staying fully linear.

## Why Option A can’t be fixed on Web

-   Offscreen `PictureRecorder` → `toImage()` uses the WebGL sRGB backbuffer on CanvasKit; overlaps inside that temporary image are blended in sRGB. There’s no portable way to force a linear FBO on Flutter Web today, so any overlapping `drawCircle`s recorded to the same image will be non-linear.
    
-   Doing “one dab per image” and then a linear composite per dab *would* be correct but explodes your draw calls (one shader draw per dab), which is what we’re trying to avoid.
    

## Practical wiring tips

-   **Uniform packing:** Keep a preallocated `Float32List` sized for `MAX_DABS` to avoid churn. For colors, pass standard RGBA (premul in source), apply mask in the shader.
    
-   **Culling:** AABB test dabs against the tile rect before uploading. Cheap and big win.
    
-   **Ordering:** If artistic order matters (wet-on-wet look), just keep array order = paint order.
    
-   **Tile updates:** Maintain a `Set<TileCoord>` of touched tiles per frame; only read/update those tiles from the accumulation image.
    
-   **Soft brushes:** Use the `dabHardness` uniform to tune edge feather per dab without new textures.
    

If you share your Flutter version (3.19–3.24 have slightly different runtime shader APIs), I can paste the exact Dart code to bind:

-   the `bgImage` child sampler,
    
-   the packed uniform arrays,
    
-   and the minimal per-tile draw loop.