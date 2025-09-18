import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart'
    show Vector2; // Unified 2D math
import 'tiled_surface.dart';
import 'dab_renderer.dart';
import '../theme/colors.dart';
import 'debug_profiler.dart';

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
  final double maxSizePx; // Base brush diameter at high pressure
  final double spacing; // Dab spacing as fraction of diameter

  // Opacity (flow) modeling
  final double maxFlow; // Target (max) per-dab flow at/after maxFlowPressure
  final double minFlow; // Flow at zero pressure (sketch taper transparency)
  final double
  maxFlowPressure; // Pressure level where "flow" reaches target ( <1 => earlier saturation )

  // Size taper modeling
  final double minScale; // Diameter fraction at zero pressure (0.05 => 5%)
  final double sizeGamma; // <1 => faster early growth (SAI-like)
  final double flowGamma; // Flow response curve shaping

  // Edge softness
  final double hardness; // 0 soft halo, 1 hard edge

  // Global multiplier
  final double opacity; // Overall stroke opacity cap
  // Stroke color (currently single monochrome brush). Alpha is modulated per dab.
  final ui.Color color;

  // UI runtime defaults (for sliders)
  final double runtimeSizeScale; // 0.01..1.0
  final double runtimeFlowScale; // 0.01..1.0

  const BrushParams({
    // Loose construction sketch defaults (SAI-like)
    this.maxSizePx = 100,
    this.spacing = 0.01,
    this.maxFlow = 1.0,
    this.minFlow = 0.0,
    this.maxFlowPressure = 1.0,
    this.minScale = 1.0,
    this.sizeGamma = 1.0,
    this.flowGamma = 1.0,
    this.hardness = 1.0,
    this.opacity = 1.0,
    this.color = kBrushDarkDefault,
    this.runtimeSizeScale = 0.07,
    this.runtimeFlowScale = 0.06,
  });

  BrushParams copyWith({
    double? maxSizePx,
    double? spacing,
    double? flow,
    double? minFlow,
    double? maxFlowPressure,
    double? minScale,
    double? sizeGamma,
    double? flowGamma,
    double? hardness,
    double? opacity,
    ui.Color? color,
    double? runtimeSizeScale,
    double? runtimeFlowScale,
  }) {
    return BrushParams(
      maxSizePx: maxSizePx ?? this.maxSizePx,
      spacing: spacing ?? this.spacing,
      maxFlow: flow ?? this.maxFlow,
      minFlow: minFlow ?? this.minFlow,
      maxFlowPressure: maxFlowPressure ?? this.maxFlowPressure,
      minScale: minScale ?? this.minScale,
      sizeGamma: sizeGamma ?? this.sizeGamma,
      flowGamma: flowGamma ?? this.flowGamma,
      hardness: hardness ?? this.hardness,
      opacity: opacity ?? this.opacity,
      color: color ?? this.color,
      runtimeSizeScale: runtimeSizeScale ?? this.runtimeSizeScale,
      runtimeFlowScale: runtimeFlowScale ?? this.runtimeFlowScale,
    );
  }
}

class InputPoint {
  final double x, y, pressure; // Normalized pressure 0..1
  final int tMs; // Millisecond timestamp used to estimate frequency
  const InputPoint(this.x, this.y, this.pressure, this.tMs);

