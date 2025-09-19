import 'persistence_util_stub.dart'
    if (dart.library.html) 'persistence_util_web.dart';

/// Requests persistent storage on platforms that support it.
/// Returns true if granted. No-op on non-web.
Future<bool> requestPersistentStorage() => requestPersistentStorageImpl();
