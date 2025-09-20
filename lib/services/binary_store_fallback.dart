import 'dart:typed_data';
import 'package:hive_ce/hive.dart';
import 'package:flutter/foundation.dart';

import 'binary_store.dart';
import 'debug_logger.dart';

class HiveBinaryStore implements BinaryStore {
  static const String boxName = 'session_blobs';
  Box<Uint8List>? _box;

  HiveBinaryStore() {
    infoLog('[HiveBinaryStore] 🏗️ Initialized (fallback storage)');
  }

  Future<void> _ensure() async {
    if (_box == null) {
      if (!Hive.isBoxOpen(boxName)) {
        _box = await Hive.openBox<Uint8List>(boxName);
      } else {
        _box = Hive.box<Uint8List>(boxName);
      }
    }
  }

  @override
  Future<Uint8List?> read(String key) async {
    infoLog('[HiveBinaryStore] 📖 Reading key: $key');
    await _ensure();
    final result = _box!.get(key);
    infoLog('[HiveBinaryStore] Read result: ${result?.length ?? 0} bytes');
    return result;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    infoLog('[HiveBinaryStore] 📝 Writing ${bytes.length} bytes to key: $key');
    await _ensure();
    await _box!.put(key, bytes);
  }

  @override
  Future<bool> isAvailable() async {
    infoLog('[HiveBinaryStore] ✅ isAvailable() = true (Hive fallback)');
    return true;
  }

  @override
  Future<void> delete(String key) async {
    await _ensure();
    await _box!.delete(key);
  }
}

BinaryStore createPlatformBinaryStore() => HiveBinaryStore();
