import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/gestures.dart'; // added for PointerDeviceKind
import 'package:flutter/services.dart'; // for HardwareKeyboard / KeyEvent
import '../services/brush_engine.dart';
import '../services/session_service.dart';
import '../models/practice_result.dart';
import 'review_screen.dart';
import '../theme/colors.dart';
// Layout constants consumed indirectly by ReferenceDrawSplit.
import '../widgets/reference_draw_split.dart';
import '../services/debug_profiler.dart';

// practice_screen.dart
// --------------------
// Core drawing experience.
// Key concepts for newcomers:
// - We maintain a backing `ui.Image` (_base) that stores committed strokes.
// - Current in‑progress stroke lives in BrushEngine.live (drawn every frame).
// - Pointer events are buffered (_pending) then flushed each animation tick
//   to keep UI responsive while batching smoothing.
// - A Ticker (from SingleTickerProviderStateMixin) drives per-frame updates.
// - Reference can be provided as a decoded image (native) OR just a URL (web).
// - Layout adapts: wide = side-by-side, narrow = vertical stack.

// Layout constants now come from `constants/layout.dart`.
// Potential future: expose stroke color palette UI; current default comes from BrushParams.

class PracticeScreen extends StatefulWidget {
  final ui.Image? reference; // may be null on web if we only have URL
  final String? referenceUrl; // used on web to display via Image.network
  final String sourceUrl;
  final int? timeLimitSeconds; // when set, shows countdown and auto-finishes
  final bool sessionMode; // when true, pop PracticeResult instead of navigating
  const PracticeScreen({
    super.key,
    this.reference,
    this.referenceUrl,
    required this.sourceUrl,
    this.timeLimitSeconds,
    this.sessionMode = false,
  });
  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen>
    with SingleTickerProviderStateMixin {
  late final BrushEngine engine;
  ui.Image? _finalComposite; // only created on finish for review
  final List<InputPoint> _pending = [];
  late final Ticker _ticker;
  bool _handedOff = false; // Becomes true once we pass _base to ReviewScreen.
  bool _ctrlDown = false; // track Control key for panning mode
  final DebugProfiler _profiler = DebugProfiler();
  bool _showProfilerHud = false; // toggle for on-screen profiler
  // Countdown state (session mode)
  Timer? _countdown;
  int _remainingSec = 0;

  // Pixel density / base sizing
  int _baseWidthPx = 0; // canvas extent tracked for export sizing
  int _baseHeightPx = 0;
  int? _pendingGrowW; // scheduled growth target width (px)
  int? _pendingGrowH; // scheduled growth target height (px)
  Offset _viewportOriginPx =
      Offset.zero; // top-left of visible window in base pixels

  // --- Lifecycle -----------------------------------------------------------

  @override
  void initState() {
    super.initState();
    engine = BrushEngine(const BrushParams(), profiler: _profiler)..prepare();
    // Pick canvas size: use reference image dimensions if available; otherwise a square fallback.
    final w = widget.reference?.width ?? 1200;
    final h = widget.reference?.height ?? 1200;
    _baseWidthPx = w;
    _baseHeightPx = h;
    // Ticker drives per-frame flushing of buffered pointer points to the brush engine.
    _ticker = createTicker(_onFrame)..start();
    // Start countdown if in timed session
    final limit = widget.timeLimitSeconds;
    if (limit != null && limit > 0) {
      _remainingSec = limit;
      _countdown = Timer.periodic(const Duration(seconds: 1), (t) async {
        if (!mounted) return;
        if (_remainingSec <= 1) {
          t.cancel();
          _remainingSec = 0;
          // Time up -> finish
          await _finish();
          return;
        }
        setState(() => _remainingSec--);
      });
    }
  }

  // (Old _initBase removed – tiling approach no longer preallocates full image.)

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  double _pressure(dynamic e) {
    // Normalize hardware pressure range to 0..1 (fallback 0.5 when unknown).
    if (e is PointerEvent) {
      final denom = (e.pressureMax - e.pressureMin);
      if (denom == 0) return 0.5;
      final v = ((e.pressure - e.pressureMin) / denom).clamp(0.0, 1.0);
      return v.isFinite ? v : 0.5;
    }
    return 0.5;
  }

  void _onFrame(Duration _) {
    // Flush buffered pointer samples into the brush engine once per frame.
    if (_pending.isEmpty) return;
    debugPrint('[Frame] Processing ${_pending.length} pending points');
    engine.addPoints(List.of(_pending));
    _pending.clear();
    // After adding new points, bake existing live dabs for constant cost.
    // Await to keep ordering predictable; work is per-dab small.
    engine.bakeLiveToTiles();
    _profiler.noteFrameFlush();
    debugPrint('[Frame] Frame processing complete');
  }

  void _flushPending() {
    if (_pending.isEmpty) return;
    debugPrint('[Flush] Manually flushing ${_pending.length} pending points');
    engine.addPoints(List.of(_pending));
    _pending.clear();
    engine.bakeLiveToTiles();
    _profiler.noteFrameFlush();
    debugPrint('[Flush] Manual flush complete');
  }

  Future<void> _commitStroke() async {
    /* no-op: baking occurs every frame */
  }

  Future<void> _finish() async {
    // Finalize: commit any in-progress stroke, store session, navigate to review.
    // Ensure final baking then render composite.
    _flushPending();
    await engine.bakeLiveToTiles();
    final finalImg = await engine.renderFull(_baseWidthPx, _baseHeightPx);
    _finalComposite = finalImg;
    if (!mounted) return;
    if (!widget.sessionMode) {
      if (widget.reference != null || widget.referenceUrl != null) {
        context.read<SessionService>().add(
          sourceUrl: widget.sourceUrl,
          reference: widget.reference,
          referenceUrl: widget.referenceUrl,
          drawing: finalImg,
        );
      }
    }
    // We are about to transfer ownership of _base to the next screen. We must
    // NOT dispose it in dispose(), otherwise the ReviewScreen's painters will
    // attempt to draw a disposed image causing the drawImage/assert failure
    // observed in overlay mode.
    _handedOff = true;
    if (widget.sessionMode) {
      Navigator.of(context).pop(PracticeResult.completed(finalImg));
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ReviewScreen(
            reference: widget.reference,
            referenceUrl: widget.referenceUrl,
            drawing: finalImg,
            sourceUrl: widget.sourceUrl,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _countdown?.cancel();
    // Dispose only if we still own the backing image. After navigation to
    // ReviewScreen the image is displayed there and must remain valid.
    if (!_handedOff) {
      _finalComposite?.dispose();
    }
    engine.disposeResources();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(debugLabel: 'practiceScreenKeyboard')
        ..requestFocus(),
      onKeyEvent: (KeyEvent event) {
        final isCtrl = HardwareKeyboard.instance.isControlPressed;
        if (isCtrl != _ctrlDown) {
          setState(() => _ctrlDown = isCtrl);
        }
        // Simple keyboard toggle for profiler HUD
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.f8) {
          setState(() => _showProfilerHud = !_showProfilerHud);
        }
      },
      child: Scaffold(
        appBar: _buildAppBar(),
        body: _buildBody(),
        floatingActionButton: _buildClearFab(),
      ),
    );
  }

  AppBar _buildAppBar() => AppBar(
    title: const Text('Practice'),
    actions: [
      IconButton(
        icon: Icon(_showProfilerHud ? Icons.speed : Icons.speed_outlined),
        onPressed: () => setState(() => _showProfilerHud = !_showProfilerHud),
        tooltip: _showProfilerHud ? 'Hide Profiler (F8)' : 'Show Profiler (F8)',
      ),
      if (widget.sessionMode)
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const PracticeResult.skipped()),
          child: const Text('Skip'),
        ),
      IconButton(
        icon: const Icon(Icons.check),
        onPressed: _finish,
        tooltip: 'Finish & Review',
      ),
    ],
  );

  Widget _buildBody() => ReferenceDrawSplit(
    referenceImage: widget.reference,
    referenceUrl: widget.referenceUrl,
    letterboxReference: true,
    letterboxDrawing: true,
    overlayTopRight: _BrushSliders(engine: engine),
    drawingChild: LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final canvasLogical = Size(constraints.maxWidth, constraints.maxHeight);
        _scheduleGrowthIfNeeded(canvasLogical, dpr);
        return Stack(
          children: [
            _buildCanvasArea(dpr, canvasLogical),
            if (widget.timeLimitSeconds != null)
              Positioned(
                top: 8,
                left: 8,
                child: _CountdownChip(
                  remaining: _remainingSec,
                  total: widget.timeLimitSeconds!,
                ),
              ),
            if (_showProfilerHud)
              Positioned(
                left: 8,
                bottom: 8,
                child: _ProfilerHud(profiler: _profiler),
              ),
          ],
        );
      },
    ),
  );

  Widget _buildCanvasArea(double dpr, Size canvasLogical) {
    return _CanvasArea(
      engine: engine,
      pending: _pending,
      pressure: _pressure,
      nowMs: _nowMs,
      commitStroke: _commitStroke,
      flushPending: _flushPending,
      base:
          _finalComposite, // only non-null after finish for review context painting
      ctrlDown: _ctrlDown,
      viewportOriginPx: _viewportOriginPx,
      baseWidthPx: _baseWidthPx,
      baseHeightPx: _baseHeightPx,
      devicePixelRatio: dpr,
      applyPendingGrowth: _applyPendingGrowthIfAny,
      onViewportChange: (o) => setState(() => _viewportOriginPx = o),
      profiler: _profiler,
    );
  }

  /// Ensures backing image matches (or grows to) snapped canvas size.
  void _scheduleGrowthIfNeeded(Size snappedLogicalSize, double dpr) {
    // dpr retained locally; no longer cached globally (removed unused field warning).

    // Because we snapped logical size, this multiplication should be integral.
    final reqW = (snappedLogicalSize.width * dpr).round();
    final reqH = (snappedLogicalSize.height * dpr).round();

    assert(() {
      final exactW = snappedLogicalSize.width * dpr;
      final exactH = snappedLogicalSize.height * dpr;
      if (exactW % 1 != 0 || exactH % 1 != 0) {
        debugPrint(
          'WARNING: snapped size not integral: $exactW x $exactH (dpr=$dpr)',
        );
      }
      return true;
    }());

    if (reqW > _baseWidthPx || reqH > _baseHeightPx) {
      // Grow only upward (never shrink).
      _pendingGrowW = math.max(reqW, _baseWidthPx);
      _pendingGrowH = math.max(reqH, _baseHeightPx);
    }

    // Clamp viewport origin (if canvas shrank within existing base).
    _viewportOriginPx = Offset(
      _viewportOriginPx.dx.clamp(
        0.0,
        (_baseWidthPx - reqW).clamp(0, _baseWidthPx).toDouble(),
      ),
      _viewportOriginPx.dy.clamp(
        0.0,
        (_baseHeightPx - reqH).clamp(0, _baseHeightPx).toDouble(),
      ),
    );
  }

  Future<void> _applyPendingGrowthIfAny() async {
    if (_pendingGrowW == null || _pendingGrowH == null) return;
    final newW = _pendingGrowW!;
    final newH = _pendingGrowH!;
    if (newW <= _baseWidthPx && newH <= _baseHeightPx) {
      _pendingGrowW = _pendingGrowH = null;
      return;
    }
    // Tiles are sparse; no need to reallocate. Just update dimensions.
    _baseWidthPx = newW;
    _baseHeightPx = newH;
    _pendingGrowW = _pendingGrowH = null;
    setState(() {});
  }

  Widget _buildClearFab() => FloatingActionButton.extended(
    onPressed: () async {
      _pending.clear();
      engine.clearAll();
      _pendingGrowW = _pendingGrowH = null;
      setState(() {});
    },
    label: const Text('Clear'),
    icon: const Icon(Icons.undo),
  );
}

