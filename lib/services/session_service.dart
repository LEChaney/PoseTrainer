import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/practice_session.dart';
import 'session_repository.dart';
import 'binary_store.dart';
import 'debug_logger.dart';

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
    infoLog(
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
    String? driveFileId, // Drive file ID for re-downloading full image later
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

    // Create thumbnail for reference image if provided
    ui.Image? refThumb;
    Uint8List? refThumbPng;
    if (reference != null) {
      refThumb = await _createThumbnail(reference, maxDimension: 256);
      final refData = await refThumb.toByteData(format: ui.ImageByteFormat.png);
      refThumbPng = refData!.buffer.asUint8List();
      // Decode thumbnail for immediate in-memory use
      refThumb = await _decodeUiImage(refThumbPng);
    }

    final session = PracticeSession(
      sourceUrl: sourceUrl,
      reference: refThumb, // Use thumbnail in memory
      referenceUrl: referenceUrl,
      driveFileId: driveFileId, // Include Drive file ID for on-demand loading
      drawing: historyImage,
      endedAt: endedAt,
      overlay: overlay,
    );
    _history.insert(0, session);
    notifyListeners();
    // ignore: avoid_print
    infoLog(
      '[Svc] add: id=${endedAt.millisecondsSinceEpoch} inserted historyCount=${_history.length}',
    );
    final id = endedAt.millisecondsSinceEpoch.toString();
    String? drawPath;
    String? refPath;
    Uint8List drawToPersist = png;
    Uint8List refToPersist = refThumbPng ?? Uint8List(0);

    // Try OPFS (web) or fallback
    final bin = createBinaryStore();
    if (await bin.isAvailable()) {
      // Store drawing
      final drawCandidate = 'sessions/$id.png';
      try {
        await bin.write(drawCandidate, png);
        drawPath = drawCandidate;
        drawToPersist = Uint8List(0); // do not duplicate in Hive
        // ignore: avoid_print
        infoLog(
          '[Svc] add: wrote drawing $drawCandidate (backend: ${bin.runtimeType})',
        );
      } catch (_) {
        drawPath = null;
      }

      // Store reference thumbnail if available
      if (refThumbPng != null && refThumbPng.isNotEmpty) {
        final refCandidate = 'sessions/${id}_ref.png';
        try {
          await bin.write(refCandidate, refThumbPng);
          refPath = refCandidate;
          refToPersist = Uint8List(0); // do not duplicate in Hive
          // ignore: avoid_print
          infoLog('[Svc] add: wrote reference thumbnail $refCandidate');
        } catch (_) {
          refPath = null;
        }
      }
    }

    final stored = await SessionCodec.toStored(
      session,
      id,
      drawToPersist,
      drawingPath: drawPath,
      driveFileId: driveFileId,
      referenceThumbnail: refToPersist,
      referencePath: refPath,
    );
    await _repo.save(stored);
  }

  /// Create a downscaled thumbnail of an image.
  Future<ui.Image> _createThumbnail(
    ui.Image source, {
    required int maxDimension,
  }) async {
    final width = source.width;
    final height = source.height;

    // Calculate scale to fit within maxDimension
    final scale = (width > height)
        ? maxDimension / width
        : maxDimension / height;

    // Don't upscale
    if (scale >= 1.0) return source;

    final newWidth = (width * scale).round();
    final newHeight = (height * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Draw scaled image
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Rect.fromLTWH(0, 0, newWidth.toDouble(), newHeight.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );

    final picture = recorder.endRecording();
    return await picture.toImage(newWidth, newHeight);
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
