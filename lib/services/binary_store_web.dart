import 'dart:async';
import 'package:web/web.dart';
import 'dart:js_interop';
import 'binary_store.dart';
import 'binary_store_fallback.dart';
import 'package:flutter/foundation.dart';

// JavaScript interop interfaces for OPFS (WASM-compatible)
@JS()
@anonymous
extension type FileSystemDirectoryHandle._(JSObject _) implements JSObject {
  external JSPromise<FileSystemDirectoryHandle> getDirectoryHandle(
    String name, [
    FileSystemGetDirectoryOptions? options,
  ]);
  external JSPromise<FileSystemFileHandle> getFileHandle(
    String name, [
    FileSystemGetFileOptions? options,
  ]);
  external JSPromise<JSAny?> removeEntry(
    String name, [
    FileSystemRemoveOptions? options,
  ]);
}

@JS()
@anonymous
extension type FileSystemFileHandle._(JSObject _) implements JSObject {
  external JSPromise<File> getFile();
  external JSPromise<FileSystemWritableFileStream> createWritable([
    FileSystemCreateWritableOptions? options,
  ]);
}

@JS()
@anonymous
extension type FileSystemWritableFileStream._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSAny data);
  external JSPromise<JSAny?> close();
}

@JS()
@anonymous
extension type FileSystemGetDirectoryOptions._(JSObject _) implements JSObject {
  external factory FileSystemGetDirectoryOptions({bool create});
}

@JS()
@anonymous
extension type FileSystemGetFileOptions._(JSObject _) implements JSObject {
  external factory FileSystemGetFileOptions({bool create});
}

@JS()
@anonymous
extension type FileSystemRemoveOptions._(JSObject _) implements JSObject {
  external factory FileSystemRemoveOptions({bool recursive});
}

@JS()
@anonymous
extension type FileSystemCreateWritableOptions._(JSObject _)
    implements JSObject {
  external factory FileSystemCreateWritableOptions({bool keepExistingData});
}

/// WASM-compatible OPFS implementation using dart:js_interop
class OpfsBinaryStore implements BinaryStore {
  FileSystemDirectoryHandle? _root;

  Future<void> _ensureRoot() async {
    if (_root != null) return;
    try {
      debugPrint('[OPFS] Obtaining root directory handle...');

      // Check if we're in a secure context
      if (!window.isSecureContext) {
        debugPrint(
          '[OPFS] ERROR: Not in secure context - OPFS requires HTTPS or localhost',
        );
        debugPrint('[OPFS] Current location: ${window.location.href}');
        throw StateError('OPFS requires secure context');
      }
      debugPrint('[OPFS] ✓ Secure context confirmed');

      // Get navigator.storage
      final navigator = window.navigator;
      final storage = navigator.storage;
      debugPrint('[OPFS] ✓ navigator.storage found');

      // Try to call getDirectory - this is where most failures occur
      debugPrint('[OPFS] Calling storage.getDirectory()...');
      final directoryPromise = storage.getDirectory();
      debugPrint('[OPFS] ✓ getDirectory() call succeeded, awaiting promise...');

      final rootObj = await directoryPromise.toDart;
      _root = rootObj as FileSystemDirectoryHandle;
      debugPrint('[OPFS] ✅ SUCCESS: Root directory handle obtained');
    } catch (e, stackTrace) {
      debugPrint('[OPFS] ❌ ERROR in _ensureRoot: $e');
      debugPrint('[OPFS] Error type: ${e.runtimeType}');
      if (e.toString().contains('getDirectory')) {
        debugPrint(
          '[OPFS] This browser may not support OPFS getDirectory method',
        );
      }
      debugPrint('[OPFS] Stack trace: $stackTrace');
      _root = null;
      rethrow;
    }
  }

  @override
  Future<bool> isAvailable() async {
    try {
      debugPrint('[OPFS] 🔍 Checking availability...');
      debugPrint('[OPFS] User Agent: ${window.navigator.userAgent}');
      debugPrint('[OPFS] Location: ${window.location.href}');
      debugPrint('[OPFS] Secure Context: ${window.isSecureContext}');

      await _ensureRoot();
      final available = _root != null;
      debugPrint('[OPFS] 🎯 Final availability result: $available');
      return available;
    } catch (e) {
      debugPrint('[OPFS] ❌ isAvailable() failed: $e');
      return false;
    }
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    await _ensureRoot();
    final root = _root;
    if (root == null) throw StateError('OPFS not available');

    try {
      // Split key into directory parts and filename
      final parts = key.split('/');
      FileSystemDirectoryHandle dir = root;

      // Create subdirectories if needed
      for (int i = 0; i < parts.length - 1; i++) {
        dir = await dir
            .getDirectoryHandle(
              parts[i],
              FileSystemGetDirectoryOptions(create: true),
            )
            .toDart;
      }

      // Create file handle
      final fileHandle = await dir
          .getFileHandle(parts.last, FileSystemGetFileOptions(create: true))
          .toDart;

      // Create writable stream
      final stream = await fileHandle.createWritable().toDart;

      try {
        // Create blob from bytes
        final jsBytes = bytes.toJS;
        final blob = Blob([jsBytes].toJS);

        // Write blob to stream
        await stream.write(blob).toDart;
      } finally {
        // Close stream
        await stream.close().toDart;
      }

      // Debug print to trace writes
      // ignore: avoid_print
      debugPrint('[OPFS] wrote ${bytes.length} bytes to $key');
    } catch (e) {
      // ignore: avoid_print
      debugPrint('[OPFS] write error for $key: $e');
      rethrow;
    }
  }

