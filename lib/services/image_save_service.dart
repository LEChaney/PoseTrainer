import 'dart:typed_data';
import 'image_save_service_stub.dart'
    if (dart.library.js_interop) 'image_save_service_web.dart';

// image_save_service.dart
// -----------------------
// Cross-platform image saving.
//   - Web  : triggers a browser "Save As" download via a temporary blob URL.
//   - Native: opens the system share sheet so the user can save to Files /
//             Photos / Downloads as appropriate for their platform.
//
// Usage:
//   await saveImageBytes(pngBytes, 'drawing.png');

/// Saves [bytes] (PNG) to the device with the given [filename].
///
/// Web    → triggers a browser download.
/// Native → opens the platform share sheet with the file attached.
Future<void> saveImageBytes(Uint8List bytes, String filename) =>
    saveImageBytesImpl(bytes, filename);
