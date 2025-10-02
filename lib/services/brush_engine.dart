import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart'; // for ChangeNotifier
import 'package:vector_math/vector_math_64.dart'
    show Vector2; // Unified 2D math
import 'tiled_surface.dart';
import 'dab_renderer.dart';
import '../theme/colors.dart';
import 'debug_profiler.dart';
import 'debug_logger.dart';

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

  // Per-dab flow modeling (density of ink per stamp)
  final double maxFlow; // Target (max) per-dab flow at/after maxFlowPressure
  final double minFlow; // Flow at zero pressure (sketch taper transparency)
  final double maxFlowPressure; // Pressure level where flow reaches target

  // Size taper modeling
  final double minScale; // Diameter fraction at zero pressure (0.05 => 5%)
  final double sizeGamma; // <1 => faster early growth (SAI-like)
  final double flowGamma; // Flow response curve shaping

  // Edge softness
  final double hardness; // 0 soft halo, 1 hard edge

  // Per-stroke opacity cap (used within-stroke as a clamp conceptually)
  final double opacity; // 0..1
  // Stroke color (currently single monochrome brush). Alpha is modulated per dab.
  final ui.Color color;

  // UI runtime defaults (for sliders)
  final double runtimeSizeScale; // 0.01..1.0
  final double runtimeFlowScale; // 0.01..1.0 (advanced)
  final double
  runtimeOpacityScale; // 0.0..1.0 global stroke blend when committing

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
    this.runtimeSizeScale = 0.75,
    this.runtimeFlowScale = 0.3,
    this.runtimeOpacityScale = 1.0,
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
    double? runtimeOpacityScale,
  }) {
    return BrushParams(
      maxSizePx: maxSizePx ?? this.maxSizePx,
      spacing: spacing ?? this.spacing,
      maxFlow: flow ?? maxFlow,
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
      runtimeOpacityScale: runtimeOpacityScale ?? this.runtimeOpacityScale,
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

// Smoothing removed: positions and pressure are used raw for deterministic
// and simpler behavior while debugging. Complex smoothing algorithms were
// causing nondeterministic issues and have been removed to simplify the
// engine. If smoothing is reintroduced later, add focused, well-tested
// implementations behind feature flags.

// Smoothing removed: use raw input directly. The above smoothing classes
// were removed to simplify debugging; pressure and position are used as-is.

// No low-pass utilities; smoothing has been removed to simplify behavior.

class Dab {
  final ui.Offset center;
  final double radius;

  /// Per-dab flow (density per stamp), 0..1
  final double flow;

  /// Pressure-driven opacity clamp for this dab, 0..1
  final double opacityClamp;
  const Dab(this.center, this.radius, this.flow, this.opacityClamp);
}

class StrokeLayer {
  // Analytic rendering version (no sprite). Each dab is drawn as a circle.
  // WHY: The sprite-based approach showed a visible square even for a single
  // dab due to the wide gradient tail + texture minification sampling faint
  // non-zero alpha out to the corners. For simplicity and correctness we draw
  // circles directly; a lightweight blur provides soft edges.
  final List<Dab> _dabs = [];
  double _hardness = 0.8; // 0 = very soft (wide halo), 1 = hard (thin halo)
  int _dabLogCount = 0; // Rate limiting for per-dab logging

  /// Public getter for dab count (for debugging)
  int get dabCount => _dabs.length;

  Future<void> ensureSprite(double hardness) async {
    // Retained for interface compatibility; no sprite needed now.
    _hardness = hardness.clamp(0, 1);
  }

  void setHardness(double h) {
    _hardness = h.clamp(0, 1);
  }

  void clear() {
    _dabs.clear();
  }

  void add(Dab d) => _dabs.add(d);

  void draw(
    ui.Canvas canvas, {
    double? maxSizePx,
    double? spacing,
    double? runtimeSizeScale,
  }) {
    // Radial gradient dab with hardness-controlled core and feather.
    // hardness 0 => small core, long feather. hardness 1 => large core, short feather.

    // Calculate dynamic logging rate based on brush parameters
    // Smaller brushes with tighter spacing generate more dabs, so log less frequently
    int logRate = 100000; // Default rate
    if (maxSizePx != null && spacing != null && runtimeSizeScale != null) {
      final effectiveSize = maxSizePx * runtimeSizeScale;
      final dabsPerPixel =
          1.0 / spacing; // Approximate dabs per pixel of movement
      final expectedDabRate =
          dabsPerPixel / effectiveSize; // Higher for small brushes

      // Scale log rate inversely with expected dab generation rate
      // Small brushes (high dab rate) -> higher log rate (less frequent logging)
      // Large brushes (low dab rate) -> lower log rate (more frequent logging)
      logRate = (100 * expectedDabRate).clamp(50, 1000000).round();
    }

    int i = 0;
    for (final dab in _dabs) {
      // Smart rate-limited logging based on brush parameters
      if (_dabLogCount % logRate == 0) {
        final previewAlpha = (dab.flow * dab.opacityClamp).clamp(0.0, 1.0);
        debugLog(
          'Drawing dab at ${dab.center}, radius=${dab.radius.toStringAsFixed(1)}, alpha=${(previewAlpha * 255).round()} (${i + 1}/${_dabs.length}) [logRate=$logRate]',
          tag: 'StrokeLayer',
        );
      }
      _dabLogCount++;
      i++;
      // Centralized helper handles alpha->color and hardness->coreRatio.
      // Preview alpha uses flow * opacityClamp.
      drawDabWithAlphaAndHardness(
        canvas,
        dab.center,
        dab.radius,
        (dab.flow * dab.opacityClamp).clamp(0.0, 1.0),
        _hardness,
      );
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
  late final TiledSurface tiles; // committed base mask tiles
  late final TiledSurface
  liveTiles; // current stroke mask tiles (cleared on commit)
  // Smoothing removed: use raw pressure and positions directly.
  Vector2? _lastDabPos; // Last dab center to enforce spacing (null => none yet)
  // Corner detection raw history (unsmoothed)
  // Raw input history removed; curvature-based blending disabled.

  // Track current hardness like other runtime controls for consistent access.
  double _hardness;

  final DebugProfiler? profiler;

  BrushEngine(this.params, {this.profiler}) : _hardness = params.hardness {
    tiles = TiledSurface(tileSize: 256, profiler: profiler);
    liveTiles = TiledSurface(tileSize: 256, profiler: profiler);
    _strokeColorFallback = params.color;
    // Initialize runtime scales from params so UI can change defaults centrally.
    _runtimeSizeScale = params.runtimeSizeScale;
    _runtimeFlowScale = params.runtimeFlowScale;
    _runtimeOpacityScale = params.runtimeOpacityScale;
  }

  // Generic input mapping (pressure/tilt/etc.) – swappable extractors.
  // Today we only have pressure; adding tilt/rotation later becomes trivial.
  double Function(InputPoint) sizeInput = (p) => p.pressure;
  double Function(InputPoint) opacityInput = (p) => p.pressure;
  double Function(InputPoint) flowInput = (p) => 1.0; // constant by default

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
  double _runtimeFlowScale = 0.5; // advanced control
  double _runtimeOpacityScale = 1.0; // global blend when committing stroke

  // Expose current runtime controls so UI can initialize from engine state.
  double get sizeScale => _runtimeSizeScale;
  double get flowScale => _runtimeFlowScale; // advanced
  double get opacityScale => _runtimeOpacityScale;
  double get hardness => _hardness;

  void setSizeScale(double v) {
    _runtimeSizeScale = v.clamp(0.01, 1.0);
    notifyListeners();
  }

  void setFlowScale(double v) {
    _runtimeFlowScale = v.clamp(0.01, 1.0);
    notifyListeners();
  }

  void setOpacityScale(double v) {
    _runtimeOpacityScale = v.clamp(0.0, 1.0);
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
    // No smoothing state to reset; clear last dab so spacing restarts.
    _lastDabPos = null;
    live.clear();
    // Start a fresh live stroke layer per stroke
    liveTiles.clear();
  }

  /// Clear all stroke data (live + committed tiles) and notify listeners so
  /// the UI repaints immediately (used by Clear button).
  void clearAll() {
    resetStroke();
    tiles.clear();
    liveTiles.clear();
    notifyListeners();
  }

  // Convert filtered points to dabs with consistent spacing. Interpolate
  // intermediate dabs when distance > spacing to avoid gaps.
  Iterable<Dab> _emit(Iterable<InputPoint> raw) sync* {
    for (final p in raw) {
      // Use raw input directly: no position smoothing or pressure filtering.
      final filtered = p.toV();
      final spSize = sizeInput(p).clamp(0.0, 1.0);
      final spOpacity = opacityInput(p).clamp(0.0, 1.0);
      // Size pressure curve (gamma <1 => aggressive early growth)
      final sizeCurve = math.pow(spSize, params.sizeGamma).toDouble();
      final diameter =
          (params.maxSizePx * _runtimeSizeScale) *
          (params.minScale + (1 - params.minScale) * sizeCurve);
      final spacingPx = (params.spacing.clamp(0.05, 1.0)) * diameter;
      // Pressure→opacity mapping (default). Flow remains an advanced control (constant along stroke).
      final flow =
          (params.minFlow +
                  (params.maxFlow - params.minFlow) * _runtimeFlowScale)
              .clamp(0.0, 1.0);
      final opacityFromPressure = math
          .pow(spOpacity, params.flowGamma)
          .toDouble()
          .clamp(0.0, 1.0);

      // --- Emit first dab immediately ---------------------------------------
      if (_lastDabPos == null) {
        final radius = diameter * 0.5;
        final alphaFlow = flow;
        final opacityClamp = opacityFromPressure; // shader will enforce clamp
        debugLog(
          'First dab: pos=${filtered.x.toStringAsFixed(1)},${filtered.y.toStringAsFixed(1)}, radius=${radius.toStringAsFixed(2)}, flow=${alphaFlow.toStringAsFixed(3)}, opacityClamp=${opacityClamp.toStringAsFixed(3)}, pressure=${p.pressure.toStringAsFixed(3)}',
          tag: 'BrushEngine',
        );
        yield Dab(
          ui.Offset(filtered.x, filtered.y),
          radius,
          alphaFlow,
          opacityClamp,
        );
        // Advance last position to the emitted dab (same as filtered for first dab)
        _lastDabPos = filtered.clone();
        continue;
      }

      // --- Distance & interpolation via Vector2 -----------------------------
      final lastPos = _lastDabPos!;
      final delta = filtered - lastPos;
      final dist = delta.length;
      if (dist < spacingPx) {
        // Not far enough yet: keep last emitted where it was to preserve leftover distance
        continue;
      }
      final dir = delta / dist; // normalized
      var traveled = spacingPx;
      Vector2?
      lastEmitted; // track the last emitted dab position for carry-over
      while (traveled <= dist) {
        final pos = lastPos + dir * traveled;
        final radius = diameter * 0.5;
        final alphaFlow = flow;
        final opacityClamp = opacityFromPressure;
        // Per-dab logging removed (too verbose)
        yield Dab(ui.Offset(pos.x, pos.y), radius, alphaFlow, opacityClamp);
        lastEmitted = pos;
        traveled += spacingPx;
      }
      // Advance the last dab position only to the last emitted dab to retain leftover distance.
      if (lastEmitted != null) {
        _lastDabPos = lastEmitted.clone();
      }
    }
  }

  // Add new raw points (e.g., from pointer events). Notifies listeners so the
  // CustomPainter can repaint the live stroke.
  void addPoints(List<InputPoint> pts) {
    // Only log when processing large point batches (reduce normal drawing noise)
    if (pts.length > 10) {
      debugLog(
        'addPoints called with ${pts.length} points',
        tag: 'BrushEngine',
      );
    }
    // No smoothing: don't maintain raw history.
    int dabCount = 0;
    for (final d in _emit(pts)) {
      live.add(d);
      dabCount++;
    }

    // Calculate dynamic logging threshold based on brush parameters
    // Smaller brushes with tighter spacing generate more dabs, so require higher thresholds
    final effectiveSize = params.maxSizePx * _runtimeSizeScale;
    final dabsPerPixel = 1.0 / params.spacing;
    final expectedDabRate = dabsPerPixel / effectiveSize;

    // Scale threshold: small brushes need higher thresholds to avoid spam
    final logThreshold = (10 * expectedDabRate).clamp(5, 50).round();

    // Smart logging based on brush characteristics
    if (pts.length > logThreshold) {
      debugLog(
        'Generated $dabCount dabs, live dabs total: ${live._dabs.length} [threshold=$logThreshold, effectiveSize=${effectiveSize.toStringAsFixed(1)}px]',
        tag: 'BrushEngine',
      );
    }
    if (pts.isNotEmpty) {
      notifyListeners();
      // Listener notification logging removed (too verbose)
    }
  }

  // _maybeHandleCorner removed: curvature-based blending supplants explicit snapping.

  /// Bake current live dabs directly into tiles and clear live list. Called once per frame
  /// after all new points have been added so cost stays evenly distributed.
  Future<void> bakeLiveToTiles() async {
    if (live._dabs.isEmpty) {
      // No need to log empty baking calls (too verbose)
      return;
    }

    // Rasterize dabs to the live stroke layer
    await liveTiles.bakeDabs(
      live._dabs,
      coreRatioFromHardness(_hardness),
      maxSizePx: params.maxSizePx,
      spacing: params.spacing,
      runtimeSizeScale: _runtimeSizeScale,
    );

    // Reduce baking completion logging (too verbose)
    // debugLog('Clearing live dabs', tag: 'BrushEngine');
    live.clear();
    // debugLog('bakeLiveToTiles complete', tag: 'BrushEngine');
    notifyListeners();
  }

  /// Commit the current live stroke into the base tiles with global opacity scaling.
  Future<void> commitLiveToBase() async {
    // Ensure all live dabs have been rasterized to the liveTiles first.
    await bakeLiveToTiles();
    await tiles.blendFrom(liveTiles, opacityScale: _runtimeOpacityScale);
    liveTiles.clear();
    notifyListeners();
  }

  /// Compose a full image (used when finishing session). Draws tiles then optional live tail.
  Future<ui.Image> renderFull(int width, int height) async {
    // Ensure any remaining live dabs are committed first for consistency.
    await commitLiveToBase();
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
    liveTiles.dispose();
  }

  // Position smoothing removed; this method intentionally omitted.
}

// NOTE: Sprite generation removed in analytic circle version. Keeping a stub
// (commented out) here for potential future reinstatement of atlas path.
// Future<ui.Image> _makeSoftDiscSprite(int size, double hardness) async { ... }
