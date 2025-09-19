import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../widgets/letterboxed_image.dart';
import '../widgets/reference_draw_split.dart';
import 'package:provider/provider.dart';
import '../models/practice_session.dart';
import '../models/review_result.dart';
import '../services/session_service.dart';

// review_screen.dart
// ------------------
// WHY this screen exists:
// After a timed practice stroke session the user needs rapid visual feedback: Did my proportions and gesture align with the reference? We provide two visual comparison modes while keeping logic minimal and cross‑platform safe.
//   1. Overlay (alpha blend) – best for proportion tracing, only possible when we already decoded the reference into a ui.Image (native platforms; web if CORS allowed and decode succeeded).
//   2. Side‑by‑side – universal fallback (always works, including web when we only have a network URL and cannot access pixel bytes for overlay).
// DESIGN CONSTRAINTS:
// - We NEVER attempt to decode the image here; decoding responsibility lives upstream (search/practice flow) to keep this screen pure display.
// - If reference decoding failed or we are on web with URL‑only access, overlay is disabled and UI hides overlay‑specific controls to reduce confusion.
// - Painter does scaling (contain) so both images retain aspect ratio without distortion.
// READABILITY STRATEGY:
// - Split UI: controls row builder vs comparison area builder.
// - Early return inside comparison builder for fallback path.
// - Small focused stateless widgets with descriptive names.

class ReviewScreen extends StatefulWidget {
  final ui.Image? reference; // may be null when only URL available (web)
  final String? referenceUrl; // raw network fallback (web only side-by-side)
  final ui.Image drawing;
  final String sourceUrl;
  final OverlayTransform? initialOverlay; // persisted transform
  final bool sessionControls; // show Next/Finish and pop result
  final bool isLast; // label the action as Finish
  const ReviewScreen({
    super.key,
    required this.reference,
    this.referenceUrl,
    required this.drawing,
    required this.sourceUrl,
    this.initialOverlay,
    this.sessionControls = false,
    this.isLast = false,
  });
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool overlay = true;
  double refOpacity = 0.6;
  double drawOpacity = 1.0;
  double _scale = 1.0;
  Offset _offset = Offset.zero;

