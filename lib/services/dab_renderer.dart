import 'dart:ui' as ui;

/// Computes the fraction of the dab radius that should be fully opaque
/// based on hardness. 0 => small opaque core (long feather), 1 => large core.
double coreRatioFromHardness(double hardness) {
  final h = hardness.clamp(0.0, 1.0);
  return ui.lerpDouble(0.35, 0.9, h)!.clamp(0.0, 1.0);
}

/// Draws a single circular dab using a radial gradient:
/// - center is fully opaque up to `coreRatio * radius`
/// - linearly fades to transparent at `radius`
void drawFeatheredDab(
  ui.Canvas canvas,
  ui.Offset center,
  double radius,
  ui.Color centerColor,
  double coreRatio,
) {
  final stops = <double>[0.0, coreRatio.clamp(0.0, 1.0), 1.0];
  final colors = <ui.Color>[
    centerColor,
    centerColor,
    const ui.Color.fromARGB(0, 255, 255, 255),
  ];
  final paint = ui.Paint()
    ..isAntiAlias = true
    ..shader = ui.Gradient.radial(
      center,
      radius,
      colors,
      stops,
      ui.TileMode.clamp,
    );
  canvas.drawCircle(center, radius, paint);
}

/// Convenience: draw a dab when you have alpha (0..1) and hardness (0..1).
/// This computes the center color and core ratio then delegates to
/// `drawFeatheredDab` so callers don't repeat that logic.
void drawDabWithAlphaAndHardness(
  ui.Canvas canvas,
  ui.Offset center,
  double radius,
  double alpha, // 0..1
  double hardness, // 0..1
) {
  final a = (alpha * 255).clamp(0, 255).round();
  final centerColor = ui.Color.fromARGB(a, 255, 255, 255);
  final core = coreRatioFromHardness(hardness);
  drawFeatheredDab(canvas, center, radius, centerColor, core);
}

/// Convenience: draw a dab when caller already has a precomputed color and
/// core ratio. This simply forwards to `drawFeatheredDab` to keep names
/// consistent across call sites.
void drawDabWithColorAndCore(
  ui.Canvas canvas,
  ui.Offset center,
  double radius,
  ui.Color centerColor,
  double coreRatio,
) {
  drawFeatheredDab(canvas, center, radius, centerColor, coreRatio);
}
