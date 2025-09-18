/// Prototype: First playable (search -> practice -> review) extracted from conversation.
/// Includes:
/// - e621 tag search (basic, no pagination)
/// - Drawing surface (brush pipeline as in minimal prototype)
/// - Review screen with overlay + side-by-side + opacity sliders
/// - In-memory session history
///
/// WARNING: Reference-only snapshot. Not integrated with production app structure.
/// Remove any unused portions or migrate into services before real adoption.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;

// =======================================================
// Models & session DTOs
// =======================================================

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
  final double x, y, pressure; // pressure 0..1
  final int tMs;
  const InputPoint(this.x, this.y, this.pressure, this.tMs);
}

class PracticeSession {
  final String sourceUrl;
  final ui.Image reference;
  final ui.Image drawing;
  final DateTime endedAt;
  PracticeSession({
    required this.sourceUrl,
    required this.reference,
    required this.drawing,
    required this.endedAt,
  });
}

final List<PracticeSession> kHistory = [];

// =======================================================
// One-Euro smoothing
// =======================================================

class OneEuro {
  double freq;
  double minCutoff;
  double beta;
  double dCutoff;

  _LowPass _x = _LowPass();
  _LowPass _dx = _LowPass();
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
  final double alpha; // flow * opacity
  final double hardness;

  Dab(this.center, this.radius, this.alpha, this.hardness);
}

class BrushEmitter {
  final BrushParams params;
  final OneEuro fx = OneEuro();
  final OneEuro fy = OneEuro();
  final OneEuro fp = OneEuro(minCutoff: 1.0, beta: 0.02, dCutoff: 1.0);

  double? _lastEmitX;
  double? _lastEmitY;

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
        final dx = sx - _lastEmitX!;
        final dy = sy - _lastEmitY!;
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

// =======================================================
// Rendering Layers
// =======================================================

class StrokeLayer {
  final List<RSTransform> _xforms = [];
  final List<Rect> _src = [];
  final List<Color> _colors = [];

  ui.Image? dabSprite;

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
    final scale = (d.radius / 64.0) * 2.0; // sprite radius 64
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
    const a = Color(0xFF1B1B22);
    const b = Color(0xFF15151B);
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

// =======================================================
// e621 Search Screen
// =======================================================

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController(
    text: 'rating:safe canine standing -animated',
  );
  List<_E6Post> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
      _results = [];
    });
    try {
      final tags = _controller.text.trim().replaceAll(RegExp(r'\s+'), '+');
      final uri = Uri.parse('https://e621.net/posts.json?limit=40&tags=$tags');
      final resp = await http.get(
        uri,
        headers: {
          'User-Agent': 'PoseTrainerPrototype/0.1 (contact: you@example.com)',
        },
      );
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final posts = (data['posts'] as List? ?? [])
          .map((j) => _E6Post.fromJson(j as Map<String, dynamic>))
          .where((p) => p.previewUrl != null)
          .toList();
      setState(() => _results = posts);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('e621 Search'),
        backgroundColor: const Color(0xFF16161C),
      ),
      backgroundColor: const Color(0xFF0F0F13),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'e621 tags',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF1B1B22),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _search,
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Search'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final p = _results[i];
                return GestureDetector(
                  onTap: () async {
                    final fullUrl = p.sampleUrl ?? p.fileUrl ?? p.previewUrl!;
                    final img = await _fetchUiImage(fullUrl);
                    if (!context.mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PracticePage(
                          reference: img,
                          sourceUrl: p.postPageUrl,
                        ),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(p.previewUrl!, fit: BoxFit.cover),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${p.score}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: kHistory.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const HistoryScreen())),
              label: const Text('History'),
              icon: const Icon(Icons.history),
            ),
    );
  }
}

