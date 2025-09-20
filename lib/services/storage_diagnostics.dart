import 'storage_diagnostics_stub.dart'
    if (dart.library.js_interop) 'storage_diagnostics_web.dart';

class StorageInfo {
  final bool opfsAvailable;
  final bool persistentGranted;
  final int? usageBytes;
  final int? quotaBytes;
  final int sessionsCount;
  const StorageInfo({
    required this.opfsAvailable,
    required this.persistentGranted,
    required this.usageBytes,
    required this.quotaBytes,
    required this.sessionsCount,
  });
}

Future<StorageInfo> getStorageInfo({required int sessionsCount}) =>
    getStorageInfoImpl(sessionsCount: sessionsCount);

/// Clears all app storage: Hive metadata, blob box, and OPFS files (web).
Future<void> clearAllStorage() => clearAllStorageImpl();
