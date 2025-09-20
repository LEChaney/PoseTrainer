import 'dart:typed_data';
import 'package:hive_ce/hive.dart';

import 'binary_store.dart';

class HiveBinaryStore implements BinaryStore {
  static const String boxName = 'session_blobs';
  Box<Uint8List>? _box;

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
    await _ensure();
    return _box!.get(key);
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    await _ensure();
    await _box!.put(key, bytes);
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> delete(String key) async {
    await _ensure();
    await _box!.delete(key);
  }
}

BinaryStore createPlatformBinaryStore() => HiveBinaryStore();
