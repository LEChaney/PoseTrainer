import 'storage_diagnostics.dart';

Future<StorageInfo> getStorageInfoImpl({required int sessionsCount}) async {
  return StorageInfo(
    opfsAvailable: false,
    persistentGranted: false,
    usageBytes: null,
    quotaBytes: null,
    sessionsCount: sessionsCount,
  );
}

Future<void> clearAllStorageImpl() async {}
