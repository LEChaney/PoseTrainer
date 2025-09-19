import 'dart:html' as html;
import 'dart:async';
import 'dart:typed_data';
import 'package:file_system_access_api/file_system_access_api.dart' as fsa;
import 'binary_store.dart';
import 'storage_diagnostics.dart';
import 'package:hive/hive.dart';

Future<StorageInfo> getStorageInfoImpl({required int sessionsCount}) async {
  final store = createBinaryStore();
  final opfsAvailable = await store.isAvailable();

  bool persistent = false;
  int? usage;
  int? quota;
  try {
    final storage = html.window.navigator.storage;
    if (storage != null) {
      persistent = await storage.persisted();
      final estimate = await storage.estimate();
      if (estimate != null) {
        final m = estimate as Map<dynamic, dynamic>;
        final u = m['usage'];
        final q = m['quota'];
        usage = (u is num) ? u.toInt() : null;
        quota = (q is num) ? q.toInt() : null;
      }
    }
  } catch (_) {}

  return StorageInfo(
    opfsAvailable: opfsAvailable,
    persistentGranted: persistent,
    usageBytes: usage,
    quotaBytes: quota,
    sessionsCount: sessionsCount,
  );
}

Future<void> clearAllStorageImpl() async {
  // ignore: avoid_print
  print('[Diag] clearAllStorage: begin');
  // 1) Try removing the entire OPFS sessions directory recursively.
  var opfsSessionsRemoved = false;
  try {
    final fsa.FileSystemDirectoryHandle? root = await html
        .window
        .navigator
        .storage
        ?.getDirectory();
    if (root != null) {
      try {
        await root.removeEntry('sessions', recursive: true);
        // ignore: avoid_print
        print('[Diag] OPFS: removed "/sessions" dir recursively');
      } catch (e) {
        // ignore: avoid_print
        print('[Diag] OPFS: recursive remove failed; will scan by paths');
      }
      // Verify presence post-deletion
      try {
        await root.getDirectoryHandle('sessions');
        // ignore: avoid_print
        print('[Diag] OPFS: sessions dir still present after removal attempt');
      } catch (_) {
        // ignore: avoid_print
        print('[Diag] OPFS: sessions dir not found after removal attempt');
        opfsSessionsRemoved = true;
      }
    }
  } catch (_) {}

  // 1b) Fallback: Clear OPFS blobs we know about by deleting known keys from BinaryStore.
  try {
    if (!opfsSessionsRemoved) {
      final store = createBinaryStore();
      if (await store.isAvailable()) {
        // We don't have a directory listing API here; delete by IDs from Hive.
        final Box<Map> sessionsBox = Hive.isBoxOpen('sessions')
            ? Hive.box<Map>('sessions')
            : await Hive.openBox<Map>('sessions');
        // ignore: avoid_print
        print(
          '[Diag] clearAllStorage: scanning ${sessionsBox.length} session maps for drawingPath',
        );
        for (final key in sessionsBox.keys) {
          final raw = sessionsBox.get(key);
          if (raw is Map) {
            final m = Map<String, Object?>.from(raw);
            final p = m['drawingPath'];
            if (p is String && p.isNotEmpty) {
              await store.delete(p);
              // ignore: avoid_print
              print('[Diag] clearAllStorage: deleted OPFS $p');
            }
          }
        }
        await sessionsBox.close();
        // ignore: avoid_print
        print('[Diag] clearAllStorage: closed scanning box "sessions"');
      }
    }
  } catch (_) {}

  // 2) Delete Hive boxes from IndexedDB. Use deleteBoxFromDisk per box.
  try {
    // Close all to avoid open-handle issues that can stall deletion on web.
    final hadSessionsOpen = Hive.isBoxOpen('sessions');
    final hadBlobsOpen = Hive.isBoxOpen('session_blobs');
    // ignore: avoid_print
    print(
      '[Diag] Hive: before global close -> sessionsOpen=$hadSessionsOpen, blobsOpen=$hadBlobsOpen',
    );
    await Hive.close();
    // ignore: avoid_print
    print('[Diag] Hive: closed all boxes');

    // Helper to delete with timeout and clear fallback.
    Future<void> deleteBoxSafely({
      required String name,
      required Future<void> Function() deleteStatic,
      required Future<void> Function() clearFallback,
    }) async {
      // ignore: avoid_print
      print('[Diag] Hive: deleting box "$name" via static delete');
      try {
        await deleteStatic().timeout(const Duration(seconds: 3));
        // ignore: avoid_print
        print('[Diag] clearAllStorage: deleted Hive box "$name"');
      } on TimeoutException {
        // ignore: avoid_print
        print(
          '[Diag] Hive: delete "$name" timed out; attempting clear() fallback',
        );
        await clearFallback();
        // ignore: avoid_print
        print('[Diag] clearAllStorage: cleared all entries in box "$name"');
      }
    }

    await deleteBoxSafely(
      name: 'sessions',
      deleteStatic: () => Hive.deleteBoxFromDisk('sessions'),
      clearFallback: () async {
        final Box<Map> b = await Hive.openBox<Map>('sessions');
        final n = b.length;
        await b.clear();
        await b.close();
        // ignore: avoid_print
        print('[Diag] Hive: sessions clear() removed $n entries');
      },
    );

    await deleteBoxSafely(
      name: 'session_blobs',
      deleteStatic: () => Hive.deleteBoxFromDisk('session_blobs'),
      clearFallback: () async {
        final Box<Uint8List> b = await Hive.openBox<Uint8List>('session_blobs');
        final n = b.length;
        await b.clear();
        await b.close();
        // ignore: avoid_print
        print('[Diag] Hive: session_blobs clear() removed $n entries');
      },
    );
  } catch (e) {
    // ignore: avoid_print
    print('[Diag] clearAllStorage: Hive deletion step threw: $e');
  }
  // ignore: avoid_print
  print('[Diag] clearAllStorage: end');
}
