import 'dart:ui' as ui;

/// Pan/zoom transform persisted from the review overlay.
class OverlayTransform {
  final double scale;
  final ui.Offset offset;
  const OverlayTransform({required this.scale, required this.offset});

  OverlayTransform copyWith({double? scale, ui.Offset? offset}) =>
      OverlayTransform(
        scale: scale ?? this.scale,
        offset: offset ?? this.offset,
      );
}

// practice_session.dart
// ---------------------
// Represents one completed drawing attempt: the reference image used and the
// final user drawing captured as a bitmap. We keep this immutable so it can be
// safely stored in a list and passed around without worrying about it changing.

/// Immutable session pairing a reference image (decoded or URL) with the
/// resulting drawing and the last-used review overlay transform.
class PracticeSession {
  /// URL the reference came from (useful for attribution / reloading later).
  final String sourceUrl;

  /// The decoded reference image (available on native when we decoded).
  final ui.Image? reference;

  /// The reference URL (used on web when decoding wasn't possible).
  final String? referenceUrl;

  /// The final drawing committed when the user finished the practice.
  final ui.Image drawing;

  /// Timestamp when the session ended (local time).
  final DateTime endedAt;

  /// Last used overlay transform in review for quick revisit.
  final OverlayTransform overlay;
  const PracticeSession({
    required this.sourceUrl,
    required this.reference,
    required this.referenceUrl,
    required this.drawing,
    required this.endedAt,
    required this.overlay,
  });

  PracticeSession copyWith({
    String? sourceUrl,
    ui.Image? reference,
    String? referenceUrl,
    ui.Image? drawing,
    DateTime? endedAt,
    OverlayTransform? overlay,
  }) => PracticeSession(
    sourceUrl: sourceUrl ?? this.sourceUrl,
    reference: reference ?? this.reference,
    referenceUrl: referenceUrl ?? this.referenceUrl,
    drawing: drawing ?? this.drawing,
    endedAt: endedAt ?? this.endedAt,
    overlay: overlay ?? this.overlay,
  );
}