  @override
  Future<Uint8List?> read(String key) async {
    await _ensureRoot();
    final root = _root;
    if (root == null) return null;

    try {
      final parts = key.split('/');
      FileSystemDirectoryHandle dir = root;

      // Navigate to subdirectories
      for (int i = 0; i < parts.length - 1; i++) {
        dir = await dir.getDirectoryHandle(parts[i]).toDart;
      }

      // Get file handle
      final fileHandle = await dir.getFileHandle(parts.last).toDart;

      // Get file
      final file = await fileHandle.getFile().toDart;

      // Read as array buffer
      final arrayBufferPromise = file.arrayBuffer();
      final arrayBuffer = await arrayBufferPromise.toDart;

      // Convert to Uint8List
      final jsUint8Array = JSUint8Array(arrayBuffer);
      final dartBytes = jsUint8Array.toDart;

      // ignore: avoid_print
      debugPrint('[OPFS] read ${dartBytes.length} bytes from $key');
      return dartBytes;
    } catch (_) {
      // ignore: avoid_print
      debugPrint('[OPFS] read miss for $key');
      return null;
    }
  }

  @override
  Future<void> delete(String key) async {
    await _ensureRoot();
    final root = _root;
    if (root == null) return;

    try {
      final parts = key.split('/');
      FileSystemDirectoryHandle dir = root;

      // Navigate to parent directory
      for (int i = 0; i < parts.length - 1; i++) {
        dir = await dir.getDirectoryHandle(parts[i]).toDart;
      }

      // Remove entry
      await dir.removeEntry(parts.last).toDart;

      // ignore: avoid_print
      debugPrint('[OPFS] deleted $key');
    } catch (_) {
      // Silent failure for delete operations
    }
  }
}

class WebBinaryStore implements BinaryStore {
  final OpfsBinaryStore _opfs = OpfsBinaryStore();
  final BinaryStore _fallback;

  WebBinaryStore({BinaryStore? fallback})
    : _fallback = fallback ?? HiveBinaryStore() {
    debugPrint('[WebBinaryStore] 🏗️ Initialized with OPFS + Hive fallback');
  }

  @override
  Future<bool> isAvailable() async {
    debugPrint('[WebBinaryStore] 🔍 Checking if binary store is available...');
    final opfsAvailable = await _opfs.isAvailable();
    debugPrint('[WebBinaryStore] OPFS available: $opfsAvailable');

    if (opfsAvailable) return true;

    final fallbackAvailable = await _fallback.isAvailable();
    debugPrint('[WebBinaryStore] Hive fallback available: $fallbackAvailable');
    return fallbackAvailable;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    debugPrint(
      '[WebBinaryStore] 📝 Writing ${bytes.length} bytes to key: $key',
    );
    if (await _opfs.isAvailable()) {
      debugPrint('[WebBinaryStore] Using OPFS for write');
      await _opfs.write(key, bytes);
    } else {
      debugPrint('[WebBinaryStore] Using Hive fallback for write');
      await _fallback.write(key, bytes);
    }
  }

  @override
  Future<Uint8List?> read(String key) async {
    debugPrint('[WebBinaryStore] 📖 Reading key: $key');
    if (await _opfs.isAvailable()) {
      debugPrint('[WebBinaryStore] Trying OPFS read first');
      final r = await _opfs.read(key);
      if (r != null) {
        debugPrint('[WebBinaryStore] OPFS read successful, ${r.length} bytes');
        return r;
      }
      debugPrint('[WebBinaryStore] OPFS read miss, trying fallback');
    } else {
      debugPrint('[WebBinaryStore] OPFS unavailable, using Hive fallback');
    }
    final result = await _fallback.read(key);
    debugPrint(
      '[WebBinaryStore] Fallback read result: ${result?.length ?? 0} bytes',
    );
    return result;
  }

  @override
  Future<void> delete(String key) async {
    if (await _opfs.isAvailable()) {
      await _opfs.delete(key);
    } else {
      await _fallback.delete(key);
    }
  }
}

BinaryStore createPlatformBinaryStore() => WebBinaryStore();
