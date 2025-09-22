import 'dart:async';
import 'package:flutter/scheduler.dart';

/// DebugProfiler
///
/// Lightweight, allocation-friendly profiler used in-app to understand:
/// - How frequently things happen (paints/sec, frames/sec, inputs/sec, tile flushes/sec)
/// - Pacing (average interval between consecutive events)
/// - Latencies (time from last input/frame to the end of a paint)
/// - Tile rasterization cost (count and per-tile durations)
///
/// Measurement model
/// - Time base: milliseconds since epoch (ms). Per-tile timing uses microseconds converted to ms.
/// - Rates (X/sec): simple rolling count of timestamps within the last 1000 ms.
/// - Average intervals: mean delta between consecutive timestamps, prioritizing ~last 1s window.
/// - Input sampling: deduped per microtask to avoid double-counting nested handlers from a single event.
/// - Paint latency: computed at notePaintEnd() using the most recent input and frame times.
///
/// Integration guidance
/// - Call [notePointerSample] in pointer handlers (down/move/hover as needed). The microtask guard
///   collapses multiple calls from the same input processing burst into a single sample.
/// - Call [noteFrameFlush] after each engine/frame flush (e.g., after baking live dabs to tiles).
/// - Call [notePaintEnd] at the end of CustomPainter.paint; pass the start time to get paint duration.
/// - For tiles, wrap your flush with [noteTileFlushStart]/[noteTileFlushEnd] and call
///   [noteTileRasterized] with per-tile durations.

/// Very lightweight in-app profiler for paint/input pacing and latency.
///
/// Collects timestamps for pointer samples, frame flushes (engine updates),
/// and paints, and exposes rolling rates (events/sec) and simple latencies.
class DebugProfiler {
  // Rolling timestamp buffers (ms since epoch)
  final List<int> _pointerMs = [];
  final List<int> _frameMs = [];
  final List<int> _paintMs = [];
  final List<int> _tileFlushMs = []; // when a flush completes

  // Search screen instrumentation -----------------------------------------
  final List<int> _searchBuildMs = [];
  final List<int> _gridItemBuildMs = [];
  final List<int> _imageWidgetBuildMs = [];
  final List<int> _searchScrollMs = [];
  double _lastScrollVelocityPxPerSec = 0;
  double? _lastScrollOffset;
  int? _lastScrollTimeMs;

  // Durations
  double _lastPaintDurationMs = 0;
  double _lastInputToPaintMs = 0;
  double _lastFrameToPaintMs = 0;
  double _lastTileFlushDurationMs = 0; // total time spent in last tiles.flush
  int _lastTileFlushCount = 0; // tiles processed in last flush
  double _lastTileAvgMs = 0; // avg ms per tile in last flush
  double _lastTileMaxMs = 0; // slowest single tile in last flush
  double _lastTileMinMs = 0; // fastest single tile in last flush

  // Last input sample time (ms) to compute input->paint latency.
  int? _lastInputSampleMs;
  // Last frame flush time (ms) to compute frame->paint delta.
  int? _lastFrameMs;
  // Tile flush bookkeeping
  int? _tileFlushStartMs;
  final List<double> _tileDurationsMs = [];

  // Keep buffers bounded to avoid unbounded growth.
  /// Maximum timestamps retained per buffer. Defaults to ~4 seconds at 60 Hz.
  /// Larger values smooth rates/averages but increase memory churn when trimming.
  int maxSamples = 240; // ~4 seconds at 60Hz
  int maxFrameSamples = 180; // ~3 seconds at 60Hz for frame aggregates

  static int nowMs() => DateTime.now().millisecondsSinceEpoch;
  bool _inputBatchOpen = false; // microtask-guard to avoid double-counting

  // Frame timing (from engine) ------------------------------------------------
  bool _schedulerAttached = false;
  final List<double> _frameTotalMs = [];
  final List<double> _frameBuildMs = [];
  final List<double> _frameRasterMs = [];

