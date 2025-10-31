// wasm_drawing_service.dart
// -------------------------
// Flutter service that wraps the Rust WASM drawing canvas for web platform.
// This provides a Dart-friendly API over the raw JS interop.
//
// Key responsibilities:
// - Load and initialize WASM module
// - Forward brush parameter changes to Rust
// - Export final canvas as ui.Image for review
// - Manage lifecycle (clear, dispose)
//
// Usage:
//   final service = WasmDrawingService();
//   await service.initialize(width, height);
//   service.setBrushSize(75.0);
//   final image = await service.exportCanvas();

import 'dart:ui' as ui;
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;
import 'debug_logger.dart';

/// Service for interfacing with the Rust WASM drawing canvas
/// Only available on web platform
class WasmDrawingService {
  bool _viewRegistered = false;
  bool _fullyInitialized = false;
  static bool _moduleLoaded = false;
  static int _viewIdCounter = 0;
  late String _viewId;

  /// Constructor - immediately generates viewId and registers platform view
  WasmDrawingService() {
    // Generate unique view ID immediately
    _viewId = 'wasm-canvas-${_viewIdCounter++}';

    // Register platform view factory immediately
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      final container = web.document.createElement('div') as web.HTMLDivElement;
      // Use unique ID for each container to avoid conflicts
      container.id =
          _viewId; // Changed from 'canvas-container' to unique _viewId
      container.setAttribute(
        'data-canvas-container',
        'true',
      ); // Add marker attribute
      container.style.width = '100%';
      container.style.height = '100%';
      container.style.position = 'relative';
      container.style.pointerEvents = 'auto';

      debugLog('Canvas container created for view: $_viewId', tag: 'WASM');
      return container;
    });

    _viewRegistered = true;
    debugLog('WASM service created, viewId: $_viewId', tag: 'WASM');
  }

  /// Get the view ID for use with HtmlElementView
  String get viewId => _viewId;

  /// Check if the WASM module is fully initialized
  bool get isFullyInitialized => _fullyInitialized;

  /// Initialize the WASM drawing canvas
  /// This should be called once before using any other methods
  Future<void> initialize(int width, int height) async {
    if (_fullyInitialized) {
      debugLog('WASM service already initialized', tag: 'WASM');
      return;
    }

    if (!_viewRegistered) {
      throw StateError(
        'View not registered - constructor should have done this',
      );
    }

    debugLog('Initializing WASM drawing service...', tag: 'WASM');

    // Load and initialize the WASM module if not already loaded
    // But don't start the event loop yet - that happens after the view is rendered
    if (!_moduleLoaded) {
      await _loadWasmModule();
      _moduleLoaded = true;
    }

    _fullyInitialized = true;
    debugLog(
      'WASM drawing service initialized: ${width}x$height (view not yet rendered)',
      tag: 'WASM',
    );
  }

  /// Start the WASM canvas event loop
  /// This should be called after the HtmlElementView has been built
  Future<void> startEventLoop() async {
    if (!_fullyInitialized) {
      throw StateError('Must call initialize() before startEventLoop()');
    }

    debugLog('Starting WASM event loop...', tag: 'WASM');

    // Wait for the canvas container to appear in the DOM
    await _waitForCanvas();

    // Now start the drawing canvas event loop
    _initDrawingCanvas();

    debugLog('WASM event loop started', tag: 'WASM');
  }

  /// Load the WASM module dynamically
  Future<void> _loadWasmModule() async {
    debugLog('Loading WASM module...', tag: 'WASM');

    try {
      // Import the WASM module's JavaScript wrapper
      // This injects a script tag that does ES6 dynamic import
      await _importWasmModule();

      // Initialize the WASM module (loads and calls wasm-bindgen init)
      // This makes all exported functions available globally
      await _initWasm();

      debugLog('WASM module loaded and initialized', tag: 'WASM');
    } catch (e, stack) {
      debugLog('Failed to load WASM module: $e\n$stack', tag: 'WASM');
      rethrow;
    }
  }

  /// Wait for the canvas container to appear in the DOM
  Future<void> _waitForCanvas() async {
    const maxAttempts = 50; // 5 seconds max
    for (var i = 0; i < maxAttempts; i++) {
      // Look for our specific container by viewId
      final container = web.document.getElementById(_viewId);
      if (container != null) {
        debugLog('Canvas container found in DOM: $_viewId', tag: 'WASM');
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    throw Exception(
      'Canvas container $_viewId not found in DOM after waiting 5 seconds',
    );
  }

  /// Set brush size (diameter in pixels)
  void setBrushSize(double size) {
    _ensureInitialized();
    _setBrushSize(size);
    debugLog('Set brush size: $size', tag: 'WASM');
  }

  /// Set brush flow/opacity per dab (0.0-1.0)
  void setBrushFlow(double flow) {
    _ensureInitialized();
    _setBrushFlow(flow);
    debugLog('Set brush flow: $flow', tag: 'WASM');
  }

  /// Set brush edge hardness (0.0=soft, 1.0=hard)
  void setBrushHardness(double hardness) {
    _ensureInitialized();
    _setBrushHardness(hardness);
    debugLog('Set brush hardness: $hardness', tag: 'WASM');
  }

  /// Set brush color (sRGB values 0.0-1.0)
  void setBrushColor(double r, double g, double b, double a) {
    _ensureInitialized();
    _setBrushColor(r, g, b, a);
    debugLog('Set brush color: rgba($r, $g, $b, $a)', tag: 'WASM');
  }

  /// Set input filter mode
  /// penOnly: true for pen-only mode, false for pen+touch mode
  void setInputFilterMode(bool penOnly) {
    _ensureInitialized();
    _setInputFilterMode(penOnly);
    debugLog(
      'Set input filter mode: ${penOnly ? 'Pen Only' : 'Pen+Touch'}',
      tag: 'WASM',
    );
  }

  /// Clear the canvas
  void clear() {
    _ensureInitialized();
    _clearCanvas();
    debugLog('Canvas cleared', tag: 'WASM');
  }

  /// Get canvas dimensions
  (int width, int height) getCanvasSize() {
    _ensureInitialized();
    return (_getCanvasWidth(), _getCanvasHeight());
  }

  /// Export canvas as Flutter ui.Image
  /// This performs an expensive GPU->CPU readback
  Future<ui.Image> exportCanvas() async {
    _ensureInitialized();
    debugLog('Exporting canvas...', tag: 'WASM');

    // Get canvas dimensions
    final width = _getCanvasWidth();
    final height = _getCanvasHeight();

    // Get image data from WASM (RGBA8 pixels) - this returns a JS Promise
    final jsPromise = _getCanvasImageData();
    final jsArray = await jsPromise.toDart;

    debugLog('Received image data: ${width}x$height', tag: 'WASM');

    // Convert JS Uint8ClampedArray to Dart Uint8List
    // JSUint8ClampedArray.toDart returns Uint8ClampedList, convert to Uint8List
    final clampedBytes = jsArray.toDart;
    final bytes = Uint8List.fromList(clampedBytes);

    debugLog('Converted to Dart bytes: ${bytes.length} bytes', tag: 'WASM');

    // Create ui.Image from raw RGBA bytes
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, width, height, ui.PixelFormat.rgba8888, (
      ui.Image image,
    ) {
      completer.complete(image);
    });

    final image = await completer.future;
    debugLog('Canvas exported as ui.Image: ${width}x$height', tag: 'WASM');
    return image;
  }

  /// Cleanup resources
  void dispose() {
    // Platform views are automatically cleaned up by Flutter
    // We just mark as uninitialized
    _fullyInitialized = false;
    debugLog('WASM service disposed', tag: 'WASM');
  }

  void _ensureInitialized() {
    if (!_fullyInitialized) {
      throw StateError(
        'WasmDrawingService not initialized. Call initialize() first.',
      );
    }
  }
}