// _ReferencePanel removed (logic centralized in ReferenceDrawSplit).

class _CanvasArea extends StatefulWidget {
  final BrushEngine engine;
  final List<InputPoint> pending;
  final double Function(dynamic) pressure;
  final int Function() nowMs;
  final Future<void> Function() commitStroke;
  final VoidCallback flushPending;
  final ui.Image?
  base; // only populated after finish for review screen navigation state
  final bool ctrlDown;
  final Offset viewportOriginPx;
  final int baseWidthPx;
  final int baseHeightPx;
  final double devicePixelRatio;
  final Future<void> Function() applyPendingGrowth;
  final ValueChanged<Offset> onViewportChange;
  final DebugProfiler profiler;
  const _CanvasArea({
    required this.engine,
    required this.pending,
    required this.pressure,
    required this.nowMs,
    required this.commitStroke,
    required this.flushPending,
    required this.base,
    required this.ctrlDown,
    required this.viewportOriginPx,
    required this.baseWidthPx,
    required this.baseHeightPx,
    required this.devicePixelRatio,
    required this.applyPendingGrowth,
    required this.onViewportChange,
    required this.profiler,
  });
  @override
  State<_CanvasArea> createState() => _CanvasAreaState();
}

class _CanvasAreaState extends State<_CanvasArea> {
  Offset? _lastPanPos;
  final Map<int, Offset> _touchPoints = {};
  bool _multiPan = false;
  // For improved two-finger pan: record image-space anchors for each pointer
  final Map<int, Offset> _multiPanImagePoints = {};

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final logicalSize = Size(c.maxWidth, c.maxHeight);
        final dpr = widget.devicePixelRatio;
        final viewWidthPx = (logicalSize.width * dpr).ceil();
        final viewHeightPx = (logicalSize.height * dpr).ceil();
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) async {
            widget.profiler.notePointerSample();
            if (e.kind == PointerDeviceKind.touch) {
              _touchPoints[e.pointer] = e.localPosition;
              if (_touchPoints.length >= 2) {
                _multiPan = true;
                // Capture image-space locations under each finger so we can
                // compute a viewport that keeps those pixels under the fingers
                // (feels like pushing a paper with two fingers).
                final dpr = widget.devicePixelRatio;
                _multiPanImagePoints.clear();
                for (final entry in _touchPoints.entries) {
                  final imgPt = widget.viewportOriginPx + entry.value * dpr;
                  _multiPanImagePoints[entry.key] = imgPt;
                }
              } else {
                // Single touch - ensure we're not in multi-pan mode
                _multiPan = false;
                _multiPanImagePoints.clear();
              }
            }

            // Determine if this should be panning or drawing
            final shouldPan =
                widget.ctrlDown || (_multiPan && _touchPoints.length >= 2);

            // Debug logging for touch issues
            debugPrint(
              '[Touch] PointerDown: kind=${e.kind}, touchCount=${_touchPoints.length}, multiPan=$_multiPan, shouldPan=$shouldPan',
            );

            if (shouldPan) {
              _lastPanPos = e.localPosition;
              debugPrint('[Touch] Starting pan mode');
            } else {
              await widget.applyPendingGrowth();
              _addPoint(e, logicalSize, reset: true);
              debugPrint('[Touch] Adding drawing point at ${e.localPosition}');
            }
          },
          onPointerMove: (e) {
            widget.profiler.notePointerSample();
            if (e.kind == PointerDeviceKind.touch &&
                _touchPoints.containsKey(e.pointer)) {
              _touchPoints[e.pointer] = e.localPosition;
            }

            // Determine if this should be panning or drawing
            final shouldPan =
                widget.ctrlDown || (_multiPan && _touchPoints.length >= 2);

            if (shouldPan) {
              if (_multiPan &&
                  e.kind == PointerDeviceKind.touch &&
                  _touchPoints.length >= 2) {
                _handleTwoFingerPan(logicalSize, viewWidthPx, viewHeightPx);
              } else {
                _handlePanMove(e, logicalSize, viewWidthPx, viewHeightPx);
              }
            } else {
              _addPoint(e, logicalSize);
            }
          },
          onPointerHover: (e) {
            widget.profiler.notePointerSample();
          },
          onPointerUp: (e) async {
            if (e.kind == PointerDeviceKind.touch) {
              _touchPoints.remove(e.pointer);
              if (_touchPoints.length < 2) {
                _multiPan = false;
                _multiPanImagePoints.clear();
              }
            }

            // Only commit stroke if we were in drawing mode (not panning)
            final wasPanning =
                widget.ctrlDown || (_multiPan && _touchPoints.length >= 1);
            if (!wasPanning) {
              widget.flushPending();
              await widget.commitStroke();
            }
            _lastPanPos = null;
          },
          onPointerCancel: (e) {
            if (e.kind == PointerDeviceKind.touch) {
              _touchPoints.remove(e.pointer);
              if (_touchPoints.length < 2) {
                _multiPan = false;
                _multiPanImagePoints.clear();
              }
            }
            _lastPanPos = null;
          },
          child: AnimatedBuilder(
            animation: widget.engine,
            builder: (context, child) => RepaintBoundary(
              child: CustomPaint(
                painter: _PracticePainter(
                  base: widget.base,
                  live: widget.engine.live,
                  engine: widget.engine,
                  devicePixelRatio: dpr,
                  viewportOriginPx: widget.viewportOriginPx,
                  viewWidthPx: viewWidthPx,
                  viewHeightPx: viewHeightPx,
                  profiler: widget.profiler,
                ),
                size: logicalSize,
              ),
            ),
          ),
        );
      },
    );
  }

  void _handlePanMove(PointerEvent e, Size logicalSize, int viewW, int viewH) {
    Offset delta;
    if (_multiPan && _touchPoints.isNotEmpty) {
      final centroid =
          _touchPoints.values.reduce((a, b) => a + b) /
          _touchPoints.length.toDouble();
      if (_lastPanPos == null) {
        _lastPanPos = centroid;
        return;
      }
      delta = centroid - _lastPanPos!;
      _lastPanPos = centroid;
    } else {
      if (_lastPanPos == null) {
        _lastPanPos = e.localPosition;
        return;
      }
      delta = e.localPosition - _lastPanPos!;
      _lastPanPos = e.localPosition;
    }
    final dpr = widget.devicePixelRatio;
    final pixelDelta = Offset(delta.dx * dpr, delta.dy * dpr);
    var origin =
        widget.viewportOriginPx - pixelDelta; // drag content with pointer
    // Clamp within base
    final maxX = (widget.baseWidthPx - viewW)
        .clamp(0, widget.baseWidthPx)
        .toDouble();
    final maxY = (widget.baseHeightPx - viewH)
        .clamp(0, widget.baseHeightPx)
        .toDouble();
    origin = Offset(origin.dx.clamp(0.0, maxX), origin.dy.clamp(0.0, maxY));
    widget.onViewportChange(origin);
  }

  void _handleTwoFingerPan(Size logicalSize, int viewW, int viewH) {
    // Compute desired viewport origins that would keep each finger anchored
    // to its starting image pixel, then average them. This keeps both
    // fingers roughly over the same pixels (feels like pushing paper).
    if (_multiPanImagePoints.isEmpty) return;
    final dpr = widget.devicePixelRatio;
    final origins = <Offset>[];
    for (final entry in _multiPanImagePoints.entries) {
      final pointerId = entry.key;
      final imagePt = entry.value;
      final local = _touchPoints[pointerId];
      if (local == null) continue; // pointer lifted mid-gesture
      final desiredOrigin = imagePt - local * dpr;
      origins.add(desiredOrigin);
    }
    if (origins.isEmpty) return;
    var avg = origins.reduce((a, b) => a + b) / origins.length.toDouble();
    // Clamp within base
    final maxX = (widget.baseWidthPx - viewW)
        .clamp(0, widget.baseWidthPx)
        .toDouble();
    final maxY = (widget.baseHeightPx - viewH)
        .clamp(0, widget.baseHeightPx)
        .toDouble();
    avg = Offset(avg.dx.clamp(0.0, maxX), avg.dy.clamp(0.0, maxY));
    widget.onViewportChange(avg);
  }

  void _addPoint(PointerEvent e, Size logicalSize, {bool reset = false}) {
    if (reset) widget.engine.resetStroke();
    final dpr = widget.devicePixelRatio;
    final imgX = widget.viewportOriginPx.dx + e.localPosition.dx * dpr;
    final imgY = widget.viewportOriginPx.dy + e.localPosition.dy * dpr;

    debugPrint(
      '[Touch] _addPoint: local=${e.localPosition}, dpr=$dpr, img=($imgX, $imgY), bounds=(${widget.baseWidthPx}, ${widget.baseHeightPx})',
    );

    if (imgX < 0 ||
        imgY < 0 ||
        imgX >= widget.baseWidthPx ||
        imgY >= widget.baseHeightPx) {
      debugPrint('[Touch] Point outside bounds, ignoring');
      return; // outside canvas bounds
    }
    widget.pending.add(
      InputPoint(imgX, imgY, widget.pressure(e), widget.nowMs()),
    );
    debugPrint(
      '[Touch] Added point to pending list, total pending: ${widget.pending.length}',
    );
  }
}