  @override
  void initState() {
    super.initState();
    if (widget.initialOverlay != null) {
      _scale = widget.initialOverlay!.scale;
      _offset = widget.initialOverlay!.offset;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review'),
        actions: [
          if (widget.sessionControls)
            TextButton(
              onPressed: () {
                final res = ReviewResult(
                  action: widget.isLast ? ReviewAction.end : ReviewAction.next,
                  overlay: OverlayTransform(scale: _scale, offset: _offset),
                );
                Navigator.of(context).pop(res);
              },
              child: Text(widget.isLast ? 'Finish' : 'Next'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.all(8), child: _buildControls()),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _buildComparison(),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI Helpers -----------------------------------------------------------

  Widget _buildControls() {
    final hasDecodedRef = widget.reference != null;
    final hasUrlRef = widget.referenceUrl != null;
    final overlayCapable =
        hasDecodedRef ||
        hasUrlRef; // new: URL-only overlay allowed via stacking widgets
    if (!overlayCapable && overlay) {
      overlay = false; // force side-by-side if neither available
    }
    return Row(
      children: [
        if (overlayCapable)
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Overlay')),
              ButtonSegment(value: false, label: Text('Side-by-side')),
            ],
            selected: {overlay},
            onSelectionChanged: (v) => setState(() => overlay = v.first),
          )
        else
          const Text('Side-by-side only', style: TextStyle(fontSize: 12)),
        const Spacer(),
        if (overlayCapable)
          _OpacitySlider(
            label: 'Ref',
            value: refOpacity,
            onChanged: (v) => setState(() => refOpacity = v),
          ),
        if (overlayCapable) const SizedBox(width: 12),
        _OpacitySlider(
          label: 'Draw',
          value: drawOpacity,
          onChanged: (v) => setState(() => drawOpacity = v),
        ),
      ],
    );
  }

  Widget _buildComparison() {
    // Cases order:
    // 1. URL-only + overlay -> widget stack overlay (no pixel access).
    // 2. Decoded + overlay -> painter overlay (pixel accurate).
    // 3. URL-only + side-by-side -> fallback.
    // 4. Decoded + side-by-side -> decoded compare.
    if (overlay) {
      // Wrap overlay modes in an interactive container that supports
      // pinch-to-zoom, two-finger pan, ctrl+drag pan, and ctrl+wheel zoom.
      if (widget.reference == null && widget.referenceUrl != null) {
        return _InteractiveUrlOverlay(
          refChild: Image.network(widget.referenceUrl!, fit: BoxFit.contain),
          drawImg: widget.drawing,
          refOpacity: refOpacity,
          drawOpacity: drawOpacity,
          initial: widget.initialOverlay,
          onTransform: (s, o) {
            _scale = s;
            _offset = o;
            if (!widget.sessionControls) {
              context.read<SessionService>().updateLastOverlay(
                OverlayTransform(scale: s, offset: o),
              );
            }
          },
        );
      }
      if (widget.reference != null) {
        return _InteractiveDecodedOverlay(
          refImg: widget.reference!,
          drawImg: widget.drawing,
          refOpacity: refOpacity,
          drawOpacity: drawOpacity,
          initial: widget.initialOverlay,
          onTransform: (s, o) {
            _scale = s;
            _offset = o;
            if (!widget.sessionControls) {
              context.read<SessionService>().updateLastOverlay(
                OverlayTransform(scale: s, offset: o),
              );
            }
          },
        );
      }
    }
    return ReferenceDrawSplit(
      referenceImage: widget.reference,
      referenceUrl: widget.referenceUrl,
      letterboxReference: true,
      letterboxDrawing: true,
      drawingChild: LetterboxedImage(
        image: widget.drawing,
        background: kPaperColor,
      ),
    );
  }
}

// overlay painter below handles decoded overlay painting when needed.

// Displays a decoded ui.Image scaled to fit while preserving aspect ratio with optional opacity.
// Removed _FittedImage in favor of shared LetterboxedImage.

// Compact labeled opacity slider used for both reference & drawing channels.
class _OpacitySlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  const _OpacitySlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        SizedBox(
          width: 120,
          child: Slider(value: value, min: 0, max: 1, onChanged: onChanged),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _OverlayPainter extends CustomPainter {
  final ui.Image refImg, drawImg;
  final double refOpacity, drawOpacity;
  _OverlayPainter(this.refImg, this.drawImg, this.refOpacity, this.drawOpacity);
  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    // Unified scaling: pick a scale that fits BOTH images entirely while
    // preserving each intrinsic aspect ratio, then center them. This keeps
    // their relative proportions consistent (no stretching of the drawing
    // relative to the reference).
    // (Intrinsic sizes accessed via image.width/height in rectFor; no locals needed.)
    // We fit the bounding box that must contain both; simplest is to compute
    // individual uniform scales then take the min.
    double scaleFor(ui.Image img) {
      final iw = img.width.toDouble(), ih = img.height.toDouble();
      final sx = size.width / iw;
      final sy = size.height / ih;
      return math.min(sx, sy);
    }

    final sRef = scaleFor(refImg);
    final sDraw = scaleFor(drawImg);
    final s = math.min(sRef, sDraw); // ensures both fit simultaneously
    Rect rectFor(ui.Image img) {
      final w = img.width * s;
      final h = img.height * s;
      return Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
    }

    final refRect = rectFor(refImg);
    final drawRect = rectFor(drawImg);
    _draw(canvas, refImg, refRect, refOpacity); // reference bottom
    _draw(canvas, drawImg, drawRect, drawOpacity); // drawing top
  }

  // (Legacy _fit removed after unified scaling implementation.)

  void _draw(ui.Canvas c, ui.Image img, Rect dst, double opacity) {
    // SaveLayer with a white color having variable alpha lets us modulate
    // opacity without allocating a new image or shader: GPU blends during
    // layer compositing.
    final src = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    final p = ui.Paint()
      ..color = Color.fromARGB((opacity * 255).round(), 255, 255, 255);
    c.saveLayer(dst, p);
    c.drawImageRect(img, src, dst, ui.Paint());
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) =>
      old.refImg != refImg ||
      old.drawImg != drawImg ||
      old.refOpacity != refOpacity ||
      old.drawOpacity != drawOpacity;
}

// Overlay for URL-only reference (no decoded pixels). We simply stack the
// network image and drawing image; no per-pixel operations (color pick, diff)
// are possible in this path.
// URL-overlay legacy implementation removed; interactive variant below.

// Interactive overlay that keeps the reference fixed and only transforms
// the drawing layer. This is the desired behavior for users overlaying
// their drawing to match the reference.
class _InteractiveDecodedOverlay extends StatefulWidget {
  final ui.Image refImg;
  final ui.Image drawImg;
  final double refOpacity, drawOpacity;
  final OverlayTransform? initial;
  final void Function(double scale, Offset offset)? onTransform;
  const _InteractiveDecodedOverlay({
    required this.refImg,
    required this.drawImg,
    required this.refOpacity,
    required this.drawOpacity,
    this.initial,
    this.onTransform,
  });
  @override
  State<_InteractiveDecodedOverlay> createState() =>
      _InteractiveDecodedOverlayState();
}

class _InteractiveDecodedOverlayState
    extends State<_InteractiveDecodedOverlay> {
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _baseScale = 1.0;
  Offset _baseOffset = Offset.zero;
  Offset? _startFocal;
  bool _mousePanning = false;
  Offset? _lastMousePos;

  static const double _minScale = 0.2;
  static const double _maxScale = 10.0;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _scale = widget.initial!.scale;
      _offset = widget.initial!.offset;
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseScale = _scale;
    _baseOffset = _offset;
    _startFocal = details.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_startFocal == null) _startFocal = details.focalPoint;
    final s = details.scale;
    final newScale = (_baseScale * s).clamp(_minScale, _maxScale);
    final anchor = details.focalPoint;
    final newOffset = anchor - (_startFocal! - _baseOffset) * s;
    setState(() {
      _scale = newScale;
      _offset = newOffset;
    });
    widget.onTransform?.call(_scale, _offset);
  }

