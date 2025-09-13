import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Brush Engine (single soft round brush)
// ---------------------------------------------------------------------------
// Converts raw pointer input into a visually smooth stroke by:
// 1. Capturing pointer samples as InputPoint (x, y, pressure, timestamp).
// 2. Smoothing x, y, and pressure separately with the One-Euro filter.
// 3. Emitting evenly spaced "dabs" (small stamped sprites) along the path.
// 4. Batching all dabs for the in‑progress stroke with drawAtlas for speed.
// 5. Compositing (merging) dabs into a base image when the stroke completes.
// Keeping this minimal helps maintain responsiveness and clarity.

class BrushParams {
  final double sizePx; // Base brush diameter in logical pixels
  final double spacing; // Dab spacing relative to diameter (smaller => denser)
  final double flow; // Base ink per dab (0..1)
  final double hardness; // Edge softness (1 = harder edge)
  final double opacity; // Overall stroke opacity multiplier
  final double pressureSize; // How strongly pressure changes size
  final double pressureFlow; // How strongly pressure changes flow
  const BrushParams({
    this.sizePx = 18,
    this.spacing = 0.12,
    this.flow = 0.7,
    this.hardness = 0.8,
    this.opacity = 1.0,
    this.pressureSize = 0.9,
    this.pressureFlow = 0.7,
  });
}

class InputPoint {
  final double x, y, pressure; // Normalized pressure 0..1
  final int tMs; // Millisecond timestamp used to estimate frequency
  const InputPoint(this.x, this.y, this.pressure, this.tMs);
}

class OneEuro {
  // Adaptive low‑pass filter balancing noise removal & responsiveness.
  double freq = 120; // Estimated update frequency (Hz)
  double minCutoff = 1.0; // Base smoothing
  double beta = 0.015; // Speed coefficient (higher -> less smoothing when fast)
  double dCutoff = 1.0; // Derivative cutoff
  _LowPass _x = _LowPass();
  _LowPass _dx = _LowPass();
  int? _lastMs;

  double filter(double value, int tMs) {
    if (_lastMs != null) {
      final dt = (tMs - _lastMs!).clamp(1, 1000);
      freq = 1000.0 / dt; // Update frequency based on sample spacing
    }
    _lastMs = tMs;
    final ed = _dx.filter((value - _x.last) * freq, _alpha(dCutoff));
    final cutoff = minCutoff + beta * ed.abs();
    return _x.filter(value, _alpha(cutoff));
  }

  double _alpha(double cutoff) {
    final te = 1.0 / freq.clamp(1e-3, 1e9);
    final tau = 1.0 / (2 * math.pi * cutoff.clamp(1e-3, 1e9));
    return 1.0 / (1.0 + tau / te);
  }

  void reset() {
    _lastMs = null;
    _x = _LowPass();
    _dx = _LowPass();
  }
}

class _LowPass {
  double _y = 0; // Last filtered value
  bool _init = false;
  double get last => _y;
  double filter(double x, double a) {
    if (!_init) {
      _y = x; // Prime filter with first sample
      _init = true;
    }
    _y = _y + a.clamp(0, 1) * (x - _y);
    return _y;
  }
}

class Dab {
  final ui.Offset center; // Center position of the stamp
  final double radius; // Radius in pixels
  final double alpha; // Final dab opacity (0..1)
  const Dab(this.center, this.radius, this.alpha);
}

class StrokeLayer {
  // Parallel lists used by drawAtlas for batching many quads in one call.
  final List<ui.RSTransform> _xforms = [];
  final List<ui.Rect> _src = [];
  final List<ui.Color> _colors = [];
  ui.Image? sprite; // Soft round brush sprite (generated lazily)

  Future<void> ensureSprite(double hardness) async {
    if (sprite != null) return;
    sprite = await _makeSoftDiscSprite(128, hardness);
  }

  void clear() {
    _xforms.clear();
    _src.clear();
    _colors.clear();
  }

