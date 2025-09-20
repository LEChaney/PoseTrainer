import 'dart:typed_data';

import 'binary_store_fallback.dart'
    if (dart.library.js_interop) 'binary_store_web.dart';

abstract class BinaryStore {
  Future<bool> isAvailable();
  Future<void> write(String key, Uint8List bytes);
  Future<Uint8List?> read(String key);
  Future<void> delete(String key);
}

BinaryStore createBinaryStore() => createPlatformBinaryStore();
