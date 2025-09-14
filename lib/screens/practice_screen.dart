import 'dart:ui' as ui;
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

  Future<void> _commitStroke() async {
    // Merge current live stroke (dabs) onto the backing image.
    if (_base == null) return;
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
    _base?.dispose();
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
        base: _base,
      );
      return isWide
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
    },
  );

  Widget _buildClearFab() => FloatingActionButton.extended(
    onPressed: () async {
      if (_base == null) return; // Early return reduces nesting.
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
  final ui.Image? base;
  const _CanvasArea({
    required this.engine,
    required this.pending,
    required this.pressure,
    required this.nowMs,
    required this.commitStroke,
    required this.base,
  });
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _addPoint(e, reset: true),
          onPointerMove: (e) => _addPoint(e),
          onPointerUp: (e) async {
            _addPoint(e);
            await commitStroke();
          },
          child: AnimatedBuilder(
            animation: engine,
            builder: (_, _) => CustomPaint(
              painter: _PracticePainter(base, engine.live),
              size: size,
            ),
          ),
        );
      },
    );
  }

  void _addPoint(PointerEvent e, {bool reset = false}) {
    if (reset) engine.resetStroke();
    pending.add(
      InputPoint(e.localPosition.dx, e.localPosition.dy, pressure(e), nowMs()),
    );
  }
}

class _PracticePainter extends CustomPainter {
  final ui.Image? base;
  final StrokeLayer live;
  _PracticePainter(this.base, this.live);
  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    // Clear background.
    canvas.drawRect(
      Offset.zero & size,
      ui.Paint()..color = const Color(0xFF111115),
    );
    // Draw committed strokes (scaled to current canvas size).
    if (base != null) {
      final dst = Offset.zero & size;
      final src = ui.Rect.fromLTWH(
        0,
        0,
        base!.width.toDouble(),
        base!.height.toDouble(),
      );
      canvas.drawImageRect(base!, src, dst, ui.Paint());
    }
    // Draw in-progress (live) dabs on top.
    live.draw(canvas);
  }

  @override
  bool shouldRepaint(covariant _PracticePainter old) => true;
}