  void add(Dab d) {
    final src = ui.Rect.fromLTWH(0, 0, 128, 128);
    final scale =
        (d.radius / 64.0) * 2.0; // Convert radius back to sprite scale
    final xf = ui.RSTransform.fromComponents(
      rotation: 0,
      scale: scale,
      anchorX: 64,
      anchorY: 64,
      translateX: d.center.dx,
      translateY: d.center.dy,
    );
    _xforms.add(xf);
    _src.add(src);
    _colors.add(ui.Color.fromARGB((d.alpha * 255).round(), 255, 255, 255));
  }

  void draw(ui.Canvas c) {
    if (sprite == null) return;
    c.drawAtlas(
      sprite!,
      _xforms,
      _src,
      _colors,
      ui.BlendMode.srcOver,
      null,
      ui.Paint()..filterQuality = ui.FilterQuality.low,
    );
  }
}

class BrushEngine extends ChangeNotifier {
  final BrushParams params;
  final StrokeLayer live = StrokeLayer(); // Holds dabs for active stroke
  final OneEuro _fx = OneEuro(); // X smoothing
  final OneEuro _fy = OneEuro(); // Y smoothing
  final OneEuro _fp = OneEuro()
    ..beta = 0.02; // Pressure smoothing (slightly faster)
  double? _lastX, _lastY; // Last dab center to enforce spacing

  BrushEngine(this.params);

  Future<void> prepare() => live.ensureSprite(params.hardness);

  // Reset state at stroke start.
  void resetStroke() {
    _fx.reset();
    _fy.reset();
    _fp.reset();
    _lastX = null;
    _lastY = null;
    live.clear();
  }

  // Convert filtered points to dabs with consistent spacing.
  Iterable<Dab> _emit(Iterable<InputPoint> raw) sync* {
    for (final p in raw) {
      final sx = _fx.filter(p.x, p.tMs);
      final sy = _fy.filter(p.y, p.tMs);
      final sp = _fp.filter(p.pressure.clamp(0, 1), p.tMs).clamp(0, 1);
      final diameter =
          params.sizePx * (1 + params.pressureSize * (sp - 0.5) * 2);
      final spacingPx = (params.spacing.clamp(0.01, 1.0)) * diameter;
      final flow = (params.flow + params.pressureFlow * (sp - 0.5) * 2).clamp(
        0,
        1,
      );
      final shouldEmit = () {
        if (_lastX == null) return true; // Always emit first dab
        final dx = sx - _lastX!, dy = sy - _lastY!;
        return (dx * dx + dy * dy) >= spacingPx * spacingPx;
      }();
      if (shouldEmit) {
        _lastX = sx;
        _lastY = sy;
        yield Dab(ui.Offset(sx, sy), diameter * 0.5, flow * params.opacity);
      }
    }
  }

  // Add new raw points (e.g., from pointer events). Notifies listeners so the
  // CustomPainter can repaint the live stroke.
  void addPoints(List<InputPoint> pts) {
    for (final d in _emit(pts)) {
      live.add(d);
    }
    if (pts.isNotEmpty) notifyListeners();
  }
}

Future<ui.Image> _makeSoftDiscSprite(int size, double hardness) async {
  // Prebuild a radial gradient disc once; reused for all dabs.
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(
    rec,
    ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
  );
  final center = ui.Offset(size / 2, size / 2);
  final r = size / 2.0;
  final stops = [0.0, (hardness.clamp(0.0, 1.0) * 0.85), 1.0];
  final colors = [
    ui.Color(0xFFFFFFFF),
    ui.Color(0xFFFFFFFF),
    ui.Color(0x00FFFFFF),
  ];
  final shader = ui.Gradient.radial(
    center,
    r,
    colors,
    stops,
    ui.TileMode.clamp,
  );
  final p = ui.Paint()..shader = shader;
  c.drawCircle(center, r, p);
  final pic = rec.endRecording();
  return pic.toImage(size, size);
}
