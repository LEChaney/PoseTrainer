import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import '../models/practice_session.dart';

// session_service.dart
// --------------------
// Stores completed practice sessions in memory (list kept newest-first). No
// persistence yet—when the app restarts the history clears. In the future we
// can extend this to serialize to disk or a database with minimal changes.

class SessionService extends ChangeNotifier {
  final List<PracticeSession> _history = [];
  // Expose an unmodifiable view so external code can't mutate list directly.
  List<PracticeSession> get history => List.unmodifiable(_history);

  /// Add a finished session to the top of the history.
  void add(String sourceUrl, ui.Image reference, ui.Image drawing) {
    _history.insert(
      0,
      PracticeSession(
        sourceUrl: sourceUrl,
        reference: reference,
        drawing: drawing,
        endedAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }
}
