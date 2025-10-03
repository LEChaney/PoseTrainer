// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'package:web/web.dart' as web;
import 'dart:js_interop';

class WgpuProbeService {
  static bool _loaded = false;
  static Future<void> ensureLoaded() async {
    if (_loaded) {
      web.console.log('[WgpuProbe] Already loaded, skipping'.toJS);
      return;
    }
    web.console.log('[WgpuProbe] Loading WASM module...'.toJS);
    final script = web.HTMLScriptElement()
      ..type = 'module'
      ..text =
          "console.log('[WgpuProbe] Module script executing'); import init from '/wgpu-probe/wgpu-probe.js'; init().then(() => console.log('[WgpuProbe] Init complete')).catch(e => console.error('[WgpuProbe] Init failed:', e));";
    web.document.head!.append(script);
    _loaded = true;
    web.console.log('[WgpuProbe] Module script injected'.toJS);
  }
}