class _E6Post {
  final String? previewUrl, sampleUrl, fileUrl;
  final int score;
  final int id;
  _E6Post({
    this.previewUrl,
    this.sampleUrl,
    this.fileUrl,
    required this.id,
    required this.score,
  });
  String get postPageUrl => "https://e621.net/posts/$id";
  factory _E6Post.fromJson(Map<String, dynamic> j) {
    String? s(Map m, String k) => m[k] is String ? m[k] as String : null;
    final file = (j['file'] as Map?) ?? {};
    final sample = (j['sample'] as Map?) ?? {};
    final preview = (j['preview'] as Map?) ?? {};
    return _E6Post(
      previewUrl: s(preview, 'url'),
      sampleUrl: s(sample, 'url'),
      fileUrl: s(file, 'url'),
      id: (j['id'] as num?)?.toInt() ?? 0,
      score: ((j['score'] as Map?)?['total'] as num?)?.toInt() ?? 0,
    );
  }
}

Future<ui.Image> _fetchUiImage(String url) async {
  final resp = await http.get(
    Uri.parse(url),
    headers: {
      'User-Agent': 'PoseTrainerPrototype/0.1 (contact: you@example.com)',
    },
  );
  if (resp.statusCode != 200) {
    throw Exception("Image ${resp.statusCode}");
  }
  final codec = await ui.instantiateImageCodec(resp.bodyBytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

// =======================================================
// Practice Page
// =======================================================

class PracticePage extends StatefulWidget {
  final ui.Image reference;
  final String sourceUrl;
  const PracticePage({
    super.key,
    required this.reference,
    required this.sourceUrl,
  });

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage>
    with SingleTickerProviderStateMixin {
  final brush = const BrushParams(
    name: 'SAI Round',
    sizePx: 18,
    spacing: 0.12,
    flow: 0.7,
    hardness: 0.8,
    opacity: 1.0,
    pressureSize: 0.9,
    pressureFlow: 0.7,
  );

  late BrushEmitter emitter;
  final live = StrokeLayer();
  ui.Image? baseImage;
  late Ticker _ticker;
  final _pending = <InputPoint>[];

  @override
  void initState() {
    super.initState();
    emitter = BrushEmitter(brush);
    _initBaseLayer(widget.reference.width, widget.reference.height);
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _initBaseLayer(int w, int h) async {
    final recorder = ui.PictureRecorder();
    // allocate transparent base
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

  Future<void> _finishAndReview() async {
    await _commitStroke();
    if (baseImage == null) return;
    final session = PracticeSession(
      sourceUrl: widget.sourceUrl,
      reference: widget.reference,
      drawing: baseImage!,
      endedAt: DateTime.now(),
    );
    kHistory.insert(0, session);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ReviewScreen(session: session)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice'),
        backgroundColor: const Color(0xFF16161C),
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => _ReferenceDialog(img: widget.reference),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const HistoryScreen()));
            },
          ),
        ],
      ),
      backgroundColor: const Color(0xFF0F0F13),
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
            onPointerCancel: (_) async => await _commitStroke(),
            child: CustomPaint(
              painter: BrushCanvasPainter(baseImage, live),
              size: size,
            ),
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            icon: const Icon(Icons.undo),
            label: const Text('Clear'),
            onPressed: () async {
              if (baseImage == null) return;
              await _initBaseLayer(baseImage!.width, baseImage!.height);
            },
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            icon: const Icon(Icons.check),
            label: const Text('Finish'),
            onPressed: _finishAndReview,
          ),
        ],
      ),
    );
  }
}

class _ReferenceDialog extends StatelessWidget {
  final ui.Image img;
  const _ReferenceDialog({required this.img});
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F0F13),
      child: AspectRatio(
        aspectRatio: img.width / img.height,
        child: RawImage(image: img, fit: BoxFit.contain),
      ),
    );
  }
}

// =======================================================
// Review Screen
// =======================================================

