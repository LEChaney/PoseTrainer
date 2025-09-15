import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/scheduler.dart';
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
  FitMode _fitMode = FitMode.cover; // default preserves full image without crop

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
    // WHY: We maintain strokes on a backing image to avoid reprocessing old dabs each frame.
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
    final w = _base!.width, h = _base!.height;
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(
      rec,
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );
    canvas.drawImage(_base!, ui.Offset.zero, ui.Paint());
    engine.live.draw(canvas); // Composite live dabs.
    final pic = rec.endRecording();
    final merged = await pic.toImage(w, h);
    _base!.dispose(); // Free old image memory.
    _base = merged;
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
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
      floatingActionButton: _buildClearFab(),
    );
  }

  AppBar _buildAppBar() => AppBar(
    title: const Text('Practice'),
    actions: [
      // Toggle between letterboxed contain (no crop) and cover (fills space, crops edges)
      IconButton(
        icon: Icon(_fitMode == FitMode.contain ? Icons.crop_free : Icons.crop),
        tooltip: _fitMode == FitMode.contain
            ? 'Use full space (Cover)'
            : 'Preserve whole image (Contain)',
        onPressed: () => setState(() {
          _fitMode = _fitMode == FitMode.contain
              ? FitMode.cover
              : FitMode.contain;
        }),
      ),
      IconButton(
        icon: const Icon(Icons.check),
        onPressed: _finish,
        tooltip: 'Finish & Review',
      ),
    ],
  );

  Widget _buildBody() => LayoutBuilder(
    builder: (context, c) {
      final isWide = c.maxWidth > 900; // Simple responsive breakpoint.
      final referencePanel = _ReferencePanel(
        reference: widget.reference,
        referenceUrl: widget.referenceUrl,
      );
      final canvasArea = _CanvasArea(
        engine: engine,
        pending: _pending,
        pressure: _pressure,
        nowMs: _nowMs,
        commitStroke: _commitStroke,
        flushPending: _flushPending,
        base: _base,
        fitMode: _fitMode,
      );
      Widget layout = isWide
          ? Row(
              children: [
                SizedBox(width: c.maxWidth * 0.35, child: referencePanel),
                const VerticalDivider(width: 1),
                Expanded(child: canvasArea),
              ],
            )
          : Column(
              children: [
                SizedBox(height: c.maxHeight * 0.35, child: referencePanel),
                const Divider(height: 1),
                Expanded(child: canvasArea),
              ],
            );
      // Overlay sliders (temporary dev UI) for size & flow.
      layout = Stack(
        children: [
          layout,
          Positioned(right: 8, top: 8, child: _BrushSliders(engine: engine)),
        ],
      );
      return layout;
    },
  );

  Widget _buildClearFab() => FloatingActionButton.extended(
    onPressed: () async {
      if (_base == null) return; // Early return reduces nesting.
      _pending.clear();
      engine.live.clear();
      engine.resetStroke();
      await _initBase(_base!.width, _base!.height);
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

class _CanvasArea extends StatelessWidget {
  final BrushEngine engine;
  final List<InputPoint> pending;
  final double Function(dynamic) pressure;
  final int Function() nowMs;
  final Future<void> Function() commitStroke;
  final VoidCallback flushPending;
  final ui.Image? base;
  final FitMode fitMode;
  // We draw and store strokes in the intrinsic backing image coordinate space
  // (base.width x base.height). When the on-screen canvas is a different size
  // we simply scale the entire paint operation. This keeps stroke positions
  // stable between the final pointer up position and the committed result and
  // removes the visible "snap" caused by mixing raw screen coordinates with
  // image-space compositing.
  const _CanvasArea({
    required this.engine,
    required this.pending,
    required this.pressure,
    required this.nowMs,
    required this.commitStroke,
    required this.flushPending,
    required this.base,
    required this.fitMode,
  });
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _addPoint(e, size, reset: true),
          onPointerMove: (e) => _addPoint(e, size),
          onPointerUp: (e) async {
            //_addPoint(e, size); // Handled in move to avoid unexpected dabs on pointer up.
            flushPending();
            await commitStroke();
          },
          child: AnimatedBuilder(
            animation: engine,
            builder: (_, _) => CustomPaint(
              painter: _PracticePainter(base, engine.live, fitMode: fitMode),
              size: size,
            ),
          ),
        );
      },
    );
  }

  void _addPoint(PointerEvent e, Size widgetSize, {bool reset = false}) {
    if (reset) engine.resetStroke();
    if (base == null) return;
    // Aspect-preserving transform. Two modes:
    // contain -> letterbox (no crop, possibly unused bars, skip points outside)
    // cover   -> fills widget (may crop image, no unused bars)
    final iw = base!.width.toDouble();
    final ih = base!.height.toDouble();
    final sx = widgetSize.width / iw;
    final sy = widgetSize.height / ih;
    final bool cover = fitMode == FitMode.cover;
    final scale = cover ? math.max(sx, sy) : math.min(sx, sy);
    final drawW = iw * scale;
    final drawH = ih * scale;
    final dx = (widgetSize.width - drawW) / 2;
    final dy = (widgetSize.height - drawH) / 2;
    final local = e.localPosition;
    // Contain: ignore pointer in letterbox bars. Cover: always map (bars negative or zero).
    if (!cover) {
      if (local.dx < dx ||
          local.dx > dx + drawW ||
          local.dy < dy ||
          local.dy > dy + drawH) {
        return;
      }
    }
    // In cover mode some of the image is outside the widget. Clamp to bounds
    // so strokes at extreme edges do not wrap. (Could optionally allow out-of-range.)
    double imgX = (local.dx - dx) / scale;
    double imgY = (local.dy - dy) / scale;
    if (cover) {
      imgX = imgX.clamp(0.0, iw - 0.0001);
      imgY = imgY.clamp(0.0, ih - 0.0001);
    }
    pending.add(InputPoint(imgX, imgY, pressure(e), nowMs()));
  }
}

// Temporary development sliders for brush size & flow.
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
              max: 3.0,
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
  _PracticePainter(this.base, this.live, {this.fitMode = FitMode.contain});
  final FitMode fitMode;
  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    // BRUSH RENDERING NOTES (post-gap & snap fixes):
    // - Pointer samples are transformed into backing image space immediately.
    // - We scale the canvas (image -> widget) once, then draw both the
    //   committed base and the live stroke so their coordinates align exactly.
    // - Gaps: The brush engine now interpolates intermediate dabs when motion
    //   distance exceeds spacing, ensuring even coverage at high speed.
    // - Square artifact: The brush sprite adds a transparent gutter + fully
    //   transparent outer color stop to prevent hard alpha edges.
    // Clear background.
    canvas.drawRect(
      Offset.zero & size,
      ui.Paint()..color = const Color(0xFF111115),
    );
    if (base == null) {
      live.draw(canvas);
      return;
    }
    final iw = base!.width.toDouble();
    final ih = base!.height.toDouble();
    final sx = size.width / iw;
    final sy = size.height / ih;
    final scale = fitMode == FitMode.cover
        ? math.max(sx, sy)
        : math.min(sx, sy);
    final drawW = iw * scale;
    final drawH = ih * scale;
    final dx = (size.width - drawW) / 2;
    final dy = (size.height - drawH) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);
    canvas.drawImage(base!, ui.Offset.zero, ui.Paint());
    live.draw(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PracticePainter old) => true;
}

// Fit mode for drawing surface scaling.
enum FitMode { contain, cover }
