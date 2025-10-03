// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;
import 'dart:js_interop';

// Track registered view types in memory to avoid duplicate registration within same session
final Set<String> _registeredViewTypes = {};

/// Registers a platform view for a div with the given [elementId].
/// On Flutter web, this allows using HtmlElementView(viewType: elementId).
void ensureWebHostRegistered(String elementId) {
  // Register only once per elementId per session (in-memory tracking).
  if (_registeredViewTypes.contains(elementId)) {
    web.console.log('[WgpuProbe] View already registered: $elementId'.toJS);
    return;
  }

  web.console.log('[WgpuProbe] Registering platform view: $elementId'.toJS);
  // ignore: undefined_prefixed_name
  ui_web.platformViewRegistry.registerViewFactory(elementId, (int viewId) {
    web.console.log(
      '[WgpuProbe] Creating view for: $elementId (viewId: $viewId)'.toJS,
    );
    final existing = web.document.getElementById(elementId);
    if (existing != null) {
      web.console.log('[WgpuProbe] Using existing element'.toJS);
      return existing;
    }
    web.console.log('[WgpuProbe] Creating new div element'.toJS);
    final div = web.HTMLDivElement()..id = elementId;
    return div;
  });

  _registeredViewTypes.add(elementId);
  web.console.log('[WgpuProbe] Registration complete'.toJS);
}
