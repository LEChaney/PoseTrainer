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
    this.spacing = 0.18, // relaxed for analytic circles (less overdraw)
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
  final ui.Offset center;
  final double radius;
  final double alpha;
  const Dab(this.center, this.radius, this.alpha);
}

class StrokeLayer {
  // Analytic rendering version (no sprite). Each dab is drawn as a circle.
  // WHY: The sprite-based approach showed a visible square even for a single
  // dab due to the wide gradient tail + texture minification sampling faint
  // non-zero alpha out to the corners. For simplicity and correctness we draw
  // circles directly; a lightweight blur provides soft edges.
  final List<Dab> _dabs = [];
  double _hardness = 0.8; // 0 = very soft (wide halo), 1 = hard (thin halo)

  Future<void> ensureSprite(double hardness) async {
    // Retained for interface compatibility; no sprite needed now.
    _hardness = hardness.clamp(0, 1);
  }

  void clear() => _dabs.clear();

  void add(Dab d) => _dabs.add(d);

  void draw(ui.Canvas c) {
    // Two-phase analytic dab: soft halo (optional) + bright core.
    // Goal: brighter center, harder visual edge while retaining adjustable softness.
    // Hardness mapping: 0 -> large soft halo; 1 -> almost no halo.
    final haloPaint = ui.Paint()..isAntiAlias = true;
    final corePaint = ui.Paint()..isAntiAlias = true;
    for (final d in _dabs) {
      final a = (d.alpha * 255).clamp(0, 255).round();
      final hardness = _hardness;
      final coreRatio = ui.lerpDouble(
        0.45,
        0.8,
        hardness,
      )!; // bigger core when harder
      final coreR = d.radius * coreRatio;
      final haloR = d.radius;
      final haloAlpha =
          (1 - hardness) * 0.55; // fade halo as hardness increases
      if (haloAlpha > 0.01) {
        final sigma =
            (haloR - coreR).clamp(0.0, d.radius) * 0.9; // soften outer falloff
        haloPaint
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma)
          ..color = ui.Color.fromARGB((a * haloAlpha).round(), 255, 255, 255);
        c.drawCircle(d.center, coreR + (haloR - coreR) * 0.5, haloPaint);
      }
      // Core: full brightness (alpha) with sharp(er) edge (AA only)
      corePaint
        ..maskFilter = null
        ..color = ui.Color.fromARGB(a, 255, 255, 255);
      c.drawCircle(d.center, coreR, corePaint);
    }
  }
}

class BrushEngine extends ChangeNotifier {
  // Analytic circle brush implementation (no texture atlas). Reasoning:
  // Earlier sprite approach produced a faint square even for a single dab
  // because the radial gradient's low-alpha tail + downscaling caused the
  // texture corners to contribute visible grey. Drawing circles directly with
  // an adjustable blur yields a perfectly round stamp at any size and avoids
  // sampling artifacts. This is simpler for the beginner phase; we can re-add
  // a sprite path later for exotic shapes or performance profiling if needed.
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

  // Convert filtered points to dabs with consistent spacing. Interpolate
  // intermediate dabs when distance > spacing to avoid gaps.
  Iterable<Dab> _emit(Iterable<InputPoint> raw) sync* {
    for (final p in raw) {
      final sx = _fx.filter(p.x, p.tMs);
      final sy = _fy.filter(p.y, p.tMs);
      final sp = _fp.filter(p.pressure.clamp(0, 1), p.tMs).clamp(0, 1);
      final diameter =
          params.sizePx * (1 + params.pressureSize * (sp - 0.5) * 2);
      final spacingPx = (params.spacing.clamp(0.05, 1.0)) * diameter;
      final flow = (params.flow + params.pressureFlow * (sp - 0.5) * 2).clamp(
        0,
        1,
      );

      // First dab: always emit at filtered position.
      if (_lastX == null) {
        _lastX = sx;
        _lastY = sy;
        yield Dab(ui.Offset(sx, sy), diameter * 0.5, flow * params.opacity);
        continue;
      }

      var dx = sx - _lastX!;
      var dy = sy - _lastY!;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < spacingPx) {
        // Not far enough to place next dab yet.
        continue;
      }

      // Normalize direction for interpolation.
      final dirX = dx / dist;
      final dirY = dy / dist;
      var traveled = spacingPx;
      while (traveled <= dist) {
        final ix = _lastX! + dirX * traveled;
        final iy = _lastY! + dirY * traveled;
        yield Dab(ui.Offset(ix, iy), diameter * 0.5, flow * params.opacity);
        traveled += spacingPx;
      }
      // Update last emitted dab center to final point so future distance calc
      // uses the newest position even if we skipped a residual fraction.
      _lastX = sx;
      _lastY = sy;
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

// NOTE: Sprite generation removed in analytic circle version. Keeping a stub
// (commented out) here for potential future reinstatement of atlas path.
// Future<ui.Image> _makeSoftDiscSprite(int size, double hardness) async { ... }
