/// Prototype: Minimal Flutter brush demo (extracted from original ChatGPT conversation)
/// Purpose: Reference-only. Not wired into main app. Shows pure Flutter low-latency
/// brush pipeline using drawAtlas + One-Euro smoothing + dab spacing.
///
/// Keep this file OUT of production imports to avoid dead code / size impact.
/// If you reuse parts, migrate logic into proper services under lib/.
///
/// Notes:
/// - Single round soft brush
/// - Base layer + live stroke layer
/// - One-Euro filter per axis + pressure
/// - Dabs batched per frame (Ticker) -> one drawAtlas call
/// - No persistence / undo / zoom
///
/// To run standalone, you could copy into a `bin/` Dart/Flutter project main or
/// temporarily replace your `lib/main.dart` while experimenting.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: DemoPage()),
  );
}

// ---------------------- Brush + Filtering Core ----------------------

class BrushParams {
  final String name;
  final double sizePx; // base diameter
  final double spacing; // in diameters (e.g., 0.12)
  final double flow; // 0..1
  final double hardness; // 0 (soft) .. 1 (hard)
  final double opacity; // 0..1
  final double pressureSize; // 0..1 scaling strength
  final double pressureFlow; // 0..1 scaling strength
  const BrushParams({
    required this.name,
    this.sizePx = 18,
    this.spacing = 0.12,
    this.flow = 0.7,
    this.hardness = 0.8,
    this.opacity = 1.0,
    this.pressureSize = 0.9,
    this.pressureFlow = 0.7,
  });
}

class InputPoint {
  final double x, y, pressure; // pressure is 0..1
  final int tMs;
  const InputPoint(this.x, this.y, this.pressure, this.tMs);
}

class OneEuro {
  double freq; // Hz, updated from timestamps
  double minCutoff; // ~1.0
  double beta; // ~0.015
  double dCutoff; // ~1.0
  _LowPass _x = _LowPass(), _dx = _LowPass();
  int? _lastMs;
  OneEuro({
    this.freq = 120,
    this.minCutoff = 1.0,
    this.beta = 0.015,
    this.dCutoff = 1.0,
  });
  double filter(double value, int tMs) {
    if (_lastMs != null) {
      final dt = (tMs - _lastMs!).clamp(1, 1000);
      freq = 1000.0 / dt;
    }
    _lastMs = tMs;
    final ed = _dx.filter((value - _x.last) * freq, _alpha(dCutoff));
    final cutoff = minCutoff + beta * ed.abs();
    return _x.filter(value, _alpha(cutoff));
  }

  double _alpha(double cutoff) {
    final te = 1.0 / freq.clamp(1e-3, 1e9);
    final tau = 1.0 / (2 * math.pi * cutoff.clamp(1e-3, 1e9));
    return 1.0 / (1.0 + tau / te);
  }
}

class _LowPass {
  double _y = 0.0;
  bool _init = false;
  double get last => _y;
  double filter(double x, double a) {
    if (!_init) {
      _y = x;
      _init = true;
    }
    _y = _y + a.clamp(0, 1) * (x - _y);
    return _y;
  }
}

class Dab {
  final Offset center;
  final double radius; // px
  final double alpha; // 0..1 (flow * opacity)
  final double hardness; // 0..1
  Dab(this.center, this.radius, this.alpha, this.hardness);
}

/// Emits evenly spaced dabs from raw pointer input using One-Euro smoothing.
class BrushEmitter {
  final BrushParams params;
  final OneEuro fx = OneEuro();
  final OneEuro fy = OneEuro();
  final OneEuro fp = OneEuro(minCutoff: 1.0, beta: 0.02, dCutoff: 1.0);
  double? _lastEmitX, _lastEmitY;
  BrushEmitter(this.params);
  void reset() {
    _lastEmitX = null;
    _lastEmitY = null;
    fx._lastMs = null;
    fy._lastMs = null;
    fp._lastMs = null;
    fx._x = _LowPass();
    fx._dx = _LowPass();
    fy._x = _LowPass();
    fy._dx = _LowPass();
    fp._x = _LowPass();
    fp._dx = _LowPass();
  }

  Iterable<Dab> addPoints(Iterable<InputPoint> pts) sync* {
    for (final p in pts) {
      final sx = fx.filter(p.x, p.tMs);
      final sy = fy.filter(p.y, p.tMs);
      final sp = fp.filter(p.pressure.clamp(0, 1), p.tMs).clamp(0, 1);
      final diameter =
          params.sizePx * (1.0 + params.pressureSize * (sp - 0.5) * 2.0);
      final spacingPx = (params.spacing.clamp(0.01, 1.0)) * diameter;
      final flow = (params.flow + params.pressureFlow * (sp - 0.5) * 2.0).clamp(
        0.0,
        1.0,
      );
      final emit = () {
        if (_lastEmitX == null) return true;
        final dx = sx - _lastEmitX!, dy = sy - _lastEmitY!;
        return (dx * dx + dy * dy) >= spacingPx * spacingPx;
      }();
      if (emit) {
        _lastEmitX = sx;
        _lastEmitY = sy;
        yield Dab(
          Offset(sx, sy),
          diameter * 0.5,
          flow * params.opacity,
          params.hardness,
        );
      }
    }
  }
}

// ---------------------- Rendering Layers ----------------------

class StrokeLayer {
  final List<RSTransform> _xforms = [];
  final List<Rect> _src = [];
  final List<Color> _colors = [];
  ui.Image? dabSprite; // 128x128 soft disc alpha
  Future<void> ensureSprite(double hardness) async {
    if (dabSprite != null) return;
    dabSprite = await _makeSoftDiscSprite(128, hardness);
  }

