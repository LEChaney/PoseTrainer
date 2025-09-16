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

// Layout constants (tune here – single source)
const double _kWideCanvasFraction = 0.65;
const double _kDividerThickness = 1.0;

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
  ui.Image? _base; // committed strokes
  final List<InputPoint> _pending = [];
  late final Ticker _ticker;
  bool _handedOff = false; // Becomes true once we pass _base to ReviewScreen.
  bool _ctrlDown = false; // track Control key for panning mode

  // Pixel density / base sizing
  int _baseWidthPx = 0;
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
    _initBase(w, h);
    // Ticker drives per-frame flushing of buffered pointer points to the brush engine.
    _ticker = createTicker(_onFrame)..start();
  }

  Future<void> _initBase(int w, int h) async {
    _baseWidthPx = w;
    _baseHeightPx = h;
    final rec = ui.PictureRecorder();
    ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    final pic = rec.endRecording();
    _base = await pic.toImage(w, h);
    setState(() {}); // Trigger repaint with new blank base.
  }

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
  }

  void _flushPending() {
    if (_pending.isEmpty) return;
    engine.addPoints(List.of(_pending));
    _pending.clear();
  }

  Future<void> _commitStroke() async {
    // Merge current live stroke (dabs) onto the backing image.
    if (_base == null) return;
    _flushPending();
    final previous = _base!; // retain old reference; do NOT dispose yet.
    final w = previous.width, h = previous.height;
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(
      rec,
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );
    // Draw previous base first.
    canvas.drawImage(previous, ui.Offset.zero, ui.Paint());
    // Composite live dabs on top.
    engine.live.draw(canvas);
    final pic = rec.endRecording();
    final merged = await pic.toImage(w, h);
    // Swap to new image before scheduling disposal of old to avoid a tiny race
    // where pointer events arriving between dispose() and assignment would
    // still read width/height from a disposed image (seen on web canvaskit).
    _base = merged;
    // Defer disposal to end of frame so any in-flight events using the old
    // image complete safely.
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    engine.live.clear();
    setState(() {}); // Repaint with committed state.
  }

  Future<void> _finish() async {
    // Finalize: commit any in-progress stroke, store session, navigate to review.
    await _commitStroke();
    if (!mounted || _base == null) return;
    if (widget.reference != null) {
      context.read<SessionService>().add(
        widget.sourceUrl,
        widget.reference!,
        _base!,
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
          drawing: _base!,
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
      _base?.dispose();
    }
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

  Widget _buildBody() => LayoutBuilder(
    builder: (context, constraints) {
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final isWide = constraints.maxWidth > 900;
      final referencePanel = _ReferencePanel(
        reference: widget.reference,
        referenceUrl: widget.referenceUrl,
      );

      // Decide canvas logical size (pre‑snap) based on mode.
      Size canvasLogical;
      Widget layout;

      if (isWide) {
        final rawCanvasLogicalW =
            constraints.maxWidth * _kWideCanvasFraction - _kDividerThickness;
        final snappedCanvasLogicalW = _snapLogical(rawCanvasLogicalW, dpr);
        final refLogicalW =
            constraints.maxWidth - _kDividerThickness - snappedCanvasLogicalW;
        canvasLogical = Size(snappedCanvasLogicalW, constraints.maxHeight);

        layout = Row(
          children: [
            SizedBox(width: refLogicalW, child: referencePanel),
            const VerticalDivider(width: _kDividerThickness),
            SizedBox(
              width: canvasLogical.width,
              height: canvasLogical.height,
              child: _buildCanvasArea(dpr, canvasLogical),
            ),
          ],
        );
      } else {
        final rawCanvasLogicalH =
            constraints.maxHeight * _kWideCanvasFraction - _kDividerThickness;
        final snappedCanvasLogicalH = _snapLogical(rawCanvasLogicalH, dpr);
        final refLogicalH =
            constraints.maxHeight - _kDividerThickness - snappedCanvasLogicalH;
        canvasLogical = Size(constraints.maxWidth, snappedCanvasLogicalH);

        layout = Column(
          children: [
            SizedBox(height: refLogicalH, child: referencePanel),
            const Divider(height: _kDividerThickness),
            SizedBox(
              width: canvasLogical.width,
              height: canvasLogical.height,
              child: _buildCanvasArea(dpr, canvasLogical),
            ),
          ],
        );
      }

      // Schedule backing growth (or initial creation) from a single snapped size.
      _scheduleGrowthIfNeeded(canvasLogical, dpr);

      // Dev overlay (brush sliders)
      return Stack(
        children: [
          layout,
          Positioned(right: 8, top: 8, child: _BrushSliders(engine: engine)),
        ],
      );
    },
  );

  Widget _buildCanvasArea(double dpr, Size canvasLogical) {
    return _CanvasArea(
      engine: engine,
      pending: _pending,
      pressure: _pressure,
      nowMs: _nowMs,
      commitStroke: _commitStroke,
      flushPending: _flushPending,
      base: _base,
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

    if (_base == null) {
      _initBase(reqW, reqH);
      return;
    }

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
    final old = _base; // keep reference for deferred disposal
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(
      rec,
      ui.Rect.fromLTWH(0, 0, newW.toDouble(), newH.toDouble()),
    );
    if (old != null) {
      canvas.drawImage(old, ui.Offset.zero, ui.Paint());
    }
    final pic = rec.endRecording();
    final grown = await pic.toImage(newW, newH);
    // Swap first, then dispose old after frame to avoid transient reads of
    // a disposed image by ongoing pointer handlers querying size.
    _base = grown;
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    _baseWidthPx = newW;
    _baseHeightPx = newH;
    _pendingGrowW = _pendingGrowH = null;
    setState(() {});
  }

  Widget _buildClearFab() => FloatingActionButton.extended(
    onPressed: () async {
      if (_base == null) return;
      _pending.clear();
      engine.live.clear();
      engine.resetStroke();
      // Recreate base matching current viewport (grow target if pending)
      final w = _pendingGrowW ?? _baseWidthPx;
      final h = _pendingGrowH ?? _baseHeightPx;
      await _initBase(w, h);
      _pendingGrowW = _pendingGrowH = null;
    },
    label: const Text('Clear'),
    icon: const Icon(Icons.undo),
  );
}

class _ReferencePanel extends StatelessWidget {
  final ui.Image? reference;
  final String? referenceUrl;
  const _ReferencePanel({required this.reference, required this.referenceUrl});
  @override
  Widget build(BuildContext context) {
    Widget child;
    if (reference != null) {
      child = FittedBox(
        fit: BoxFit.contain,
        child: RawImage(image: reference),
      );
    } else if (referenceUrl != null) {
      child = Image.network(
        referenceUrl!,
        fit: BoxFit.contain,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      );
    } else {
      child = const Center(child: Text('No reference'));
    }
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF1A1A1E)),
      child: Center(child: child),
    );
  }
}