// JS interop declarations for calling Rust WASM exports
// These match the #[wasm_bindgen] functions in lib.rs

/// Initialize the drawing canvas (starts the event loop)
@JS('init_drawing_canvas')
external void _initDrawingCanvas();

@JS('set_brush_size')
external void _setBrushSize(double size);

@JS('set_brush_flow')
external void _setBrushFlow(double flow);

@JS('set_brush_hardness')
external void _setBrushHardness(double hardness);

@JS('set_brush_color')
external void _setBrushColor(double r, double g, double b, double a);

@JS('set_input_filter_mode')
external void _setInputFilterMode(bool penOnly);

@JS('clear_canvas')
external void _clearCanvas();

@JS('get_canvas_width')
external int _getCanvasWidth();

@JS('get_canvas_height')
external int _getCanvasHeight();

@JS('get_canvas_image_data')
external JSPromise<JSUint8ClampedArray> _getCanvasImageData();

// Dynamic WASM module loading
// This injects a script tag to do ES6 dynamic import

/// Get property from window object
@JS('eval')
external JSAny? _jsEval(String code);

/// Import the WASM module dynamically by injecting a script tag
Future<void> _importWasmModule() async {
  // Inject a module script that does the dynamic import and stores init function
  final script = web.document.createElement('script') as web.HTMLScriptElement;
  script.type = 'module';
  script.textContent = '''
    // Set up debug function stubs for WASM module
    // These are called by the Rust code but we just log them in Flutter
    // Only log in debug mode (check if origin is localhost or contains 'debug')
    const isDebug = window.location.hostname === 'localhost' || 
                    window.location.hostname === '127.0.0.1' ||
                    window.location.search.includes('debug=true');
    
    window.updateDebugStatus = function(status) {
      if (isDebug) console.log('[WASM Debug] Status:', status);
    };
    
    window.updateDebugStage = function(stage) {
      if (isDebug) console.log('[WASM Debug] Stage:', stage);
    };
    
    window.updateDebugPointer = function(type, x, y, pressure, tilt_x, tilt_y, azimuth, twist) {
      if (isDebug) console.log('[WASM Debug] Pointer:', {type, x, y, pressure, tilt_x, tilt_y, azimuth, twist});
    };
    
    window.incrementFrameCount = function() {
      // No-op in Flutter, we don't need frame counting
    };
    
    window.__wasmDrawingInit = async () => {
      console.log('[WASM] Importing drawing_canvas.js...');
      // Use base href to construct correct path for versioned assets
      const baseHref = document.querySelector('base')?.getAttribute('href') || '/';
      const modulePath = baseHref + 'pkg/drawing_canvas.js';
      console.log('[WASM] Loading from:', modulePath);
      const module = await import(modulePath);
      console.log('[WASM] Module imported, calling default init...');
      await module.default();
      console.log('[WASM] Init complete, module:', module);
      
      // Expose all exported functions to window for Dart to call
      window.init_drawing_canvas = module.init_drawing_canvas;
      window.set_brush_size = module.set_brush_size;
      window.set_brush_flow = module.set_brush_flow;
      window.set_brush_hardness = module.set_brush_hardness;
      window.set_brush_color = module.set_brush_color;
      window.set_input_filter_mode = module.set_input_filter_mode;
      window.clear_canvas = module.clear_canvas;
      window.get_canvas_width = module.get_canvas_width;
      window.get_canvas_height = module.get_canvas_height;
      window.get_canvas_image_data = module.get_canvas_image_data;
      
      console.log('[WASM] All functions exposed to window');
      return module;
    };
  ''';
  web.document.head!.appendChild(script);

  // Wait a bit for the script to execute
  await Future.delayed(const Duration(milliseconds: 100));
}

/// Initialize the WASM module (calls the init function from wasm-bindgen)
Future<void> _initWasm() async {
  // Use eval to get the function (safer than @JS for dynamic properties)
  final initFn = _jsEval('window.__wasmDrawingInit');
  if (initFn == null) {
    throw Exception('WASM init function not found on window');
  }

  // Call the function which returns a promise
  final fnObj = initFn as JSFunction;
  final result = fnObj.callAsFunction(null);

  if (result != null) {
    // Wait for the promise to resolve
    final promise = result as JSPromise;
    await promise.toDart;
  }
}
