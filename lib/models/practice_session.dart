import 'dart:ui' as ui;

// practice_session.dart
// ---------------------
// Represents one completed drawing attempt: the reference image used and the
// final user drawing captured as a bitmap. We keep this immutable so it can be
// safely stored in a list and passed around without worrying about it changing.

/// Immutable session pairing a reference image with the resulting drawing.
class PracticeSession {
  /// URL the reference came from (useful for attribution / reloading later).
  final String sourceUrl;

  /// The decoded reference image (only available on native platforms right now).
  final ui.Image reference;

  /// The final drawing committed when the user finished the practice.
  final ui.Image drawing;

  /// Timestamp when the session ended (local time).
  final DateTime endedAt;
  const PracticeSession({
    required this.sourceUrl,
    required this.reference,
    required this.drawing,
    required this.endedAt,
  });
}
