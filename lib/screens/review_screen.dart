import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class ReviewScreen extends StatefulWidget {
  final ui.Image? reference; // may be null when only URL available (web)
  final String? referenceUrl; // raw network fallback (web only side-by-side)
  final ui.Image drawing;
  final String sourceUrl;
  const ReviewScreen({
    super.key,
    required this.reference,
    this.referenceUrl,
    required this.drawing,
    required this.sourceUrl,
  });
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool overlay = true;
  double refOpacity = 0.6;
  double drawOpacity = 1.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
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
                const Text('Ref'),
                SizedBox(
                  width: 120,
                  child: Slider(
                    value: refOpacity,
                    min: 0,
                    max: 1,
                    onChanged: (v) => setState(() => refOpacity = v),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Draw'),
                SizedBox(
                  width: 120,
                  child: Slider(
                    value: drawOpacity,
                    min: 0,
                    max: 1,
                    onChanged: (v) => setState(() => drawOpacity = v),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    // If no decoded reference image, force side-by-side with network widget (web fallback)
    if (widget.reference == null) {
      return _SideBySideFallback(
        refUrl: widget.referenceUrl,
        drawImg: widget.drawing,
      );
    }
    if (overlay) {
      return _OverlayCompare(
        refImg: widget.reference!,
        drawImg: widget.drawing,
        refOpacity: refOpacity,
        drawOpacity: drawOpacity,
      );
    }
    return _SideBySideCompare(
      refImg: widget.reference!,
      drawImg: widget.drawing,
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
        Expanded(child: _Fitted(img: refImg, opacity: 1)),
        const VerticalDivider(width: 16, thickness: 1),
        Expanded(child: _Fitted(img: drawImg, opacity: 1)),
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
      size: Size.infinite,
    );
  }
}

class _Fitted extends StatelessWidget {
  final ui.Image img;
  final double opacity;
  const _Fitted({required this.img, required this.opacity});
  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      child: Opacity(
        opacity: opacity,
        child: RawImage(image: img),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final ui.Image refImg, drawImg;
  final double refOpacity, drawOpacity;
  _OverlayPainter(this.refImg, this.drawImg, this.refOpacity, this.drawOpacity);
  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final refRect = _fit(size, refImg);
    final drawRect = _fit(size, drawImg);
    _draw(canvas, refImg, refRect, refOpacity);
    _draw(canvas, drawImg, drawRect, drawOpacity);
  }

  Rect _fit(ui.Size view, ui.Image img) {
    final iw = img.width.toDouble(), ih = img.height.toDouble();
    final scale = (view.width / iw).clamp(0.0, double.infinity);
    final scaledH = ih * scale;
    double s = scale;
    if (scaledH > view.height) {
      s = view.height / ih;
    }
    final w = iw * s, h = ih * s;
    return Rect.fromLTWH((view.width - w) / 2, (view.height - h) / 2, w, h);
  }

  void _draw(ui.Canvas c, ui.Image img, Rect dst, double opacity) {
    final src = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    final p = ui.Paint()
      ..color = Color.fromARGB((opacity * 255).round(), 255, 255, 255);
    c.saveLayer(dst, p);
    c.drawImageRect(img, src, dst, ui.Paint());
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) =>
      old.refImg != refImg ||
      old.drawImg != drawImg ||
      old.refOpacity != refOpacity ||
      old.drawOpacity != drawOpacity;
}

class _SideBySideFallback extends StatelessWidget {
  final String? refUrl;
  final ui.Image drawImg;
  const _SideBySideFallback({required this.refUrl, required this.drawImg});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xFF1A1A1E)),
            child: refUrl != null
                ? Image.network(refUrl!, fit: BoxFit.contain)
                : const Center(
                    child: Text(
                      'No reference',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
          ),
        ),
        const VerticalDivider(width: 16, thickness: 1),
        Expanded(
          child: FittedBox(
            fit: BoxFit.contain,
            child: RawImage(image: drawImg),
          ),
        ),
      ],
    );
  }
}
