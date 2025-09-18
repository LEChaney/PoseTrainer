import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

/// LinearBlendShader loads and runs a fragment program that composites
/// white-alpha soft-disc dabs in linear space over an existing tile image.
///
/// Dab data is passed as a 1D RGBA texture (width=N*2, height=1), using
/// two texels per dab in pixel space:
/// - Texel0: [cx_lo, cx_hi, cy_lo, cy_hi] where center x/y are 16-bit signed
///   pixel coordinates with a +32768 bias to allow off-tile centers.
/// - Texel1: [radius_lo, radius_hi, alphaByte, 0]. Radius is 16-bit unsigned
///   pixels, alphaByte is 0..255. The shader computes soft-disc coverage and
///   blends in linear space with SrcOver.
class LinearBlendShader {
  final ui.FragmentProgram program;
  final ui.FragmentShader shader;
  static const int _maxDabsPerPass = 512; // Must match shader MAX_DABS

  LinearBlendShader._(this.program, this.shader);

  static Future<LinearBlendShader> load() async {
    final prog = await ui.FragmentProgram.fromAsset(
      'shaders/linear_dab_blend.frag',
    );
    final sh = prog.fragmentShader();
    return LinearBlendShader._(prog, sh);
  }

  /// Builds a 1D image for dab payloads using two texels per dab (adaptive fixed-point):
  /// - Centers are stored relative to the tile center with a per-dab shift `s`
  ///   (0..15) giving scale = 2^s and value_px = (raw - 32768) / scale.
  ///   Higher `s` => more precision, less range. We pick the largest `s` that
  ///   still covers ±(tileSize/2 + radius).
  /// - Radius is stored as 16-bit unsigned integer pixels (no subpixel needed).
  /// Layout per dab:
  ///   Texel0: [cx_lo, cx_hi, cy_lo, cy_hi]
  ///   Texel1: [r_lo, r_hi, alphaByte, posShiftByte]
  /// Center and radius are in pixels relative to the tile's (0,0), allowed to be outside [0, tileSize].
  Future<ui.Image> makeDabBuffer(List<DabPayload> dabs, int tileSize) async {
    final n = dabs.length;
    final width = n == 0 ? 2 : n * 2; // two texels per dab
    final data = Uint8List(width * 4);
    const bias = 32768; // bias applied to signed centers
    int packFixed16UnsignedPx(double px) {
      final t = px.round();
      return t.clamp(0, 65535);
    }

    int packFixed16SignedWithShift(double pxRel, int shift) {
      final scale = 1 << shift; // integer scale
      final t = (pxRel * scale).round() + bias;
      return t.clamp(0, 65535);
    }

    for (int i = 0; i < n; i++) {
      final d = dabs[i];
      // Center relative to tile center to minimize required range.
      final half = tileSize * 0.5;
      final relX = d.center.dx - half;
      final relY = d.center.dy - half;
      // Choose largest shift that still covers ±(tileSize/2 + radius).
      final required = half + d.radius;
      final maxRaw = 32767.0;
      int posShift = (math.log(maxRaw / required) / math.ln2).floor().clamp(
        0,
        15,
      );
      final cx = packFixed16SignedWithShift(relX, posShift);
      final cy = packFixed16SignedWithShift(relY, posShift);
      final rr = packFixed16UnsignedPx(d.radius);
      final aa = (d.alpha.clamp(0.0, 1.0) * 255 + 0.5).toInt();
      final base = i * 8; // 8 bytes per dab
      // Texel 0
      data[base + 0] = cx & 0xFF; // cx lo
      data[base + 1] = (cx >> 8) & 0xFF; // cx hi
      data[base + 2] = cy & 0xFF; // cy lo
      data[base + 3] = (cy >> 8) & 0xFF; // cy hi
      // Texel 1
      data[base + 4] = rr & 0xFF; // r lo
      data[base + 5] = (rr >> 8) & 0xFF; // r hi
      data[base + 6] = aa; // alpha
      data[base + 7] = posShift; // per-dab position shift (scale=2^shift)

      // Packed two texels per dab; no logging in production.
    }
    final buf = await ui.ImmutableBuffer.fromUint8List(data);
    final desc = ui.ImageDescriptor.raw(
      buf,
      width: width,
      height: 1,
      pixelFormat: ui.PixelFormat.rgba8888,
      rowBytes: width * 4,
    );
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Composite dabs onto existing tile (if null -> transparent) and return new tile.
  Future<ui.Image> blendOntoTile({
    required ui.Image? existing,
    required List<DabPayload> dabs,
    required int tileSize,
    required ui.Color brushColor,
    double hardness = 1.0,
  }) async {
    // Use a fresh FragmentShader per call to avoid concurrent races
    // when tiles are rasterized in parallel.
    final sh = program.fragmentShader();
    // We may need multiple passes if dabs exceed shader MAX_DABS.
    ui.Image acc = existing ?? await _transparentTile(tileSize);
    int offset = 0;
    // Intentionally no logging in release builds
    while (offset < dabs.length) {
      final end = (offset + _maxDabsPerPass).clamp(0, dabs.length);
      final chunk = dabs.sublist(offset, end);

      final recorder = ui.PictureRecorder();
      final rect = ui.Rect.fromLTWH(
        0,
        0,
        tileSize.toDouble(),
        tileSize.toDouble(),
      );
      final c = ui.Canvas(recorder, rect);

      // Bind uniforms for this chunk
      sh.setImageSampler(0, acc);
      final dabImg = await makeDabBuffer(chunk, tileSize);
      sh.setImageSampler(1, dabImg);
      sh.setFloat(0, chunk.length.toDouble());
      sh.setFloat(1, tileSize.toDouble());
      sh.setFloat(2, hardness.toDouble());
      sh.setFloat(3, brushColor.r);
      sh.setFloat(4, brushColor.g);
      sh.setFloat(5, brushColor.b);

      final paint = ui.Paint()..shader = sh;
      c.drawRect(rect, paint);
      final pic = recorder.endRecording();
      final nextImg = await pic.toImage(tileSize, tileSize);
      dabImg.dispose();
      if (acc != existing) acc.dispose();
      acc = nextImg;

      offset = end;
    }

    return acc;
  }

  Future<ui.Image> _transparentTile(int tileSize) async {
    final recorder = ui.PictureRecorder();
    final rect = ui.Rect.fromLTWH(
      0,
      0,
      tileSize.toDouble(),
      tileSize.toDouble(),
    );
    final _ = ui.Canvas(recorder, rect);
    // Nothing drawn -> fully transparent
    final pic = recorder.endRecording();
    return pic.toImage(tileSize, tileSize);
  }
}

/// Public dab payload for the shader blender. Coordinates must be tile-local.
class DabPayload {
  final ui.Offset center; // tile-local center in pixels (0..tileSize)
  final double radius; // radius in pixels
  final double alpha; // 0..1 flow
  DabPayload(this.center, this.radius, this.alpha);
}
