import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/gestures.dart'; // added for PointerDeviceKind
import 'package:flutter/services.dart'; // for HardwareKeyboard / KeyEvent
import '../services/brush_engine.dart';
import '../services/session_service.dart';
import 'review_screen.dart';
import '../theme/colors.dart';
// Layout constants consumed indirectly by ReferenceDrawSplit.
import '../widgets/reference_draw_split.dart';

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
  const PracticeScreen({
    super.key,
    this.reference,
    this.referenceUrl,
    required this.sourceUrl,
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
    engine = BrushEngine(const BrushParams())..prepare();
    // Pick canvas size: use reference image dimensions if available; otherwise a square fallback.
    final w = widget.reference?.width ?? 1200;
    final h = widget.reference?.height ?? 1200;
    _baseWidthPx = w;
    _baseHeightPx = h;
    // Ticker drives per-frame flushing of buffered pointer points to the brush engine.
    _ticker = createTicker(_onFrame)..start();
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
    engine.addPoints(List.of(_pending));
    _pending.clear();
    // After adding new points, bake existing live dabs for constant cost.
    // Await to keep ordering predictable; work is per-dab small.
    engine.bakeLiveToTiles();
  }

  void _flushPending() {
    if (_pending.isEmpty) return;
    engine.addPoints(List.of(_pending));
    _pending.clear();
    engine.bakeLiveToTiles();
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
    if (widget.reference != null) {
      context.read<SessionService>().add(
        widget.sourceUrl,
        widget.reference!,
        finalImg,
      );
    }
    // We are about to transfer ownership of _base to the next screen. We must
    // NOT dispose it in dispose(), otherwise the ReviewScreen's painters will
    // attempt to draw a disposed image causing the drawImage/assert failure
    // observed in overlay mode.
    _handedOff = true;
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

  @override
  void dispose() {
    _ticker.dispose();
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
        return _buildCanvasArea(dpr, canvasLogical);
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
  });
  @override
  State<_CanvasArea> createState() => _CanvasAreaState();
}

class _CanvasAreaState extends State<_CanvasArea> {
  Offset? _lastPanPos;
  final Map<int, Offset> _touchPoints = {};
  bool _multiPan = false;

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
            if (e.kind == PointerDeviceKind.touch) {
              _touchPoints[e.pointer] = e.localPosition;
              if (_touchPoints.length == 2) _multiPan = true;
            }
            if (widget.ctrlDown || _multiPan) {
              _lastPanPos = e.localPosition;
            } else {
              await widget.applyPendingGrowth();
              _addPoint(e, logicalSize, reset: true);
            }
          },
          onPointerMove: (e) {
            if (e.kind == PointerDeviceKind.touch &&
                _touchPoints.containsKey(e.pointer)) {
              _touchPoints[e.pointer] = e.localPosition;
            }
            if (widget.ctrlDown || _multiPan) {
              _handlePanMove(e, logicalSize, viewWidthPx, viewHeightPx);
            } else {
              _addPoint(e, logicalSize);
            }
          },
          onPointerUp: (e) async {
            if (e.kind == PointerDeviceKind.touch) {
              _touchPoints.remove(e.pointer);
              if (_touchPoints.length < 2) _multiPan = false;
            }
            if (!(widget.ctrlDown || _multiPan)) {
              widget.flushPending();
              await widget.commitStroke();
            }
            _lastPanPos = null;
          },
          onPointerCancel: (e) {
            if (e.kind == PointerDeviceKind.touch) {
              _touchPoints.remove(e.pointer);
              if (_touchPoints.length < 2) _multiPan = false;
            }
            _lastPanPos = null;
          },
          child: AnimatedBuilder(
            animation: widget.engine,
            builder: (context, child) => CustomPaint(
              painter: _PracticePainter(
                base: widget.base,
                live: widget.engine.live,
                engine: widget.engine,
                devicePixelRatio: dpr,
                viewportOriginPx: widget.viewportOriginPx,
                viewWidthPx: viewWidthPx,
                viewHeightPx: viewHeightPx,
              ),
              size: logicalSize,
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

  void _addPoint(PointerEvent e, Size logicalSize, {bool reset = false}) {
    if (reset) widget.engine.resetStroke();
    final dpr = widget.devicePixelRatio;
    final imgX = widget.viewportOriginPx.dx + e.localPosition.dx * dpr;
    final imgY = widget.viewportOriginPx.dy + e.localPosition.dy * dpr;
    if (imgX < 0 ||
        imgY < 0 ||
        imgX >= widget.baseWidthPx ||
        imgY >= widget.baseHeightPx) {
      return; // outside canvas bounds
    }
    widget.pending.add(
      InputPoint(imgX, imgY, widget.pressure(e), widget.nowMs()),
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
  double _size = 1.0; // runtime size multiplier
  double _flow = 1.0; // runtime flow multiplier
  double _hardness = 1.0; // initial matches params.hardness
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
  _PracticePainter({
    required this.base,
    required this.live,
    required this.engine,
    required this.devicePixelRatio,
    required this.viewportOriginPx,
    required this.viewWidthPx,
    required this.viewHeightPx,
  });
  @override
  void paint(ui.Canvas canvas, ui.Size size) {
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
      canvas.drawImage(baseImage, ui.Offset.zero, ui.Paint());
    } else {
      engine.tiles.draw(canvas);
    }
    // Draw live dabs in image pixel space
    live.draw(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PracticePainter old) => true;
}

// _snapLogical removed; snapping handled in shared split widget.
