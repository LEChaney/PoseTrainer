import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' as vm;

class LinearBlendUniformShader {
  final ui.FragmentProgram program;
  static const int maxDabsPerPass = 64; // Must match shader MAX_DABS

  LinearBlendUniformShader._(this.program);

  static Future<LinearBlendUniformShader> load() async {
    final prog = await ui.FragmentProgram.fromAsset(
      'shaders/linear_dab_blend_uniform.frag',
    );
    return LinearBlendUniformShader._(prog);
  }

  Future<ui.Image> blendOntoTile({
    required ui.Image? existing,
    required List<DabUniform> dabs,
    required int tileSize,
    required ui.Color brushColor,
    double hardness = 1.0,
  }) async {
    ui.Image acc = existing ?? await _transparentTile(tileSize);
    int offset = 0;
    print('Blending ${dabs.length} dabs onto tile with color $brushColor');
    // Convert brush color from sRGB (0..1 per channel) to linear (0..1 per channel)
    // using the same logic as the shader.
    vm.Vector3 srgbToLinear(vm.Vector3 c) {
      double conv(double v) {
        // v is in 0..1
        if (v <= 0.04045) return v / 12.92;
        return math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      }

      return vm.Vector3(conv(c.x), conv(c.y), conv(c.z));
    }

    final brushColorLin = srgbToLinear(
      vm.Vector3(brushColor.r, brushColor.g, brushColor.b),
    );

    while (offset < dabs.length) {
      final end = (offset + maxDabsPerPass).clamp(0, dabs.length);
      final chunk = dabs.sublist(offset, end);

      final sh = program.fragmentShader();
      sh.setImageSampler(0, acc);
      sh.setFloat(0, chunk.length.toDouble());
      sh.setFloat(1, tileSize.toDouble());
      sh.setFloat(2, hardness.toDouble());
      // Pass linear 0..1 RGB to match shader's expected range
      sh.setFloat(3, brushColorLin.r);
      sh.setFloat(4, brushColorLin.g);
      sh.setFloat(5, brushColorLin.b);

      // dabs0[64] occupies 64*4 = 256 floats; we'll fill only count*4
      // RuntimeEffect uniforms are sequential; following the above 6 floats
      // we push 256 floats (cx,cy,r,alpha) for all 64 entries.
      int base = 6;
      for (int i = 0; i < maxDabsPerPass; i++) {
        final v = (i < chunk.length) ? chunk[i] : const DabUniform(0, 0, 0, 0);
        sh.setFloat(base + i * 4 + 0, v.cx);
        sh.setFloat(base + i * 4 + 1, v.cy);
        sh.setFloat(base + i * 4 + 2, v.r);
        sh.setFloat(base + i * 4 + 3, v.a);
      }

      final recorder = ui.PictureRecorder();
      final rect = ui.Rect.fromLTWH(
        0,
        0,
        tileSize.toDouble(),
        tileSize.toDouble(),
      );
      final c = ui.Canvas(recorder, rect);
      final paint = ui.Paint()
        ..shader = sh
        ..blendMode = ui.BlendMode.src;
      c.drawRect(rect, paint);
      final pic = recorder.endRecording();
      final nextImg = await pic.toImage(tileSize, tileSize);
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
    final pic = recorder.endRecording();
    return pic.toImage(tileSize, tileSize);
  }
}

class DabUniform {
  final double cx, cy, r, a;
  const DabUniform(this.cx, this.cy, this.r, this.a);
}
