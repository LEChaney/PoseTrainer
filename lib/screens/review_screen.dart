import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/letterboxed_image.dart';
import '../widgets/reference_draw_split.dart';

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
  const ReviewScreen({
    super.key,
    required this.reference,
    this.referenceUrl,
    required this.drawing,
    required this.sourceUrl,
  });
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool overlay = true;
  double refOpacity = 0.6;
  double drawOpacity = 1.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
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
      if (widget.reference == null && widget.referenceUrl != null) {
        return _UrlOverlayCompare(
          refUrl: widget.referenceUrl!,
          drawImg: widget.drawing,
          refOpacity: refOpacity,
          drawOpacity: drawOpacity,
        );
      }
      if (widget.reference != null) {
        return _OverlayCompare(
          refImg: widget.reference!,
          drawImg: widget.drawing,
          refOpacity: refOpacity,
          drawOpacity: drawOpacity,
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

class _OverlayCompare extends StatelessWidget {
  final ui.Image refImg, drawImg;
  final double refOpacity, drawOpacity;
  const _OverlayCompare({
    required this.refImg,
    required this.drawImg,
    required this.refOpacity,
    required this.drawOpacity,
  });
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OverlayPainter(refImg, drawImg, refOpacity, drawOpacity),
      size: Size.infinite,
    );
  }
}

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
class _UrlOverlayCompare extends StatelessWidget {
  final String refUrl;
  final ui.Image drawImg;
  final double refOpacity, drawOpacity;
  const _UrlOverlayCompare({
    required this.refUrl,
    required this.drawImg,
    required this.refOpacity,
    required this.drawOpacity,
  });
  @override
  Widget build(BuildContext context) {
    // We cannot know the reference intrinsic size synchronously; using two
    // independent FittedBox instances with the same fit preserves each aspect
    // without stretching the drawing relative to the reference. (Unified scale
    // exactly requires both intrinsic sizes; acceptable compromise here.)
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: refOpacity,
          child: FittedBox(fit: BoxFit.contain, child: Image.network(refUrl)),
        ),
        Opacity(
          opacity: drawOpacity,
          child: FittedBox(
            fit: BoxFit.contain,
            child: RawImage(image: drawImg),
          ),
        ),
      ],
    );
  }
}

// Legacy side-by-side widgets removed in favor of ReferenceDrawSplit.
