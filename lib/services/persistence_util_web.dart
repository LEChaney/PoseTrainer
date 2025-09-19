import 'dart:html' as html;

Future<bool> requestPersistentStorageImpl() async {
  try {
    final storage = html.window.navigator.storage;
    if (storage == null) return false;
    final granted = await storage.persist();
    return granted;
  } catch (_) {
    return false;
  }
}