class _BrushSliders extends StatefulWidget {
  final BrushEngine engine;
  const _BrushSliders({required this.engine});
  @override
  State<_BrushSliders> createState() => _BrushSlidersState();
}

class _BrushSlidersState extends State<_BrushSliders> {
  double _size = 0.1; // runtime size multiplier (initialized in initState)
  double _flow = 0.08; // runtime flow multiplier (initialized in initState)
  double _hardness = 1.0; // initialized in initState

  @override
  void initState() {
    super.initState();
    // Sync initial slider positions with engine's current runtime state
    // so defaults only need to be set in one place (BrushEngine/BrushParams).
    _size = widget.engine.sizeScale;
    _flow = widget.engine.flowScale;
    _hardness = widget.engine.hardness;
  }

  @override
  Widget build(BuildContext context) {
    // FLOW vs OPACITY NOTE:
    // Flow = per-dab alpha (ink laid down each stamp). Opacity (if added
    // later) would be a *cap* on cumulative stroke buildup. For a sketch
    // brush we only expose flow so light pressure yields faint marks but
    // repeated passes build darker tone.
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: Colors.black54,
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Brush', style: TextStyle(color: Colors.white70)),
            _buildSlider(
              label: 'Size',
              value: _size,
              onChanged: (v) {
                setState(() => _size = v);
                widget.engine.setSizeScale(v);
              },
              min: 0.01,
              max: 1.0,
            ),
            _buildSlider(
              label: 'Flow',
              value: _flow,
              onChanged: (v) {
                setState(() => _flow = v);
                widget.engine.setFlowScale(v);
              },
              min: 0.01,
              max: 1.0,
            ),
            _buildSlider(
              label: 'Hardness',
              value: _hardness,
              onChanged: (v) {
                setState(() => _hardness = v);
                widget.engine.setHardness(v);
              },
              min: 0.0,
              max: 1.0,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    required double min,
    required double max,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white)),
            Text(
              value.toStringAsFixed(2),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        Slider(
          value: value,
          onChanged: onChanged,
          min: min,
          max: max,
          divisions: 100,
        ),
      ],
    );
  }
}

