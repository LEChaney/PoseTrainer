import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Displays a decoded `ui.Image` centered with aspect ratio preserved and
/// fills any remaining space with the provided background color (reference
/// panel color by default). This ensures *consistent* letterboxing on all
/// screens so bars may appear top/bottom OR left/right depending on aspect.
class LetterboxedImage extends StatelessWidget {
  final ui.Image image;
  final Color background;
  final double opacity;
  const LetterboxedImage({
    super.key,
    required this.image,
    this.background = const Color(0xFF1A1A1E),
    this.opacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LetterboxPainter(image, background, opacity),
      size: Size.infinite,
    );
  }
}

class _LetterboxPainter extends CustomPainter {
  final ui.Image img;
  final Color background;
  final double opacity;
  _LetterboxPainter(this.img, this.background, this.opacity);

  @override
  void paint(Canvas canvas, Size size) {
    // Fill background first so bars show on any side needed.
    final bgPaint = Paint()..color = background;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final iw = img.width.toDouble();
    final ih = img.height.toDouble();
    if (iw <= 0 || ih <= 0 || size.width <= 0 || size.height <= 0) return;

    final sx = size.width / iw;
    final sy = size.height / ih;
    final s = sx < sy ? sx : sy; // contain
    final drawW = iw * s;
    final drawH = ih * s;
    final dx = (size.width - drawW) / 2;
    final dy = (size.height - drawH) / 2;
    final dst = Rect.fromLTWH(dx, dy, drawW, drawH);

    final src = Rect.fromLTWH(0, 0, iw, ih);
    final paint = Paint();
    if (opacity < 1.0) {
      paint.color = Color.fromARGB((opacity * 255).round(), 255, 255, 255);
      canvas.saveLayer(dst, paint);
      canvas.drawImageRect(img, src, dst, Paint());
      canvas.restore();
    } else {
      canvas.drawImageRect(img, src, dst, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LetterboxPainter old) =>
      old.img != img || old.background != background || old.opacity != opacity;
}
