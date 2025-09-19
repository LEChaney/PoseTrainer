import 'dart:async';
import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:js_util' as jsu;
import 'package:file_system_access_api/file_system_access_api.dart' as fsa;
import 'binary_store.dart';
import 'binary_store_fallback.dart';

class OpfsBinaryStore implements BinaryStore {
  fsa.FileSystemDirectoryHandle? _root;

  Future<void> _ensureRoot() async {
    if (_root != null) return;
    _root = await html.window.navigator.storage?.getDirectory();
  }

  @override
  Future<bool> isAvailable() async {
    if (!fsa.FileSystemAccess.supported) return false;
    try {
      await _ensureRoot();
      return _root != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    await _ensureRoot();
    final root = _root!;
    // Ensure any subdirectories in key exist (e.g., 'sessions/123.png')
    final parts = key.split('/');
    fsa.FileSystemDirectoryHandle dir = root;
    for (int i = 0; i < parts.length - 1; i++) {
      dir = await dir.getDirectoryHandle(parts[i], create: true);
    }
    final file = await dir.getFileHandle(parts.last, create: true);
    final stream = await file.createWritable();
    // Use JS interop to call 'write' with a Blob, wrapped in try/catch.
    try {
      final blob = html.Blob([bytes]);
      jsu.callMethod(stream as Object, 'write', [blob]);
    } finally {
      await stream.close();
    }
    // Debug print to trace writes
    // ignore: avoid_print
    print('[OPFS] wrote ${bytes.length} bytes to $key');
  }

  @override
  Future<Uint8List?> read(String key) async {
    await _ensureRoot();
    final root = _root!;
    try {
      final parts = key.split('/');
      fsa.FileSystemDirectoryHandle dir = root;
      for (int i = 0; i < parts.length - 1; i++) {
        dir = await dir.getDirectoryHandle(parts[i]);
      }
      final file = await dir.getFileHandle(parts.last);
      final html.File f = await file.getFile();
      final reader = html.FileReader();
      final completer = Completer<Uint8List>();
      reader.onLoadEnd.listen((_) {
        final result = reader.result;
        if (result is ByteBuffer) {
          completer.complete(Uint8List.view(result));
        } else if (result is Uint8List) {
          completer.complete(result);
        } else {
          completer.completeError(StateError('Unexpected FileReader result'));
        }
      });
      reader.onError.listen((e) => completer.completeError(e));
      reader.readAsArrayBuffer(f);
      final out = await completer.future;
      // ignore: avoid_print
      print('[OPFS] read ${out.length} bytes from $key');
      return out;
    } catch (_) {
      // ignore: avoid_print
      print('[OPFS] read miss for $key');
      return null;
    }
  }

  @override
  Future<void> delete(String key) async {
    await _ensureRoot();
    final root = _root!;
    try {
      final parts = key.split('/');
      fsa.FileSystemDirectoryHandle dir = root;
      for (int i = 0; i < parts.length - 1; i++) {
        dir = await dir.getDirectoryHandle(parts[i]);
      }
      try {
        await dir.removeEntry(parts.last);
        // ignore: avoid_print
        print('[OPFS] deleted $key');
      } catch (_) {}
    } catch (_) {}
  }
}

class WebBinaryStore implements BinaryStore {
  final OpfsBinaryStore _opfs = OpfsBinaryStore();
  final BinaryStore _fallback;

  WebBinaryStore({BinaryStore? fallback})
    : _fallback = fallback ?? HiveBinaryStore();

  @override
  Future<bool> isAvailable() async =>
      await _opfs.isAvailable() || await _fallback.isAvailable();

  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (await _opfs.isAvailable()) {
      await _opfs.write(key, bytes);
    } else {
      await _fallback.write(key, bytes);
    }
  }

  @override
  Future<Uint8List?> read(String key) async {
    if (await _opfs.isAvailable()) {
      final r = await _opfs.read(key);
      if (r != null) return r;
    }
    return _fallback.read(key);
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