class _PracticePainter extends CustomPainter {
  final ui.Image? base; // final composite only after finish
  final StrokeLayer live; // live stroke tail
  final BrushEngine engine; // provides tiled committed strokes
  final double devicePixelRatio;
  final Offset viewportOriginPx;
  final int viewWidthPx;
  final int viewHeightPx;
  final DebugProfiler profiler;
  _PracticePainter({
    required this.base,
    required this.live,
    required this.engine,
    required this.devicePixelRatio,
    required this.viewportOriginPx,
    required this.viewWidthPx,
    required this.viewHeightPx,
    required this.profiler,
  });
  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final startMs = DateTime.now().millisecondsSinceEpoch;
    // Fill visible region with paper color in case base is smaller / panned.
    canvas.drawRect(Offset.zero & size, ui.Paint()..color = kPaperColor);
    final baseImage = base; // null while drawing
    canvas.save();
    // Scale down so that image pixels map 1:1 to device pixels (logical coords scaled by dpr later by engine)
    final inv = 1 / devicePixelRatio;
    canvas.scale(inv, inv);
    // Translate so viewport origin becomes (0,0) in logical space after scale
    canvas.translate(-viewportOriginPx.dx, -viewportOriginPx.dy);
    // Draw base full-res (no filter scaling happening)
    if (baseImage != null) {
      // Final composite already tinted in renderFull
      canvas.drawImage(baseImage, ui.Offset.zero, ui.Paint());
    } else {
      // Build mask layer (tiles + live), then tint with stroke color
      final bounds = ui.Rect.fromLTWH(
        0,
        0,
        viewWidthPx.toDouble(),
        viewHeightPx.toDouble(),
      );
      canvas.saveLayer(bounds, ui.Paint());
      // Draw white-alpha tiles and live dabs
      debugPrint('[Painter] Drawing tiles and live dabs');
      engine.tiles.draw(canvas);
      debugPrint('[Painter] Drawing live stroke layer');
      live.draw(canvas);
      debugPrint('[Painter] Applying tint');
      // Apply tint via srcIn
      final tintPaint = ui.Paint()
        ..blendMode = ui.BlendMode.srcIn
        ..color = BrushEngine.currentColor.withAlpha(255);
      canvas.drawRect(bounds, tintPaint);
      canvas.restore();
    }
    canvas.restore();
    profiler.notePaintEnd(startMs);
  }

  @override
  bool shouldRepaint(covariant _PracticePainter old) => true;
}