  void clear() {
    _xforms.clear();
    _src.clear();
    _colors.clear();
  }

  void addDab(Dab d) {
    final src = Rect.fromLTWH(0, 0, 128, 128);
    final scale = (d.radius / 64.0) * 2.0; // sprite radius 64 => target radius
    final xf = RSTransform.fromComponents(
      rotation: 0,
      scale: scale,
      anchorX: 64,
      anchorY: 64,
      translateX: d.center.dx,
      translateY: d.center.dy,
    );
    _xforms.add(xf);
    _src.add(src);
    _colors.add(Colors.white.withValues(alpha: d.alpha));
  }

  void draw(Canvas c) {
    if (dabSprite == null) return;
    final paint = Paint()..filterQuality = FilterQuality.low;
    c.drawAtlas(
      dabSprite!,
      _xforms,
      _src,
      _colors,
      BlendMode.srcOver,
      null,
      paint,
    );
  }
}

class BrushCanvasPainter extends CustomPainter {
  final ui.Image? baseLayer;
  final StrokeLayer liveLayer;
  BrushCanvasPainter(this.baseLayer, this.liveLayer);
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF0E0E12);
    canvas.drawRect(Offset.zero & size, bg);
    _drawChecker(canvas, size);
    if (baseLayer != null) {
      final dst = Offset.zero & size;
      final src = Rect.fromLTWH(
        0,
        0,
        baseLayer!.width.toDouble(),
        baseLayer!.height.toDouble(),
      );
      canvas.drawImageRect(baseLayer!, src, dst, Paint());
    }
    liveLayer.draw(canvas);
  }

  @override
  bool shouldRepaint(covariant BrushCanvasPainter old) => true;
  void _drawChecker(Canvas c, Size s) {
    const a = Color(0xFF1B1B22), b = Color(0xFF15151B);
    const cell = 24.0;
    final p = Paint();
    for (double y = 0; y < s.height; y += cell) {
      for (double x = 0; x < s.width; x += cell) {
        final even = (((x / cell).floor() + (y / cell).floor()) & 1) == 0;
        p.color = even ? a : b;
        c.drawRect(Rect.fromLTWH(x, y, cell, cell), p);
      }
    }
  }
}

// ---------------------- Demo Page ----------------------

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});
  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage>
    with SingleTickerProviderStateMixin {
  final brush = const BrushParams(name: "SAI Round");
  late BrushEmitter emitter;
  final live = StrokeLayer();
  ui.Image? baseImage;
  late Ticker _ticker;
  final _pending = <InputPoint>[];
  @override
  void initState() {
    super.initState();
    emitter = BrushEmitter(brush);
    _initBaseLayer(1920, 1200);
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _initBaseLayer(int w, int h) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    final pic = recorder.endRecording();
    baseImage = await pic.toImage(w, h);
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    baseImage?.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    if (_pending.isEmpty) return;
    for (final d in emitter.addPoints(_pending)) {
      live.addDab(d);
    }
    _pending.clear();
    setState(() {});
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;
  double _normalizePressure(PointerEvent e) {
    final min = e.pressureMin, max = e.pressureMax;
    final denom = (max - min);
    if (denom == 0) return 0.5;
    final v = ((e.pressure - min) / denom).clamp(0.0, 1.0);
    return v.isFinite ? v : 0.5;
  }

  Future<void> _commitStroke() async {
    if (baseImage == null) return;
    final w = baseImage!.width, h = baseImage!.height;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.drawImage(baseImage!, Offset.zero, Paint());
    live.draw(canvas);
    final pic = rec.endRecording();
    final merged = await pic.toImage(w, h);
    baseImage!.dispose();
    baseImage = merged;
    live.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (_, c) {
          final size = Size(c.maxWidth, c.maxHeight);
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) async {
              emitter.reset();
              await live.ensureSprite(brush.hardness);
              live.clear();
              _pending.add(
                InputPoint(
                  e.localPosition.dx,
                  e.localPosition.dy,
                  _normalizePressure(e),
                  _nowMs(),
                ),
              );
            },
            onPointerMove: (e) => _pending.add(
              InputPoint(
                e.localPosition.dx,
                e.localPosition.dy,
                _normalizePressure(e),
                _nowMs(),
              ),
            ),
            onPointerUp: (e) async {
              _pending.add(
                InputPoint(
                  e.localPosition.dx,
                  e.localPosition.dy,
                  _normalizePressure(e),
                  _nowMs(),
                ),
              );
              await _commitStroke();
            },
            onPointerCancel: (_) async {
              await _commitStroke();
            },
            child: CustomPaint(
              painter: BrushCanvasPainter(baseImage, live),
              size: size,
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        label: const Text('Clear'),
        onPressed: () async {
          if (baseImage == null) return;
          await _initBaseLayer(baseImage!.width, baseImage!.height);
        },
      ),
    );
  }
}

// ---------------------- Sprite generator (soft disc) ----------------------

Future<ui.Image> _makeSoftDiscSprite(int size, double hardness) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));
  final center = Offset(size / 2, size / 2);
  final r = size / 2.0;
  final stops = [0.0, (hardness.clamp(0.0, 1.0) * 0.85), 1.0];
  final colors = [
    Colors.white,
    Colors.white,
    Colors.white.withValues(alpha: 0.0),
  ];
  final shader = ui.Gradient.radial(center, r, colors, stops, TileMode.clamp);
  final p = Paint()..shader = shader;
  c.drawCircle(center, r, p);
  final pic = rec.endRecording();
  return pic.toImage(size, size);
}
