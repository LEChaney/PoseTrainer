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
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background letterbox color
        ColoredBox(color: background),
        // Image with contain fit for aspect-preserving scaling
        Opacity(
          opacity: opacity,
          child: RawImage(image: image, fit: BoxFit.contain),
        ),
      ],
    );
  }
}