class _ProfilerHud extends StatelessWidget {
  final DebugProfiler profiler;
  const _ProfilerHud({required this.profiler});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        ignoring: true,
        child: StreamBuilder<int>(
          stream: Stream<int>.periodic(
            const Duration(milliseconds: 250),
            (_) => 0,
          ),
          builder: (context, _) {
            final textStyle = Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Colors.white);
            final bg = Colors.black.withValues(alpha: 0.55);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DefaultTextStyle(
                style:
                    textStyle ??
                    const TextStyle(fontSize: 11, color: Colors.white),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Paint: ${profiler.paintsPerSec.toStringAsFixed(0)} fps  (${profiler.avgPaintIntervalMs.toStringAsFixed(1)} ms)',
                    ),
                    Text(
                      'Frame: ${profiler.framesPerSec.toStringAsFixed(0)} hz  (${profiler.avgFrameIntervalMs.toStringAsFixed(1)} ms)',
                    ),
                    Text(
                      'Input: ${profiler.inputsPerSec.toStringAsFixed(0)} hz  (${profiler.avgInputIntervalMs.toStringAsFixed(1)} ms)',
                    ),
                    Text(
                      'Latency: input→paint ${profiler.lastInputToPaintMs.toStringAsFixed(1)} ms  frame→paint ${profiler.lastFrameToPaintMs.toStringAsFixed(1)} ms',
                    ),
                    Text(
                      'Paint time: ${profiler.lastPaintDurationMs.toStringAsFixed(2)} ms',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tiles: ${profiler.lastTileFlushCount} in ${profiler.lastTileFlushDurationMs.toStringAsFixed(2)} ms'
                      '  (${profiler.lastTileAvgMs.toStringAsFixed(2)} avg |'
                      ' ${profiler.lastTileMinMs.toStringAsFixed(2)}–${profiler.lastTileMaxMs.toStringAsFixed(2)} ms)',
                    ),
                    Text(
                      'Tile flush rate: ${profiler.tileFlushesPerSec.toStringAsFixed(0)} hz  (${profiler.avgTileFlushIntervalMs.toStringAsFixed(1)} ms)',
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CountdownChip extends StatelessWidget {
  final int remaining;
  final int total;
  const _CountdownChip({required this.remaining, required this.total});
  @override
  Widget build(BuildContext context) {
    final r = remaining.clamp(0, total);
    final pct = total > 0 ? r / total : 0.0;
    final mm = (r ~/ 60).toString().padLeft(2, '0');
    final ss = (r % 60).toString().padLeft(2, '0');
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      color: Colors.black54,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 60,
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: Colors.white24,
              ),
            ),
            const SizedBox(width: 8),
            Text('$mm:$ss', style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

// _snapLogical removed; snapping handled in shared split widget.
