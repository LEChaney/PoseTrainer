import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../models/practice_session.dart';
import 'binary_store.dart';
import 'debug_logger.dart';

/// Serial form stored on disk/IndexedDB. Keeps bytes & minimal metadata.
@immutable
class StoredSession {
  final String id;
  final String sourceUrl;
  final String? referenceUrl;
  final Uint8List drawingPng;
  final String? drawingPath; // when using OPFS
  final int endedAtMs;
  final double overlayScale;
  final double overlayDx;
  final double overlayDy;

  const StoredSession({
    required this.id,
    required this.sourceUrl,
    required this.referenceUrl,
    required this.drawingPng,
    this.drawingPath,
    required this.endedAtMs,
    required this.overlayScale,
    required this.overlayDx,
    required this.overlayDy,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'sourceUrl': sourceUrl,
    'referenceUrl': referenceUrl,
    'drawingPng': drawingPng,
    'drawingPath': drawingPath,
    'endedAtMs': endedAtMs,
    'overlayScale': overlayScale,
    'overlayDx': overlayDx,
    'overlayDy': overlayDy,
  };

  factory StoredSession.fromMap(Map map) => StoredSession(
    id: map['id'] as String,
    sourceUrl: map['sourceUrl'] as String,
    referenceUrl: map['referenceUrl'] as String?,
    drawingPng: (map['drawingPng'] is Uint8List)
        ? map['drawingPng'] as Uint8List
        : Uint8List(0),
    drawingPath: map['drawingPath'] as String?,
    endedAtMs: (map['endedAtMs'] as num).toInt(),
    overlayScale: (map['overlayScale'] as num).toDouble(),
    overlayDx: (map['overlayDx'] as num).toDouble(),
    overlayDy: (map['overlayDy'] as num).toDouble(),
  );
}

/// Abstraction for session persistence. Keep UI/services independent of storage.
abstract class SessionRepository {
  Future<void> init();
  Future<List<StoredSession>> loadAll();
  Future<void> save(StoredSession session);
  Future<void> updateOverlay(String id, OverlayTransform overlay);
}

/// Utilities to convert between in-memory `PracticeSession` and `StoredSession`.
class SessionCodec {
  static Future<StoredSession> toStored(
    PracticeSession s,
    String id,
    Uint8List drawingPng, {
    String? drawingPath,
  }) async {
    return StoredSession(
      id: id,
      sourceUrl: s.sourceUrl,
      referenceUrl: s.referenceUrl,
      drawingPng: drawingPng,
      drawingPath: drawingPath,
      endedAtMs: s.endedAt.millisecondsSinceEpoch,
      overlayScale: s.overlay.scale,
      overlayDx: s.overlay.offset.dx,
      overlayDy: s.overlay.offset.dy,
    );
  }

  static Future<PracticeSession> fromStored(StoredSession ss) async {
    // Prefer external path (OPFS) if present; fallback to inline bytes.
    Uint8List bytes = ss.drawingPng;
    if (ss.drawingPath != null) {
      final store = createBinaryStore();
      final b = await store.read(ss.drawingPath!);
      if (b != null) {
        bytes = b;
      } else if (bytes.isEmpty) {
        // Path recorded but no inline bytes and read failed: nothing to decode.
        // Return an empty 1x1 image placeholder to avoid crashes.
        final recorder = ui.PictureRecorder();
        final c = ui.Canvas(recorder);
        c.drawPaint(ui.Paint());
        final pic = recorder.endRecording();
        final img = await pic.toImage(1, 1);
        return PracticeSession(
          sourceUrl: ss.sourceUrl,
          reference: null,
          referenceUrl: ss.referenceUrl,
          drawing: img,
          endedAt: DateTime.fromMillisecondsSinceEpoch(ss.endedAtMs),
          overlay: OverlayTransform(
            scale: ss.overlayScale,
            offset: ui.Offset(ss.overlayDx, ss.overlayDy),
          ),
        );
      }
    }
    final drawImage = await _decodeUiImage(bytes);

    return PracticeSession(
      sourceUrl: ss.sourceUrl,
      reference: null, // decoded reference not persisted on web
      referenceUrl: ss.referenceUrl,
      drawing: drawImage,
      endedAt: DateTime.fromMillisecondsSinceEpoch(ss.endedAtMs),
      overlay: OverlayTransform(
        scale: ss.overlayScale,
        offset: ui.Offset(ss.overlayDx, ss.overlayDy),
      ),
    );
  }
}

class HiveSessionRepository implements SessionRepository {
  static const String boxName = 'sessions';
  Box<Map>? _box;

  @override
  Future<void> init() async {
    // Init hive in main; here we only open box lazily if needed.
    if (!Hive.isAdapterRegistered(0)) {
      // No TypeAdapters used; we store Map directly. This is just a placeholder
      // to avoid warnings if any future adapters are added.
    }
    // Always ensure we hold a handle to an open box; after a clear/close we
    // need to reopen and refresh _box.
    if (!Hive.isBoxOpen(boxName)) {
      _box = await Hive.openBox<Map>(boxName);
    } else {
      _box = Hive.box<Map>(boxName);
    }
    // ignore: avoid_print
    infoLog('[Repo] box "$boxName" open; entries=${_box!.length}');
  }

  @override
  Future<List<StoredSession>> loadAll() async {
    await init();
    final result = <StoredSession>[];
    final seen = <String>{};
    int malformed = 0;
    final keysIterable = _box!.keys.toList(growable: false);
    // ignore: avoid_print
    infoLog('[Repo] loadAll: keys=${keysIterable.length}');
    for (final k in keysIterable) {
      final m = _box!.get(k);
      if (m == null) continue;
      try {
        final ss = StoredSession.fromMap(Map<String, Object?>.from(m));
        if (seen.add(ss.id)) {
          result.add(ss);
        }
      } catch (_) {
        malformed++;
      }
    }
    // newest-first by endedAt
    result.sort((a, b) => b.endedAtMs.compareTo(a.endedAtMs));
    final dedup = keysIterable.length - (result.length + malformed);
    // ignore: avoid_print
    infoLog(
      '[Repo] loadAll -> sessions=${result.length} (malformed=$malformed, dedup=$dedup)',
    );
    return result;
  }

  @override
  Future<void> save(StoredSession session) async {
    await init();
    await _box!.put(session.id, session.toMap());
    // ignore: avoid_print
    infoLog(
      '[Repo] saved id=${session.id} path=${session.drawingPath ?? ''} bytes=${session.drawingPng.length}',
    );
  }

  @override
  Future<void> updateOverlay(String id, OverlayTransform overlay) async {
    await init();
    final existing = _box!.get(id);
    if (existing == null) return;
    final m = Map<String, Object?>.from(existing);
    m['overlayScale'] = overlay.scale;
    m['overlayDx'] = overlay.offset.dx;
    m['overlayDy'] = overlay.offset.dy;
    await _box!.put(id, m);
    // ignore: avoid_print
    infoLog(
      '[Repo] overlay updated id=$id scale=${overlay.scale} dx=${overlay.offset.dx} dy=${overlay.offset.dy}',
    );
  }
}

Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
  final comp = Completer<ui.Image>();
  ui.decodeImageFromList(bytes, comp.complete);
  return comp.future;
}
