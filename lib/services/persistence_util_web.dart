import 'package:web/web.dart';
import 'dart:js_interop';

Future<bool> requestPersistentStorageImpl() async {
  try {
    final storage = window.navigator.storage;
    final grantedPromise = storage.persist();
    final granted = await grantedPromise.toDart;
    return granted.toDart;
  } catch (_) {
    return false;
  }
}