class ReviewScreen extends StatefulWidget {
  final PracticeSession session;
  const ReviewScreen({super.key, required this.session});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool overlay = true;
  double refOpacity = 0.6;
  double drawOpacity = 1.0;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review'),
        backgroundColor: const Color(0xFF16161C),
      ),
      backgroundColor: const Color(0xFF0F0F13),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Overlay')),
                    ButtonSegment(value: false, label: Text('Side-by-side')),
                  ],
                  selected: {overlay},
                  onSelectionChanged: (v) => setState(() => overlay = v.first),
                ),
                const Spacer(),
                const Text('Ref', style: TextStyle(color: Colors.white70)),
                SizedBox(
                  width: 140,
                  child: Slider(
                    value: refOpacity,
                    onChanged: (v) => setState(() => refOpacity = v),
                    min: 0,
                    max: 1,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Draw', style: TextStyle(color: Colors.white70)),
                SizedBox(
                  width: 140,
                  child: Slider(
                    value: drawOpacity,
                    onChanged: (v) => setState(() => drawOpacity = v),
                    min: 0,
                    max: 1,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: overlay
                  ? _OverlayCompare(
                      refImg: s.reference,
                      drawImg: s.drawing,
                      refOpacity: refOpacity,
                      drawOpacity: drawOpacity,
                    )
                  : _SideBySideCompare(refImg: s.reference, drawImg: s.drawing),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Row(
            children: [
              FilledButton.tonal(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const SearchScreen()),
                    (_) => false,
                  );
                },
                child: const Text('New Search'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  );
                },
                child: const Text('History'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideBySideCompare extends StatelessWidget {
  final ui.Image refImg, drawImg;
  const _SideBySideCompare({required this.refImg, required this.drawImg});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: refImg.width / refImg.height,
              child: RawImage(image: refImg, fit: BoxFit.contain),
            ),
          ),
        ),
        const VerticalDivider(color: Colors.white12, width: 20, thickness: 1),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: drawImg.width / drawImg.height,
              child: RawImage(image: drawImg, fit: BoxFit.contain),
            ),
          ),
        ),
      ],
    );
  }
}

class _OverlayCompare extends StatelessWidget {
  final ui.Image refImg, drawImg;
  final double refOpacity, drawOpacity;
  const _OverlayCompare({
    required this.refImg,
    required this.drawImg,
    required this.refOpacity,
    required this.drawOpacity,
  });
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OverlayPainter(refImg, drawImg, refOpacity, drawOpacity),
      child: const SizedBox.expand(),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final ui.Image refImg, drawImg;
  final double refOpacity, drawOpacity;
  _OverlayPainter(this.refImg, this.drawImg, this.refOpacity, this.drawOpacity);
  @override
  void paint(Canvas canvas, Size size) {
    final dst = _fitContain(
      size,
      refImg.width.toDouble(),
      refImg.height.toDouble(),
    );
    _drawImageFitted(canvas, refImg, dst, refOpacity);
    _drawImageFitted(canvas, drawImg, dst, drawOpacity);
  }

  Rect _fitContain(Size view, double iw, double ih) {
    final vr = view.width / view.height;
    final ir = iw / ih;
    double w, h;
    if (ir > vr) {
      w = view.width;
      h = w / ir;
    } else {
      h = view.height;
      w = h * ir;
    }
    final dx = (view.width - w) * 0.5;
    final dy = (view.height - h) * 0.5;
    return Rect.fromLTWH(dx, dy, w, h);
  }

  void _drawImageFitted(Canvas c, ui.Image img, Rect dst, double opacity) {
    final src = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    final p = Paint()..color = Colors.white.withValues(alpha: opacity);
    c.saveLayer(dst, p);
    c.drawImageRect(img, src, dst, Paint());
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) =>
      old.refImg != refImg ||
      old.drawImg != drawImg ||
      old.refOpacity != refOpacity ||
      old.drawOpacity != drawOpacity;
}

// =======================================================
// History Screen
// =======================================================

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        backgroundColor: const Color(0xFF16161C),
      ),
      backgroundColor: const Color(0xFF0F0F13),
      body: kHistory.isEmpty
          ? const Center(
              child: Text(
                'No sessions yet.',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView.separated(
              itemCount: kHistory.length,
              separatorBuilder: (_, _) =>
                  const Divider(color: Colors.white12, height: 1),
              itemBuilder: (_, i) {
                final s = kHistory[i];
                return ListTile(
                  tileColor: const Color(0xFF121218),
                  title: Text(
                    s.sourceUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${s.endedAt.toLocal()}'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ReviewScreen(session: s)),
                  ),
                );
              },
            ),
    );
  }
}

// =======================================================
// Utilities
// =======================================================

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

// Entry point for this prototype only.
void runFirstPlayablePrototype() {
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: SearchScreen()),
  );
}
