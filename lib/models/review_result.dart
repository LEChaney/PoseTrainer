import 'practice_session.dart';

enum ReviewAction { next, end, repeat }

class ReviewResult {
  final ReviewAction action;
  final OverlayTransform overlay;
  final bool save; // whether to persist to history
  const ReviewResult({
    required this.action,
    required this.overlay,
    this.save = true,
  });
}