class _CanvasArea extends StatefulWidget {
  final BrushEngine engine;
  final List<InputPoint> pending;
  final double Function(dynamic) pressure;
  final int Function() nowMs;
  final Future<void> Function() commitStroke;
  final VoidCallback flushPending;
  final ui.Image? base;
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
                widget.base,
                widget.engine.live,
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
    final base = widget.base;
    if (base == null) return;
    final dpr = widget.devicePixelRatio;
    final imgX = widget.viewportOriginPx.dx + e.localPosition.dx * dpr;
    final imgY = widget.viewportOriginPx.dy + e.localPosition.dy * dpr;
    if (imgX < 0 || imgY < 0 || imgX >= base.width || imgY >= base.height) {
      return; // safety
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
  double _hardness = 0.2; // initial matches params.hardness
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
              min: 0.3,
              max: 5.0,
            ),
            _buildSlider(
              label: 'Flow',
              value: _flow,
              onChanged: (v) {
                setState(() => _flow = v);
                widget.engine.setFlowScale(v);
              },
              min: 0.2,
              max: 2.0,
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
  final ui.Image? base;
  final StrokeLayer live;
  final double devicePixelRatio;
  final Offset viewportOriginPx;
  final int viewWidthPx;
  final int viewHeightPx;
  _PracticePainter(
    this.base,
    this.live, {
    required this.devicePixelRatio,
    required this.viewportOriginPx,
    required this.viewWidthPx,
    required this.viewHeightPx,
  });
  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    canvas.drawRect(
      Offset.zero & size,
      ui.Paint()..color = const Color(0xFF111115),
    );
    final baseImage = base;
    if (baseImage == null) {
      // Nothing yet
      return;
    }
    canvas.save();
    // Scale down so that image pixels map 1:1 to device pixels (logical coords scaled by dpr later by engine)
    final inv = 1 / devicePixelRatio;
    canvas.scale(inv, inv);
    // Translate so viewport origin becomes (0,0) in logical space after scale
    canvas.translate(-viewportOriginPx.dx, -viewportOriginPx.dy);
    // Draw base full-res (no filter scaling happening)
    canvas.drawImage(
      baseImage,
      ui.Offset.zero,
      ui.Paint()..filterQuality = FilterQuality.none,
    );
    // Draw live dabs in image pixel space
    live.draw(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PracticePainter old) => true;
}

/// Snap a logical dimension so logical * dpr is an integer pixel span.
double _snapLogical(double logical, double dpr) =>
    (logical * dpr).floor() / dpr;
