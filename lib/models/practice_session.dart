import 'dart:ui' as ui;

/// Immutable session pairing a reference image with the resulting drawing.
class PracticeSession {
  final String sourceUrl;
  final ui.Image reference;
  final ui.Image drawing;
  final DateTime endedAt;
  const PracticeSession({
    required this.sourceUrl,
    required this.reference,
    required this.drawing,
    required this.endedAt,
  });
}