  // Per-frame aggregates for Search screen events -----------------------------
  double _currFrameSearchBuildMs = 0;
  double _currFrameGridItemBuildMs = 0;
  double _currFrameImageWidgetMs = 0;
  final List<double> _perFrameSearchBuildMs = [];
  final List<double> _perFrameGridItemBuildMs = [];
  final List<double> _perFrameImageWidgetMs = [];

  // Labeled subtree paint timings (ms) ---------------------------------------
  final Map<String, List<double>> _subtreePaintMs = {};

  /// Record a pointer/input sample at [tMs] (ms since epoch). If omitted, uses now.
  ///
  /// Deduplicates within the same microtask to avoid counting multiple nested
  /// callbacks triggered by the same raw input event.
  void notePointerSample([int? tMs]) {
    // Deduplicate within the same microtask so nested handlers don't double count.
    if (_inputBatchOpen) return;
    _inputBatchOpen = true;
    scheduleMicrotask(() => _inputBatchOpen = false);
    final t = tMs ?? nowMs();
    _lastInputSampleMs = t;
    _pointerMs.add(t);
    _trim(_pointerMs);
  }

  /// Record that a frame/engine update (e.g., brush bake/flush) completed.
  ///
  /// Use to compute frames/sec and frame→paint latency.
  void noteFrameFlush([int? tMs]) {
    final t = tMs ?? nowMs();
    _lastFrameMs = t;
    _frameMs.add(t);
    _trim(_frameMs);
  }

  /// Optional paint start marker for potential future breakdowns.
  /// Currently not used by metrics, but kept for symmetry.
  void notePaintStart() {
    // No-op for now; kept for potential future breakdowns.
  }

  /// Called at the end of a CustomPainter.paint. If [startedAtMs] is provided,
  /// computes [lastPaintDurationMs] as (now - startedAtMs).
  ///
  /// Also updates latencies:
  /// - [lastInputToPaintMs]: time from the most recent input sample to now.
  /// - [lastFrameToPaintMs]: time from the most recent frame flush to now.
  void notePaintEnd([int? startedAtMs]) {
    final end = nowMs();
    if (startedAtMs != null) {
      _lastPaintDurationMs = (end - startedAtMs).toDouble();
    }
    if (_lastInputSampleMs != null) {
      _lastInputToPaintMs = (end - _lastInputSampleMs!).toDouble();
    }
    if (_lastFrameMs != null) {
      _lastFrameToPaintMs = (end - _lastFrameMs!).toDouble();
    }
    _paintMs.add(end);
    _trim(_paintMs);
  }

  // Tile rasterization profiling ------------------------------------------
  /// Mark the start of a tile flush at [tMs] (defaults to now).
  /// Resets per-tile duration accumulation.
  void noteTileFlushStart([int? tMs]) {
    _tileFlushStartMs = tMs ?? nowMs();
    _tileDurationsMs.clear();
  }

  /// Record the duration (in milliseconds) to rasterize a single tile.
  /// Call once per tile during a flush between [noteTileFlushStart]/[noteTileFlushEnd].
  void noteTileRasterized(double durationMs) {
    _tileDurationsMs.add(durationMs);
  }

  /// Mark the end of a tile flush. Computes the aggregate stats for the last flush:
  /// - [lastTileFlushCount], [lastTileFlushDurationMs]
  /// - [lastTileAvgMs], [lastTileMinMs], [lastTileMaxMs]
  /// Also appends a timestamp for tile flush rate/interval metrics.
  void noteTileFlushEnd([int? tMs]) {
    final end = tMs ?? nowMs();
    final start = _tileFlushStartMs;
    if (start != null) {
      _lastTileFlushDurationMs = (end - start).toDouble();
    } else {
      _lastTileFlushDurationMs = 0;
    }
    _lastTileFlushCount = _tileDurationsMs.length;
    if (_lastTileFlushCount > 0) {
      double sum = 0;
      double minV = _tileDurationsMs.first;
      double maxV = _tileDurationsMs.first;
      for (final v in _tileDurationsMs) {
        sum += v;
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }
      _lastTileAvgMs = sum / _lastTileFlushCount;
      _lastTileMinMs = minV;
      _lastTileMaxMs = maxV;
    } else {
      _lastTileAvgMs = 0;
      _lastTileMinMs = 0;
      _lastTileMaxMs = 0;
    }
    _tileFlushMs.add(end);
    _trim(_tileFlushMs);
    _tileFlushStartMs = null;
    _tileDurationsMs.clear();
  }

