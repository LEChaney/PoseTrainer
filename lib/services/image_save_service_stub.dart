import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Native implementation: writes PNG bytes to a temporary file and opens
/// the platform share sheet so the user can save to Photos, Files, etc.
Future<void> saveImageBytesImpl(Uint8List bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([
    XFile(file.path, mimeType: 'image/png', name: filename),
  ], subject: filename);
}
