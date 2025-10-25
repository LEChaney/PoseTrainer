// wasm_drawing_service_stub.dart
// -------------------------------
// Stub implementation for non-web platforms
// This file is imported when dart:html is not available (native platforms)

import 'dart:ui' as ui;
import 'dart:async';

/// Stub service for non-web platforms
/// The actual WASM service is only available on web
class WasmDrawingService {
  Future<void> initialize(int width, int height) async {
    throw UnsupportedError('WasmDrawingService is only available on web platform');
  }

  void setBrushSize(double size) {
    throw UnsupportedError('WasmDrawingService is only available on web platform');
  }

  void setBrushFlow(double flow) {
    throw UnsupportedError('WasmDrawingService is only available on web platform');
  }

  void setBrushHardness(double hardness) {
    throw UnsupportedError('WasmDrawingService is only available on web platform');
  }

  void setBrushColor(double r, double g, double b, double a) {
    throw UnsupportedError('WasmDrawingService is only available on web platform');
  }

  void clear() {
    throw UnsupportedError('WasmDrawingService is only available on web platform');
  }

  (int, int) getCanvasSize() {
    throw UnsupportedError('WasmDrawingService is only available on web platform');
  }

  Future<ui.Image> exportCanvas() async {
    throw UnsupportedError('WasmDrawingService is only available on web platform');
  }

  void dispose() {
    // No-op on non-web platforms
  }
}