  // Search screen instrumentation -----------------------------------------
  /// Record that the SearchScreen root widget rebuilt.
  void noteSearchBuild([int? tMs]) {
    final t = tMs ?? nowMs();
    _searchBuildMs.add(t);
    _trim(_searchBuildMs);
  }

  /// Record the duration (ms) spent within SearchScreen.build() for this frame.
  void noteSearchBuildDuration(double durationMs) {
    if (durationMs.isNaN || durationMs.isInfinite) return;
    _currFrameSearchBuildMs += durationMs;
  }

  /// Record that a GridView itemBuilder ran (one tile widget built).
  void noteGridItemBuilt([int? tMs]) {
    final t = tMs ?? nowMs();
    _gridItemBuildMs.add(t);
    _trim(_gridItemBuildMs);
  }

  /// Record the time (ms) spent building one Grid item widget (itemBuilder).
  void noteGridItemBuildDuration(double durationMs) {
    if (durationMs.isNaN || durationMs.isInfinite) return;
    _currFrameGridItemBuildMs += durationMs;
  }

  /// Record that an Image.network widget was instantiated in the grid.
  void noteSearchImageWidgetCreated([int? tMs]) {
    final t = tMs ?? nowMs();
    _imageWidgetBuildMs.add(t);
    _trim(_imageWidgetBuildMs);
  }

  /// Record the time (ms) spent constructing an Image widget in the grid.
  void noteSearchImageWidgetCreateDuration(double durationMs) {
    if (durationMs.isNaN || durationMs.isInfinite) return;
    _currFrameImageWidgetMs += durationMs;
  }

  /// Record a scroll tick and compute an approximate velocity in px/sec.
  void noteSearchScroll(double offset, [int? tMs]) {
    final t = tMs ?? nowMs();
    final lastT = _lastScrollTimeMs;
    final lastO = _lastScrollOffset;
    if (lastT != null && lastO != null) {
      final dt = (t - lastT).clamp(1, 1 << 30);
      _lastScrollVelocityPxPerSec = ((offset - lastO) / dt) * 1000.0;
    }
    _lastScrollTimeMs = t;
    _lastScrollOffset = offset;
    _searchScrollMs.add(t);
    _trim(_searchScrollMs);
  }

  // Public metrics --------------------------------------------------------

  /// Recent paints per second. Counts paint-end timestamps within the last 1s.
  double get paintsPerSec => _ratePerSec(_paintMs);

  /// Recent engine/frame flushes per second.
  double get framesPerSec => _ratePerSec(_frameMs);

  /// Recent deduped input samples per second (microtask-collapsed).
  double get inputsPerSec => _ratePerSec(_pointerMs);

  /// Recent tile flushes per second (flush-end timestamps within last 1s).
  double get tileFlushesPerSec => _ratePerSec(_tileFlushMs);

  /// Average time between consecutive paints (ms). Prefers ~last 1s window.
  double get avgPaintIntervalMs => _avgIntervalMs(_paintMs);

  /// Average time between consecutive frame flushes (ms).
  double get avgFrameIntervalMs => _avgIntervalMs(_frameMs);

  /// Average time between consecutive input samples (ms).
  double get avgInputIntervalMs => _avgIntervalMs(_pointerMs);

  /// Average time between consecutive tile flushes (ms).
  double get avgTileFlushIntervalMs => _avgIntervalMs(_tileFlushMs);

  /// Duration of the last CustomPainter.paint (ms), if start time was provided.
  double get lastPaintDurationMs => _lastPaintDurationMs;

  /// Time from the most recent input sample to the end of the last paint (ms).
  double get lastInputToPaintMs => _lastInputToPaintMs;

  /// Time from the most recent frame flush to the end of the last paint (ms).
  double get lastFrameToPaintMs => _lastFrameToPaintMs;

