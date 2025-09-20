import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/practice_session.dart';
import 'session_repository.dart';
import 'binary_store.dart';

// session_service.dart
// --------------------
// Stores completed practice sessions in memory (list kept newest-first). No
// persistence yet—when the app restarts the history clears. In the future we
// can extend this to serialize to disk or a database with minimal changes.

class SessionService extends ChangeNotifier {
  final SessionRepository _repo;
  final List<PracticeSession> _history = [];
  SessionService(this._repo);
  // Expose an unmodifiable view so external code can't mutate list directly.
  List<PracticeSession> get history => List.unmodifiable(_history);

  /// Initialize repository and load existing sessions from storage.
  Future<void> init() async {
    await _repo.init();
    final stored = await _repo.loadAll();
    final decoded = <PracticeSession>[];
    for (final ss in stored) {
      try {
        decoded.add(await SessionCodec.fromStored(ss));
      } catch (_) {
        // Skip corrupted/undecodable entries without nuking in-memory state.
      }
    }
    // Merge with any in-memory sessions (e.g. if a user finished a session
    // while init() was still loading). Keep newest-first and dedupe by ID.
    final merged = _mergeSessions(decoded, _history);
    // ignore: avoid_print
    print(
      '[Svc] init: loaded=${decoded.length} inMemory=${_history.length} merged=${merged.length}',
    );
    _history
      ..clear()
      ..addAll(merged);
    notifyListeners();
  }

  /// Reloads sessions from persistence without touching repository init.
  Future<void> reload() async {
    final stored = await _repo.loadAll();
    final decoded = <PracticeSession>[];
    for (final ss in stored) {
      try {
        decoded.add(await SessionCodec.fromStored(ss));
      } catch (_) {}
    }
    _history
      ..clear()
      ..addAll(decoded);
    notifyListeners();
  }

  List<PracticeSession> _mergeSessions(
    List<PracticeSession> a,
    List<PracticeSession> b,
  ) {
    final byId = <String, PracticeSession>{};
    void addAll(List<PracticeSession> src) {
      for (final s in src) {
        final id = s.endedAt.millisecondsSinceEpoch.toString();
        // Prefer existing entry if duplicate so we preserve decoded refs.
        byId.putIfAbsent(id, () => s);
      }
    }

    // Preserve current in-memory over loaded on conflicts
    addAll(a);
    addAll(b);
    final list = byId.values.toList();
    list.sort((x, y) => y.endedAt.compareTo(x.endedAt));
    return list;
  }

  /// Clears in-memory history immediately (does not touch persistent storage).
  void clear() {
    _history.clear();
    notifyListeners();
  }

  /// Add a finished session to the top of the history and persist it.
  Future<void> add({
    required String sourceUrl,
    ui.Image? reference,
    String? referenceUrl,
    required ui.Image drawing,
    OverlayTransform overlay = const OverlayTransform(
      scale: 1.0,
      offset: ui.Offset.zero,
    ),
  }) async {
    final endedAt = DateTime.now();
    // Encode drawing to PNG bytes once, then decode a stable copy for History.
    // This avoids potential volatility of freshly rendered GPU-backed images
    // (particularly on web/canvaskit) that could disappear until reload.
    final data = await drawing.toByteData(format: ui.ImageByteFormat.png);
    final png = data!.buffer.asUint8List();
    final historyImage = await _decodeUiImage(png);

    final session = PracticeSession(
      sourceUrl: sourceUrl,
      reference: reference,
      referenceUrl: referenceUrl,
      drawing: historyImage,
      endedAt: endedAt,
      overlay: overlay,
    );
    _history.insert(0, session);
    notifyListeners();
    // ignore: avoid_print
    print(
      '[Svc] add: id=${endedAt.millisecondsSinceEpoch} inserted historyCount=${_history.length}',
    );
    final id = endedAt.millisecondsSinceEpoch.toString();
    String? path;
    Uint8List toPersist = png;
    // Try OPFS (web) or fallback
    final bin = createBinaryStore();
    if (await bin.isAvailable()) {
      final candidate = 'sessions/$id.png';
      try {
        await bin.write(candidate, png);
        path = candidate;
        toPersist = Uint8List(0); // do not duplicate in Hive
        // ignore: avoid_print
        print('[Svc] add: wrote OPFS $candidate');
      } catch (_) {
        // keep Hive bytes if OPFS write failed
        path = null;
      }
    }
    final stored = await SessionCodec.toStored(
      session,
      id,
      toPersist,
      drawingPath: path,
    );
    await _repo.save(stored);
  }

  /// Update the most recent session's saved overlay transform (after review adjustments).
  void updateLastOverlay(OverlayTransform transform) {
    if (_history.isEmpty) return;
    final updated = _history[0].copyWith(overlay: transform);
    _history[0] = updated;
    // Persist overlay for the stored record. We use endedAt as ID key.
    final id = updated.endedAt.millisecondsSinceEpoch.toString();
    _repo.updateOverlay(id, transform);
    notifyListeners();
  }
}

Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
  final comp = Completer<ui.Image>();
  ui.decodeImageFromList(bytes, comp.complete);
  return comp.future;
}
