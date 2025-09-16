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

  // Force filter state to this value immediately (used on sharp corners)
  void jumpTo(double value) {
    _x.prime(value);
    _dx.prime(0);
    // Consider warmup satisfied so subsequent samples proceed normally.
    _samples = warmupSamples;
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

/// Alternate position smoothing that attempts to reduce corner wobble by
/// (1) predicting next position via linear extrapolation, (2) using a
/// direction-change deadband, and (3) blending prediction and raw based on
/// instantaneous curvature + speed. Designed to be extremely low latency
/// for decisive direction changes while still calming micro jitter.
class PredictiveAxisSmoother {
  double _lastX = 0;
  double _vx = 0; // velocity (units/ms)
  bool _init = false;
  int _lastMs = 0;

  // Tunables
  double jitterSpeedThreshold =
      0.002; // below this speed treat as potential jitter
  double deadbandAngleCos =
      0.9848; // ~10 degrees: dot > cos => similar direction
  double velocityBlend = 0.18; // low-pass on velocity
  double predictionHorizonMs = 10; // how far ahead to extrapolate
  double turnBoost = 0.65; // more weight to raw when turning sharply

  void reset() {
    _init = false;
    _vx = 0;
  }

  double filter(double x, int tMs) {
    if (!_init) {
      _lastX = x;
      _lastMs = tMs;
      _init = true;
      return x;
    }
    final dtMs = (tMs - _lastMs).clamp(1, 32); // cap large gaps
    final dt = dtMs.toDouble();
    final vxRaw = (x - _lastX) / dt; // units per ms

    // Blend velocity for stability unless direction changes sharply.
    var vx = _vx + (vxRaw - _vx) * velocityBlend;

    // Direction change detection: compare sign of velocities.
    if ((_vx > 0 && vxRaw < 0) || (_vx < 0 && vxRaw > 0)) {
      // Rapid reversal: trust raw immediately (defeat lag at sharp corners)
      vx = vxRaw;
    }

    // Very low speed region: treat as jitter; pull toward previous.
    if (vxRaw.abs() < jitterSpeedThreshold) {
      vx *= 0.25; // heavily damp
    }

    _vx = vx;
    _lastMs = tMs;

    // Predict next position slightly ahead.
    final pred = x + vx * predictionHorizonMs;

    // Blend: if velocity is small or reversing, lean more raw; else slightly toward prediction.
    double speed = vx.abs();
    double k = (speed / (jitterSpeedThreshold * 8)).clamp(0, 1); // scale 0..1
    k = math.pow(k, 0.7).toDouble();
    double blended = x * (1 - 0.25 * k) + pred * (0.25 * k);

    // Turn boost: if raw delta opposes stored velocity strongly, bias to raw.
    if (vxRaw.sign != _vx.sign && vxRaw.abs() > jitterSpeedThreshold * 2) {
      blended = x * (1 - turnBoost) + blended * turnBoost;
    }

    _lastX = x;
    return blended;
  }
}

enum SmoothingMode { none, oneEuro, predictive }

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
  final PredictiveAxisSmoother _px = PredictiveAxisSmoother();
  final PredictiveAxisSmoother _py = PredictiveAxisSmoother();
  SmoothingMode positionMode = SmoothingMode.predictive;
  double? _lastX, _lastY; // Last dab center to enforce spacing
  // Corner detection raw history (unsmoothed)
  InputPoint? _rawPrev1; // most recent previous
  InputPoint? _rawPrev2; // older
  // (Legacy explicit corner snap parameters removed; adaptive curvature blending now handles wobble.)
  // Curvature adaptive smoothing parameters
  double curvatureMin =
      0.15; // below this curvature (radians) -> full smoothing
  double curvatureMax =
      0.65; // above this curvature -> raw position (no smoothing)
  double curvatureBlendExp = 1.6; // shaping for blend curve

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
    _px.reset();
    _py.reset();
    _lastX = null;
    _lastY = null;
    _rawPrev1 = null;
    _rawPrev2 = null;
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
      // Estimate local curvature using last two raw points (if present).
      double blend = 1.0; // 1 => use filtered, 0 => use raw
      if (_rawPrev1 != null && _rawPrev2 != null) {
        final p1 = _rawPrev2!; // older
        final p2 = _rawPrev1!; // previous
        final v1x = p2.x - p1.x;
        final v1y = p2.y - p1.y;
        final v2x = p.x - p2.x;
        final v2y = p.y - p2.y;
        final len1 = math.sqrt(v1x * v1x + v1y * v1y);
        final len2 = math.sqrt(v2x * v2x + v2y * v2y);
        if (len1 > 0.0001 && len2 > 0.0001) {
          var dot = (v1x * v2x + v1y * v2y) / (len1 * len2);
          if (dot < -1)
            dot = -1;
          else if (dot > 1)
            dot = 1;
          final angle = math.acos(dot); // 0 straight
          // Map angle to blend: low angle => 1 (filtered), high angle => 0 (raw)
          if (angle <= curvatureMin) {
            blend = 1.0;
          } else if (angle >= curvatureMax) {
            blend = 0.0;
          } else {
            final t = (angle - curvatureMin) / (curvatureMax - curvatureMin);
            // Invert so t=0 => angle=curvatureMin => filtered
            blend = math.pow(1 - t, curvatureBlendExp).toDouble();
          }
        }
      }

      // Always advance filters so state continuity maintained.
      double fx, fy;
      switch (positionMode) {
        case SmoothingMode.none:
          fx = p.x;
          fy = p.y;
          break;
        case SmoothingMode.oneEuro:
          fx = _fx.filter(p.x, p.tMs);
          fy = _fy.filter(p.y, p.tMs);
          break;
        case SmoothingMode.predictive:
          fx = _px.filter(p.x, p.tMs);
          fy = _py.filter(p.y, p.tMs);
          break;
      }
      final sx = fx * blend + p.x * (1 - blend);
      final sy = fy * blend + p.y * (1 - blend);
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
    // Maintain raw history for curvature estimation.
    for (final p in pts) {
      _rawPrev2 = _rawPrev1;
      _rawPrev1 = p;
    }
    for (final d in _emit(pts)) {
      live.add(d);
    }
    if (pts.isNotEmpty) notifyListeners();
  }

  // _maybeHandleCorner removed: curvature-based blending supplants explicit snapping.

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

  void setPositionSmoothingMode(SmoothingMode mode) {
    if (positionMode == mode) return;
    positionMode = mode;
    // Reset stroke state so switching is immediate and artifact free.
    _lastX = null;
    _lastY = null;
    _fx.reset();
    _fy.reset();
    _px.reset();
    _py.reset();
    notifyListeners();
  }
}

// NOTE: Sprite generation removed in analytic circle version. Keeping a stub
// (commented out) here for potential future reinstatement of atlas path.
// Future<ui.Image> _makeSoftDiscSprite(int size, double hardness) async { ... }