  /// Total time spent in the last tiles.flush() (ms) between flush start/end markers.
  double get lastTileFlushDurationMs => _lastTileFlushDurationMs;

  /// Number of tiles rasterized in the last flush.
  int get lastTileFlushCount => _lastTileFlushCount;

  /// Average rasterization time per tile (ms) in the last flush.
  double get lastTileAvgMs => _lastTileAvgMs;

  /// Slowest single tile time (ms) in the last flush.
  double get lastTileMaxMs => _lastTileMaxMs;

  /// Fastest single tile time (ms) in the last flush.
  double get lastTileMinMs => _lastTileMinMs;

  // Search metrics ---------------------------------------------------------
  /// Recent SearchScreen builds per second.
  double get searchBuildsPerSec => _ratePerSec(_searchBuildMs);

  /// Recent GridView item builds per second.
  double get gridItemsBuiltPerSec => _ratePerSec(_gridItemBuildMs);

  /// Recent Image.network creations per second in SearchScreen grid.
  double get imageWidgetsPerSec => _ratePerSec(_imageWidgetBuildMs);

  /// Recent scroll ticks per second captured from SearchScreen controller.
  double get searchScrollTicksPerSec => _ratePerSec(_searchScrollMs);

  /// Approximate last scroll velocity in px/sec (signed).
  double get lastScrollVelocityPxPerSec => _lastScrollVelocityPxPerSec;

  // Time between latest input sample and current time when called.
  /// Age of the most recent input sample in milliseconds at query time.
  int get inputToNowLatencyMs {
    final li = _lastInputSampleMs;
    if (li == null) return 0;
    return (nowMs() - li).clamp(0, 1 << 30);
  }

  // Time between last frame flush and now (useful when called during paint).
  /// Age of the most recent frame flush in milliseconds at query time.
  int get frameToNowLatencyMs {
    final lf = _lastFrameMs;
    if (lf == null) return 0;
    return (nowMs() - lf).clamp(0, 1 << 30);
  }

  // Helpers ---------------------------------------------------------------
  void _trim(List<int> buf) {
    final remove = buf.length - maxSamples;
    if (remove > 0) {
      buf.removeRange(0, remove);
    }
  }

  void _trimD(List<double> buf, [int? cap]) {
    final max = cap ?? maxFrameSamples;
    final remove = buf.length - max;
    if (remove > 0) {
      buf.removeRange(0, remove);
    }
  }

  double _ratePerSec(List<int> times) {
    if (times.isEmpty) return 0;
    final now = nowMs();
    final cutoff = now - 1000;
    // Find index of the first timestamp within the 1s window from the end.
    int startIdx = times.length;
    for (int i = times.length - 1; i >= 0; i--) {
      if (times[i] >= cutoff) {
        startIdx = i;
      } else {
        break;
      }
    }
    if (startIdx == times.length) return 0; // none in window
    final count = times.length - startIdx;
    final windowStart = times[startIdx];
    final windowMs = (now - windowStart).clamp(1, 10000);
    return count / (windowMs / 1000.0);
  }

