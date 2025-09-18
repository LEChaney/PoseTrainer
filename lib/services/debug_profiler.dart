import 'dart:async';

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

  static int nowMs() => DateTime.now().millisecondsSinceEpoch;
  bool _inputBatchOpen = false; // microtask-guard to avoid double-counting

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

  double _ratePerSec(List<int> times) {
    if (times.isEmpty) return 0;
    final cutoff = nowMs() - 1000;
    int count = 0;
    for (int i = times.length - 1; i >= 0; i--) {
      if (times[i] >= cutoff) {
        count++;
      } else {
        break;
      }
    }
    return count.toDouble();
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
}
