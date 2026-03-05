import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'dart:js_interop';

/// Web implementation: creates a temporary blob URL and clicks a hidden
/// anchor element so the browser shows its native "Save As" download dialog.
Future<void> saveImageBytesImpl(Uint8List bytes, String filename) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
  final url = web.URL.createObjectURL(blob);

  final a = web.document.createElement('a') as web.HTMLAnchorElement;
  a.href = url;
  a.download = filename;

  // Must be in the DOM for Firefox compatibility.
  web.document.body!.append(a);
  a.click();

  // Small async gap to let the browser queue the download before clean-up.
  await Future.delayed(const Duration(milliseconds: 150));
  a.remove();
  web.URL.revokeObjectURL(url);
}