  double _avgIntervalMs(List<int> times) {
    if (times.length < 2) return 0;
    // Use up to last ~1s of intervals for stability.
    final cutoff = nowMs() - 1000;
    final recent = <int>[];
    for (int i = times.length - 1; i >= 0; i--) {
      if (times[i] >= cutoff) {
        recent.add(times[i]);
      } else {
        break;
      }
    }
    if (recent.length < 2) {
      // Fallback to entire buffer if recent too small
      recent.clear();
      recent.addAll(times);
    }
    if (recent.length < 2) return 0;
    double sum = 0;
    int n = 0;
    for (int i = 1; i < recent.length; i++) {
      sum += (recent[i] - recent[i - 1]).toDouble();
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  // Frame hooks ------------------------------------------------------------
  /// Attach to Flutter's scheduler to collect FrameTiming and roll per-frame
  /// aggregates for the Search screen. Safe to call multiple times.
  void attachToScheduler() {
    if (_schedulerAttached) return;
    _schedulerAttached = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    // Post-frame callback to finalize per-frame aggregates each frame.
    void postFrame(Duration _) {
      _finalizeCurrentFrame();
      SchedulerBinding.instance.addPostFrameCallback(postFrame);
    }

    SchedulerBinding.instance.addPostFrameCallback(postFrame);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _frameTotalMs.add(t.totalSpan.inMicroseconds / 1000.0);
      _frameBuildMs.add(t.buildDuration.inMicroseconds / 1000.0);
      _frameRasterMs.add(t.rasterDuration.inMicroseconds / 1000.0);
      _trimD(_frameTotalMs);
      _trimD(_frameBuildMs);
      _trimD(_frameRasterMs);
    }
  }

  void _finalizeCurrentFrame() {
    _perFrameSearchBuildMs.add(_currFrameSearchBuildMs);
    _perFrameGridItemBuildMs.add(_currFrameGridItemBuildMs);
    _perFrameImageWidgetMs.add(_currFrameImageWidgetMs);
    _trimD(_perFrameSearchBuildMs);
    _trimD(_perFrameGridItemBuildMs);
    _trimD(_perFrameImageWidgetMs);
    _currFrameSearchBuildMs = 0;
    _currFrameGridItemBuildMs = 0;
    _currFrameImageWidgetMs = 0;
  }

  // Stats helpers ----------------------------------------------------------
  double _avgD(List<double> v) {
    if (v.isEmpty) return 0;
    double s = 0;
    for (final x in v) s += x;
    return s / v.length;
  }

  double _minD(List<double> v) {
    if (v.isEmpty) return 0;
    double m = v.first;
    for (final x in v) {
      if (x < m) m = x;
    }
    return m;
  }

  double _maxD(List<double> v) {
    if (v.isEmpty) return 0;
    double m = v.first;
    for (final x in v) {
      if (x > m) m = x;
    }
    return m;
  }

  // Labeled subtree paint metrics -------------------------------------------
  void noteSubtreePaint(String label, double durationMs) {
    if (durationMs.isNaN || durationMs.isInfinite) return;
    final list = _subtreePaintMs.putIfAbsent(label, () => <double>[]);
    list.add(durationMs);
    _trimD(list);
  }

  double subtreeAvgMs(String label) =>
      _avgD(_subtreePaintMs[label] ?? const []);
  double subtreeMinMs(String label) =>
      _minD(_subtreePaintMs[label] ?? const []);
  double subtreeMaxMs(String label) =>
      _maxD(_subtreePaintMs[label] ?? const []);
  bool hasSubtreeLabel(String label) => _subtreePaintMs.containsKey(label);

  // Public per-frame metrics (ms) -----------------------------------------
  double get frameAvgTotalMs => _avgD(_frameTotalMs);
  double get frameMinTotalMs => _minD(_frameTotalMs);
  double get frameMaxTotalMs => _maxD(_frameTotalMs);

  double get frameAvgBuildMs => _avgD(_frameBuildMs);
  double get frameMinBuildMs => _minD(_frameBuildMs);
  double get frameMaxBuildMs => _maxD(_frameBuildMs);

  double get frameAvgRasterMs => _avgD(_frameRasterMs);
  double get frameMinRasterMs => _minD(_frameRasterMs);
  double get frameMaxRasterMs => _maxD(_frameRasterMs);

  double get perFrameAvgSearchBuildMs => _avgD(_perFrameSearchBuildMs);
  double get perFrameMinSearchBuildMs => _minD(_perFrameSearchBuildMs);
  double get perFrameMaxSearchBuildMs => _maxD(_perFrameSearchBuildMs);

  double get perFrameAvgGridItemBuildMs => _avgD(_perFrameGridItemBuildMs);
  double get perFrameMinGridItemBuildMs => _minD(_perFrameGridItemBuildMs);
  double get perFrameMaxGridItemBuildMs => _maxD(_perFrameGridItemBuildMs);

  double get perFrameAvgImageWidgetMs => _avgD(_perFrameImageWidgetMs);
  double get perFrameMinImageWidgetMs => _minD(_perFrameImageWidgetMs);
  double get perFrameMaxImageWidgetMs => _maxD(_perFrameImageWidgetMs);
}
