import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'tiled_surface.dart';

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
  // Loose Sketch Brush (SAI-like) Parameter Design:
  // - Early size growth (sizeGamma 0.6) so light pressure already yields a
  //   readable line width, enabling quick gesture marks without pressing hard.
  // - Min size 5% for tapered starts/ends (keeps strokes lively).
  // - Flow reaches target before full pressure (maxFlowPressure 0.85) so mid
  //   pressure feels nearly opaque; high pressure adds only subtle weight.
  // - minFlow small but non-zero to avoid completely invisible feathering.
  // - Low hardness => slight halo softening; will tighten for lineart brush.
  // Core size / spacing
  final double sizePx; // Base brush diameter at high pressure
  final double spacing; // Dab spacing as fraction of diameter

  // Opacity (flow) modeling
  final double flow; // Target (max) per-dab flow at/after maxFlowPressure
  final double minFlow; // Flow at zero pressure (sketch taper transparency)
  final double
  maxFlowPressure; // Pressure level where "flow" reaches target ( <1 => earlier saturation )

  // Size taper modeling
  final double minSizePct; // Diameter fraction at zero pressure (0.05 => 5%)
  final double sizeGamma; // <1 => faster early growth (SAI-like)
  final double flowGamma; // Flow response curve shaping

  // Edge softness
  final double hardness; // 0 soft halo, 1 hard edge

  // Global multiplier
  final double opacity; // Overall stroke opacity cap
  // Stroke color (currently single monochrome brush). Alpha is modulated per dab.
  final ui.Color color;

  const BrushParams({
    // Loose construction sketch defaults (SAI-like)
    this.sizePx = 10,
    this.spacing = 0.18,
    this.flow = 0.65,
    this.minFlow = 0.05,
    this.maxFlowPressure = 0.85,
    this.minSizePct = 0.05,
    this.sizeGamma = 0.6,
    this.flowGamma = 1.0,
    this.hardness = 0.2,
    this.opacity = 1.0,
    this.color = const ui.Color(0xFF111115),
  });

  BrushParams copyWith({
    double? sizePx,
    double? spacing,
    double? flow,
    double? minFlow,
    double? maxFlowPressure,
    double? minSizePct,
    double? sizeGamma,
    double? flowGamma,
    double? hardness,
    double? opacity,
    ui.Color? color,
  }) {
    return BrushParams(
      sizePx: sizePx ?? this.sizePx,
      spacing: spacing ?? this.spacing,
      flow: flow ?? this.flow,
      minFlow: minFlow ?? this.minFlow,
      maxFlowPressure: maxFlowPressure ?? this.maxFlowPressure,
      minSizePct: minSizePct ?? this.minSizePct,
      sizeGamma: sizeGamma ?? this.sizeGamma,
      flowGamma: flowGamma ?? this.flowGamma,
      hardness: hardness ?? this.hardness,
      opacity: opacity ?? this.opacity,
      color: color ?? this.color,
    );
  }
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
  int _samples = 0; // Count of processed samples for warmup
  int warmupSamples =
      2; // Emit first N samples unsmoothed to avoid initial kink
  double maxDerivative = 4000; // Clamp derivative magnitude to suppress spikes

  double filter(double value, int tMs) {
    if (_lastMs != null) {
      final dt = (tMs - _lastMs!).clamp(1, 1000);
      freq = 1000.0 / dt; // Update frequency based on sample spacing
    }
    _lastMs = tMs;
    // Warmup: output raw value for first few samples (primes filters)
    if (_samples < warmupSamples) {
      _samples++;
      _x.prime(value); // Prime position filter
      _dx.prime(0); // Prime derivative filter
      return value;
    }
    var deriv = (value - _x.last) * freq;
    // Clamp derivative to avoid sudden huge beta amplification causing a kink
    if (deriv > maxDerivative) {
      deriv = maxDerivative;
    } else if (deriv < -maxDerivative) {
      deriv = -maxDerivative;
    }
    final ed = _dx.filter(deriv, _alpha(dCutoff));
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
    _samples = 0;
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

  void prime(double x) {
    _y = x;
    _init = true;
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

  void setHardness(double h) {
    _hardness = h.clamp(0, 1);
  }

  void clear() => _dabs.clear();

  void add(Dab d) => _dabs.add(d);

  void draw(ui.Canvas canvas) {
    // Two-phase analytic dab: soft halo (optional) + bright core.
    // Goal: brighter center, harder visual edge while retaining adjustable softness.
    // Hardness mapping: 0 -> large soft halo; 1 -> almost no halo.
    final haloPaint = ui.Paint()..isAntiAlias = true;
    final corePaint = ui.Paint()..isAntiAlias = true;
    for (final dab in _dabs) {
      final a = (dab.alpha * 255).clamp(0, 255).round();
      final hardness = _hardness;
      final coreRatio = ui.lerpDouble(
        0.45,
        0.8,
        hardness,
      )!; // bigger core when harder
      final coreR = dab.radius * coreRatio;
      final haloR = dab.radius;
      final haloAlpha =
          (1 - hardness) * 0.55; // fade halo as hardness increases
      if (haloAlpha > 0.01) {
        final sigma =
            (haloR - coreR).clamp(0.0, dab.radius) *
            0.9; // soften outer falloff
        final c = BrushEngine.currentColor;
        haloPaint
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma)
          ..color = ui.Color.fromARGB(
            (a * haloAlpha).round(),
            (c.r * 255).round().clamp(0, 255),
            (c.g * 255).round().clamp(0, 255),
            (c.b * 255).round().clamp(0, 255),
          );
        canvas.drawCircle(dab.center, coreR + (haloR - coreR) * 0.5, haloPaint);
      }
      // Core: full brightness (alpha) with sharp(er) edge (AA only)
      final c2 = BrushEngine.currentColor;
      corePaint
        ..maskFilter = null
        ..color = ui.Color.fromARGB(
          a,
          (c2.r * 255).round().clamp(0, 255),
          (c2.g * 255).round().clamp(0, 255),
          (c2.b * 255).round().clamp(0, 255),
        );
      canvas.drawCircle(dab.center, coreR, corePaint);
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
  final StrokeLayer live =
      StrokeLayer(); // Holds dabs for active stroke (tail only once tiled baking active)
  final TiledSurface tiles = TiledSurface(tileSize: 256);
  final OneEuro _fx = OneEuro(); // X smoothing
  final OneEuro _fy = OneEuro(); // Y smoothing
  final OneEuro _fp = OneEuro()
    ..beta = 0.02; // Pressure smoothing (slightly faster)
  double? _lastX, _lastY; // Last dab center to enforce spacing

  BrushEngine(this.params) {
    _strokeColorFallback = params.color;
  }

  // Current stroke color (shared with StrokeLayer draw). For now single global.
  static ui.Color _strokeColorFallback = const ui.Color(0xFF111115);
  static ui.Color get currentColor => _strokeColorFallback;
  void setColor(ui.Color c) {
    _strokeColorFallback = c;
    notifyListeners();
  }

  // Runtime multipliers (temporary before full preset UI). These *only*
  // scale size and flow curves; base param object stays immutable.
  double _runtimeSizeScale = 1.0; // 1.0 => use params.sizePx
  double _runtimeFlowScale = 1.0; // 1.0 => use computed flow as-is

  void setSizeScale(double v) {
    _runtimeSizeScale = v.clamp(0.1, 5.0);
    notifyListeners();
  }

  void setFlowScale(double v) {
    _runtimeFlowScale = v.clamp(0.1, 3.0);
    notifyListeners();
  }

  void setHardness(double v) {
    live.setHardness(v);
    notifyListeners();
  }

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

  /// Clear all stroke data (live + committed tiles) and notify listeners so
  /// the UI repaints immediately (used by Clear button).
  void clearAll() {
    resetStroke();
    tiles.clear();
    notifyListeners();
  }

  // Convert filtered points to dabs with consistent spacing. Interpolate
  // intermediate dabs when distance > spacing to avoid gaps.
  Iterable<Dab> _emit(Iterable<InputPoint> raw) sync* {
    for (final p in raw) {
      final sx = _fx.filter(p.x, p.tMs);
      final sy = _fy.filter(p.y, p.tMs);
      final sp = _fp.filter(p.pressure.clamp(0, 1), p.tMs).clamp(0, 1);
      // Size pressure curve (gamma <1 => aggressive early growth)
      final sizeCurve = math.pow(sp, params.sizeGamma).toDouble();
      final diameter =
          (params.sizePx * _runtimeSizeScale) *
          (params.minSizePct + (1 - params.minSizePct) * sizeCurve);
      final spacingPx = (params.spacing.clamp(0.05, 1.0)) * diameter;
      // Flow (density) curve: normalize pressure by maxFlowPressure then apply gamma
      final flowNorm = (sp / params.maxFlowPressure).clamp(0.0, 1.0);
      final flowCurve = math.pow(flowNorm, params.flowGamma).toDouble();
      final baseFlow =
          (params.minFlow + (params.flow - params.minFlow) * flowCurve).clamp(
            0.0,
            1.0,
          );
      final flow =
          (params.minFlow + (baseFlow - params.minFlow) * _runtimeFlowScale)
              .clamp(0.0, 1.0);

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

  /// Bake current live dabs into tiles and clear live list. Called once per frame
  /// after all new points have been added so cost stays evenly distributed.
  Future<void> bakeLiveToTiles() async {
    if (live._dabs.isEmpty) return;
    // Convert each dab into pending tile work.
    final strokeColor = BrushEngine.currentColor;
    // Pre-multiply color per dab alpha.
    for (final d in live._dabs) {
      final a = (d.alpha * 255).clamp(0, 255).round();
      if (a == 0) continue;
      final color = ui.Color.fromARGB(
        a,
        (strokeColor.r * 255).round().clamp(0, 255),
        (strokeColor.g * 255).round().clamp(0, 255),
        (strokeColor.b * 255).round().clamp(0, 255),
      );
      tiles.addDab(d.center, d.radius, color);
    }
    live.clear();
    // Flush asynchronously; caller may await if they need deterministic completion.
    await tiles.flush();
    notifyListeners();
  }

  /// Compose a full image (used when finishing session). Draws tiles then optional live tail.
  Future<ui.Image> renderFull(int width, int height) async {
    // Ensure any remaining live dabs baked first for consistency.
    await bakeLiveToTiles();
    return tiles.toImage(width, height);
  }

  void disposeResources() {
    tiles.dispose();
  }
}

// NOTE: Sprite generation removed in analytic circle version. Keeping a stub
// (commented out) here for potential future reinstatement of atlas path.
// Future<ui.Image> _makeSoftDiscSprite(int size, double hardness) async { ... }
