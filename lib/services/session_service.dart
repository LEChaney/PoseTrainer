import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import '../models/practice_session.dart';

/// Manages in-memory session history for now.
class SessionService extends ChangeNotifier {
  final List<PracticeSession> _history = [];
  List<PracticeSession> get history => List.unmodifiable(_history);

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