  /// Convenience vector view (allocation free for ephemeral calculations).
  Vector2 toV() => Vector2(x, y);
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

/// Abstract 2D position smoothing interface.
abstract class PositionSmoother {
  Vector2 filter(Vector2 v, int tMs);
  void reset();
}

/// Pass-through (no smoothing) implementation.
class PassthroughSmoother implements PositionSmoother {
  @override
  Vector2 filter(Vector2 v, int tMs) => v;
  @override
  void reset() {}
}

/// 2D One-Euro smoother built from two scalar filters (still cleaner than
/// scattering scalars in BrushEngine). Keeps public API vector-based.
class OneEuroSmoother2D implements PositionSmoother {
  final OneEuro _sx = OneEuro();
  final OneEuro _sy = OneEuro();
  @override
  Vector2 filter(Vector2 v, int tMs) =>
      Vector2(_sx.filter(v.x, tMs), _sy.filter(v.y, tMs));
  @override
  void reset() {
    _sx.reset();
    _sy.reset();
  }
}

/// Predictive 2D smoother; mirrors prior PredictiveAxisSmoother logic but
/// applies it per component while exposing vector API. Allows future coupling.
class PredictiveSmoother2D implements PositionSmoother {
  final PredictiveAxisSmoother _px = PredictiveAxisSmoother();
  final PredictiveAxisSmoother _py = PredictiveAxisSmoother();
  @override
  Vector2 filter(Vector2 v, int tMs) =>
      Vector2(_px.filter(v.x, tMs), _py.filter(v.y, tMs));
  @override
  void reset() {
    _px.reset();
    _py.reset();
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
    // Radial gradient dab with hardness-controlled core and feather.
    // hardness 0 => small core, long feather. hardness 1 => large core, short feather.
    final coreRatio = coreRatioFromHardness(_hardness);
    for (final dab in _dabs) {
      final a = (dab.alpha * 255).clamp(0, 255).round();
      final centerColor = ui.Color.fromARGB(a, 255, 255, 255);
      drawFeatheredDab(canvas, dab.center, dab.radius, centerColor, coreRatio);
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
  late final TiledSurface tiles;
  final OneEuro _fp = OneEuro()
    ..beta = 0.02; // Pressure smoothing (slightly faster)
  SmoothingMode positionMode = SmoothingMode.none;
  // Unified 2D position smoother (strategy selected by mode).
  PositionSmoother _posSmoother = PassthroughSmoother();
  Vector2? _lastDabPos; // Last dab center to enforce spacing (null => none yet)
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

  // Track current hardness like other runtime controls for consistent access.
  double _hardness;

  final DebugProfiler? profiler;

  BrushEngine(this.params, {this.profiler}) : _hardness = params.hardness {
    tiles = TiledSurface(tileSize: 256, profiler: profiler);
    _strokeColorFallback = params.color;
    // Initialize runtime scales from params so UI can change defaults centrally.
    _runtimeSizeScale = params.runtimeSizeScale;
    _runtimeFlowScale = params.runtimeFlowScale;
  }

  // Current stroke color (shared with StrokeLayer draw). For now single global.
  static ui.Color _strokeColorFallback = kBrushDarkDefault;
  static ui.Color get currentColor => _strokeColorFallback;
  void setColor(ui.Color c) {
    _strokeColorFallback = c;
    notifyListeners();
  }

  // Runtime multipliers (temporary before full preset UI). These *only*
  // scale size and flow curves; base param object stays immutable.
  double _runtimeSizeScale = 0.1; // 1.0 => use params.sizePx
  double _runtimeFlowScale = 0.08; // 1.0 => use computed flow as-is

  // Expose current runtime controls so UI can initialize from engine state.
  double get sizeScale => _runtimeSizeScale;
  double get flowScale => _runtimeFlowScale;
  double get hardness => _hardness;

  void setSizeScale(double v) {
    _runtimeSizeScale = v.clamp(0.01, 1.0);
    notifyListeners();
  }

  void setFlowScale(double v) {
    _runtimeFlowScale = v.clamp(0.01, 1.0);
    notifyListeners();
  }

  void setHardness(double v) {
    _hardness = v.clamp(0, 1);
    live.setHardness(_hardness);
    notifyListeners();
  }

  Future<void> prepare() => live.ensureSprite(_hardness);

  // Reset state at stroke start.
  void resetStroke() {
    _posSmoother.reset();
    _fp.reset();
    _lastDabPos = null;
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
      // --- Curvature-adaptive smoothing blend ---------------------------------
      double blend = 1.0; // 1 => rely on filtered movement, 0 => raw
      if (_rawPrev1 != null && _rawPrev2 != null) {
        final v1 = Vector2(
          _rawPrev1!.x - _rawPrev2!.x,
          _rawPrev1!.y - _rawPrev2!.y,
        );
        final v2 = Vector2(p.x - _rawPrev1!.x, p.y - _rawPrev1!.y);
        final len1 = v1.length;
        final len2 = v2.length;
        if (len1 > 0.0001 && len2 > 0.0001) {
          final dot = (v1.dot(v2) / (len1 * len2)).clamp(-1.0, 1.0);
          final angle = math.acos(dot); // radians
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

      // --- Position smoothing (choose strategy then blend with raw) ---------
      final rawV = p.toV();
      // Choose smoothing strategy via current _posSmoother; blend curvature adaptively.
      final smoothed = _posSmoother.filter(rawV, p.tMs);
      final filtered = smoothed * blend + rawV * (1 - blend);

      // --- Pressure to size / flow curves -----------------------------------
      final sp = _fp.filter(p.pressure.clamp(0, 1), p.tMs).clamp(0, 1);
      // Size pressure curve (gamma <1 => aggressive early growth)
      final sizeCurve = math.pow(sp, params.sizeGamma).toDouble();
      final diameter =
          (params.maxSizePx * _runtimeSizeScale) *
          (params.minScale + (1 - params.minScale) * sizeCurve);
      final spacingPx = (params.spacing.clamp(0.05, 1.0)) * diameter;
      // Flow (density) curve: normalize pressure by maxFlowPressure then apply gamma
      final flowNorm = (sp / params.maxFlowPressure).clamp(0.0, 1.0);
      final flowCurve = math.pow(flowNorm, params.flowGamma).toDouble();
      final baseFlow =
          (params.minFlow + (params.maxFlow - params.minFlow) * flowCurve)
              .clamp(0.0, 1.0);
      final flow =
          (params.minFlow + (baseFlow - params.minFlow) * _runtimeFlowScale)
              .clamp(0.0, 1.0);

      // --- Emit first dab immediately ---------------------------------------
      if (_lastDabPos == null) {
        _lastDabPos = filtered.clone();
        yield Dab(
          ui.Offset(filtered.x, filtered.y),
          diameter * 0.5,
          flow * params.opacity,
        );
        continue;
      }

      // --- Distance & interpolation via Vector2 -----------------------------
      final lastPos = _lastDabPos!;
      final delta = filtered - lastPos;
      final dist = delta.length;
      if (dist < spacingPx) {
        continue; // not far enough yet
      }
      final dir = delta / dist; // normalized
      var traveled = spacingPx;
      while (traveled <= dist) {
        final pos = lastPos + dir * traveled;
        yield Dab(
          ui.Offset(pos.x, pos.y),
          diameter * 0.5,
          flow * params.opacity,
        );
        traveled += spacingPx;
      }
      _lastDabPos = filtered.clone();
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
    // Pre-multiply color per dab alpha.
    for (final d in live._dabs) {
      final a = (d.alpha * 255).clamp(0, 255).round();
      if (a == 0) continue;
      final color = ui.Color.fromARGB(a, 255, 255, 255);
      final coreRatio = coreRatioFromHardness(_hardness);
      tiles.addDab(d.center, d.radius, color, coreRatio: coreRatio);
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
    // Compose tiles as mask, then tint with current color to produce final image.
    final rect = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, rect);
    // Build mask layer
    canvas.saveLayer(rect, ui.Paint());
    tiles.draw(canvas); // white-alpha mask
    // Apply tint
    final tintPaint = ui.Paint()
      ..blendMode = ui.BlendMode.srcIn
      ..color = BrushEngine.currentColor.withAlpha(255);
    canvas.drawRect(rect, tintPaint);
    canvas.restore();
    final pic = recorder.endRecording();
    return pic.toImage(width, height);
  }

  void disposeResources() {
    tiles.dispose();
  }

  void setPositionSmoothingMode(SmoothingMode mode) {
    if (positionMode == mode) return;
    positionMode = mode;
    // Reset stroke state so switching is immediate and artifact free.
    _lastDabPos = null;
    switch (positionMode) {
      case SmoothingMode.none:
        _posSmoother = PassthroughSmoother();
        break;
      case SmoothingMode.oneEuro:
        _posSmoother = OneEuroSmoother2D();
        break;
      case SmoothingMode.predictive:
        _posSmoother = PredictiveSmoother2D();
        break;
    }
    _posSmoother.reset();
    notifyListeners();
  }
}

// NOTE: Sprite generation removed in analytic circle version. Keeping a stub
// (commented out) here for potential future reinstatement of atlas path.
// Future<ui.Image> _makeSoftDiscSprite(int size, double hardness) async { ... }
