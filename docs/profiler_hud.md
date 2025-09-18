# Profiler HUD

A quick reference for the on‑screen profiling overlay used in Practice.

This HUD surfaces rates, pacing, latencies, and tile rasterization costs gathered by `lib/services/debug_profiler.dart`.

## Quick Legend
- Paint: Number of paint completions per second; average time between paints.
- Frame: Engine flushes per second (post‑bake/flush); average interval.
- Input: Deduped input samples per second; average interval.
- Latency: Time from last Input → end of paint, and from last Frame → end of paint.
- Paint time: Duration of the last `CustomPainter.paint`.
- Tiles: Count and total ms for last tile flush; average/min/max ms per tile.
- Tile flush rate: Flushes per second; average interval between flushes.

## Metrics Details
- Paint (fps)
  - Meaning: How often the CustomPainter finished painting.
  - Expectation: Near display refresh when painting continuously. Can be lower if nothing changes or due to throttling.
  - Shown as: `fps (avg interval ms)`.

- Frame (hz)
  - Meaning: How often the engine flushed/baked live dabs to tiles (your per‑frame work).
  - Expectation: Similar to paint rate when drawing; may differ during idle or batching.
  - Shown as: `hz (avg interval ms)`.

- Input (hz)
  - Meaning: Recent input samples per second. Input is deduplicated per microtask to avoid counting nested callbacks from the same event.
  - Expectation: Can exceed frame rate (e.g., high‑frequency pointer events). During hover or fast moves, this may be high.
  - Shown as: `hz (avg interval ms)`.

- Latency
  - Input → Paint: Time from the most recent input sample to the end of the last paint. Lower is better (input responsiveness).
  - Frame → Paint: Time from the most recent engine flush to the end of the last paint. Indicates how quickly work appears on screen after bake/flush.

- Paint time (ms)
  - Meaning: Duration of the last `paint()` call. Use to track draw complexity, shader/layout cost, and overdraw.

- Tiles (N in T ms; avg|min–max)
  - Meaning: For the most recent tile flush, number of tiles rasterized (N) and total flush time (T). Also reports average, minimum, and maximum per‑tile rasterization time.
  - Notes: Per‑tile times are measured with microsecond precision and shown in ms.

- Tile flush rate (hz; avg interval ms)
  - Meaning: How frequently tile flushes complete. Useful to correlate with frame pacing and batching.

## How Values Are Computed
- Time base: milliseconds since epoch. Per‑tile timing uses microseconds converted to ms.
- Rates (X/sec): Count of timestamps within the last 1000ms.
- Average intervals: Mean delta between consecutive timestamps, preferring ~last 1s; falls back to buffer if too few.
- Buffers: Rolling windows, capped by `maxSamples` (~4s at 60Hz by default).
- Input dedupe: `notePointerSample()` collapses multiple calls in the same microtask to a single sample.

## Reading Tips
- High Input, lower Frame: Input is outpacing your processing; expect input→paint latency to grow if work is deferred.
- High Frame, low Paint: Engine is flushing work, but painter isn’t repainting (or is throttled/is idle).
- Large Paint time: Optimize painter, reduce overdraw, or isolate repaint regions with `RepaintBoundary`.
- High Tile max ms: A single heavy tile is a hotspot. Consider smaller tiles, reducing dab density, or batching logic.
- Spiky Input→Paint: Input sampling bursts or GC/async gaps; verify `_pending` flushing cadence and per‑frame work.

## Integration Pointers
- Input: Call `DebugProfiler.notePointerSample()` in pointer handlers (down/move/hover as needed).
- Frame/Engine: Call `noteFrameFlush()` after baking/flush per frame.
- Paint: Call `notePaintEnd(startMs)` at end of `paint()`.
- Tiles: Surround flush with `noteTileFlushStart()`/`noteTileFlushEnd()` and call `noteTileRasterized(perTileMs)` inside your per‑tile work.

## UI Controls
- Toggle HUD: App Bar speed icon or `F8`.
- HUD Isolation: The overlay is wrapped with `RepaintBoundary` and `IgnorePointer` to avoid input interference and unnecessary repaints.

## Source
- Profiler: `lib/services/debug_profiler.dart`
- HUD: `lib/screens/practice_screen.dart` (`_ProfilerHud`)
- Tiling: `lib/services/tiled_surface.dart`