  void _onScaleEnd(ScaleEndDetails _) {
    _startFocal = null;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final focal = event.localPosition;
      final delta = event.scrollDelta.dy;
      final factor = math.pow(1.0015, -delta);
      final newScale = (_scale * factor).clamp(_minScale, _maxScale);
      final scaleRatio = newScale / _scale;
      final newOffset = focal - (focal - _offset) * scaleRatio;
      setState(() {
        _scale = newScale;
        _offset = newOffset;
      });
      widget.onTransform?.call(_scale, _offset);
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.mouse &&
        (e.buttons & kPrimaryButton) != 0) {
      _mousePanning = true;
      _lastMousePos = e.position;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_mousePanning && _lastMousePos != null) {
      final delta = e.position - _lastMousePos!;
      setState(() {
        _offset += delta;
        _lastMousePos = e.position;
      });
      widget.onTransform?.call(_scale, _offset);
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _mousePanning = false;
    _lastMousePos = null;
  }

  @override
  Widget build(BuildContext context) {
    final drawMatrix = Matrix4.identity()
      ..translate(_offset.dx, _offset.dy)
      ..scale(_scale, _scale);
    return Listener(
      onPointerSignal: _onPointerSignal,
      onPointerDown: (e) {
        // Prevent default browser behaviors by consuming events here
        _onPointerDown(e);
      },
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (_) {}, // consume to suppress context menu
        onTapDown: (_) {}, // consume image clicks during panning
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Reference fixed
            Opacity(
              opacity: widget.refOpacity,
              child: FittedBox(
                fit: BoxFit.contain,
                child: RawImage(image: widget.refImg),
              ),
            ),
            // Drawing transformed
            Opacity(
              opacity: widget.drawOpacity,
              child: Transform(
                transform: drawMatrix,
                alignment: Alignment.topLeft,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: RawImage(image: widget.drawImg),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractiveUrlOverlay extends StatefulWidget {
  final Widget refChild; // already built Image widget for network ref
  final ui.Image drawImg;
  final double refOpacity, drawOpacity;
  final OverlayTransform? initial;
  final void Function(double scale, Offset offset)? onTransform;
  const _InteractiveUrlOverlay({
    required this.refChild,
    required this.drawImg,
    required this.refOpacity,
    required this.drawOpacity,
    this.initial,
    this.onTransform,
  });
  @override
  State<_InteractiveUrlOverlay> createState() => _InteractiveUrlOverlayState();
}

class _InteractiveUrlOverlayState extends State<_InteractiveUrlOverlay> {
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _baseScale = 1.0;
  Offset _baseOffset = Offset.zero;
  Offset? _startFocal;
  bool _mousePanning = false;
  Offset? _lastMousePos;

  static const double _minScale = 0.2;
  static const double _maxScale = 10.0;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _scale = widget.initial!.scale;
      _offset = widget.initial!.offset;
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseScale = _scale;
    _baseOffset = _offset;
    _startFocal = details.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_startFocal == null) _startFocal = details.focalPoint;
    final s = details.scale;
    final newScale = (_baseScale * s).clamp(_minScale, _maxScale);
    final anchor = details.focalPoint;
    final newOffset = anchor - (_startFocal! - _baseOffset) * s;
    setState(() {
      _scale = newScale;
      _offset = newOffset;
    });
    widget.onTransform?.call(_scale, _offset);
  }

  void _onScaleEnd(ScaleEndDetails _) {
    _startFocal = null;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final focal = event.localPosition;
      final delta = event.scrollDelta.dy;
      final factor = math.pow(1.0015, -delta);
      final newScale = (_scale * factor).clamp(_minScale, _maxScale);
      final scaleRatio = newScale / _scale;
      final newOffset = focal - (focal - _offset) * scaleRatio;
      setState(() {
        _scale = newScale;
        _offset = newOffset;
      });
      widget.onTransform?.call(_scale, _offset);
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.mouse &&
        (e.buttons & kPrimaryButton) != 0) {
      _mousePanning = true;
      _lastMousePos = e.position;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_mousePanning && _lastMousePos != null) {
      final delta = e.position - _lastMousePos!;
      setState(() {
        _offset += delta;
        _lastMousePos = e.position;
      });
      widget.onTransform?.call(_scale, _offset);
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _mousePanning = false;
    _lastMousePos = null;
  }

  @override
  Widget build(BuildContext context) {
    final drawMatrix = Matrix4.identity()
      ..translate(_offset.dx, _offset.dy)
      ..scale(_scale, _scale);
    return Listener(
      onPointerSignal: _onPointerSignal,
      onPointerDown: (e) {
        _onPointerDown(e);
      },
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (_) {},
        onTapDown: (_) {},
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Prevent browser drag/drop and context interactions on the image
            IgnorePointer(
              ignoring: true,
              child: Opacity(
                opacity: widget.refOpacity,
                child: widget.refChild,
              ),
            ),
            Opacity(
              opacity: widget.drawOpacity,
              child: Transform(
                transform: drawMatrix,
                alignment: Alignment.topLeft,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: RawImage(image: widget.drawImg),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Interactive wrapper that adds pan/zoom gesture handling around any
// overlay widget. It exposes consistent behavior for touch and mouse.
class _InteractiveOverlay extends StatefulWidget {
  final Widget child;
  const _InteractiveOverlay({required this.child});
  @override
  State<_InteractiveOverlay> createState() => _InteractiveOverlayState();
}

class _InteractiveOverlayState extends State<_InteractiveOverlay> {
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _baseScale = 1.0;
  Offset _baseOffset = Offset.zero;
  Offset? _startFocal;
  bool _mousePanning = false;
  Offset? _lastMousePos;

  static const double _minScale = 0.2;
  static const double _maxScale = 10.0;

  void _onScaleStart(ScaleStartDetails details) {
    _baseScale = _scale;
    _baseOffset = _offset;
    _startFocal = details.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_startFocal == null) _startFocal = details.focalPoint;
    final s = details.scale;
    final newScale = (_baseScale * s).clamp(_minScale, _maxScale);
    // anchor math: offset_t = F_t - s*(F0 - offset0)
    final anchor = details.focalPoint;
    final newOffset = anchor - (_startFocal! - _baseOffset) * s;
    setState(() {
      _scale = newScale;
      _offset = newOffset;
    });
  }

  void _onScaleEnd(ScaleEndDetails _) {
    _startFocal = null;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final isCtrl = HardwareKeyboard.instance.isControlPressed;
      if (!isCtrl) return;
      // Zoom around pointer
      final focal = event.localPosition;
      final delta = event.scrollDelta.dy;
      final factor = math.pow(1.0015, -delta);
      final newScale = (_scale * factor).clamp(_minScale, _maxScale);
      final scaleRatio = newScale / _scale;
      // offset_t = focal - scaleRatio*(focal - offset)
      final newOffset = focal - (focal - _offset) * scaleRatio;
      setState(() {
        _scale = newScale;
        _offset = newOffset;
      });
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    if (isCtrl &&
        e.kind == PointerDeviceKind.mouse &&
        (e.buttons & kPrimaryButton) != 0) {
      _mousePanning = true;
      _lastMousePos = e.position;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_mousePanning && _lastMousePos != null) {
      final delta = e.position - _lastMousePos!;
      setState(() {
        _offset += delta;
        _lastMousePos = e.position;
      });
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _mousePanning = false;
    _lastMousePos = null;
  }

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix4.identity()
      ..translate(_offset.dx, _offset.dy)
      ..scale(_scale, _scale);
    return Focus(
      child: Listener(
        onPointerSignal: _onPointerSignal,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: ClipRect(
            child: Transform(
              transform: matrix,
              alignment: Alignment.topLeft,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

// Legacy side-by-side widgets removed in favor of ReferenceDrawSplit.
