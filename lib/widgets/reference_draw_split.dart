import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../constants/layout.dart';
import '../theme/colors.dart';
import 'letterboxed_image.dart';

/// Shared responsive layout for reference + drawing areas.
/// Responsibilities:
/// - Wide mode: Row with reference panel, vertical divider, drawing panel.
/// - Narrow mode: Column with reference panel, horizontal divider, drawing panel.
/// - Snaps drawing logical dimensions so width/height * dpr is integral.
/// - Provides unified theming (reference dark, drawing paper) unless
///   custom builders override.
class ReferenceDrawSplit extends StatelessWidget {
  final ui.Image? referenceImage; // decoded reference (optional)
  final String? referenceUrl; // network reference if decoded not available
  final Widget drawingChild; // canvas or review drawing widget
  final Widget? overlayTopRight; // e.g., sliders in practice
  final Widget? drawingOverlay; // overlay anchored within drawing area only
  final Widget? leftRail; // optional fixed UI column on far left (wide only)
  final bool letterboxReference;
  final bool letterboxDrawing;

  const ReferenceDrawSplit({
    super.key,
    required this.referenceImage,
    required this.referenceUrl,
    required this.drawingChild,
    this.overlayTopRight,
    this.drawingOverlay,
    this.leftRail,
    this.letterboxReference = true,
    this.letterboxDrawing = false,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > kWideLayoutBreakpoint;
        // Compute snapped drawing logical size depending on orientation.
        if (isWide) {
          final rawCanvasLogicalW =
              constraints.maxWidth * kCanvasFraction - kDividerThickness;
          final snappedCanvasLogicalW = _snap(rawCanvasLogicalW, dpr);
          final snappedCanvasLogicalH = _snap(constraints.maxHeight, dpr);
          // Reserve space for an optional left rail without overlapping reference
          // Rail sits flush (no extra padding).
          final leftRailCoreW = leftRail == null ? 0.0 : 48.0;
          final leftRailW = leftRailCoreW;
          final refLogicalW =
              constraints.maxWidth -
              kDividerThickness -
              snappedCanvasLogicalW -
              leftRailW;
          final drawingSizedBox = SizedBox(
            width: snappedCanvasLogicalW,
            height: snappedCanvasLogicalH,
            child: Stack(
              children: [
                _wrapDrawing(snappedCanvasLogicalW, snappedCanvasLogicalH),
                if (drawingOverlay != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: drawingOverlay!,
                    ),
                  ),
              ],
            ),
          );
          final refWidget = _buildReference();
          final row = Row(
            children: [
              if (leftRail != null)
                ConstrainedBox(
                  constraints: BoxConstraints.tightFor(
                    width: leftRailCoreW,
                    height: constraints.maxHeight,
                  ),
                  child: leftRail!,
                ),
              SizedBox(width: refLogicalW, child: refWidget),
              const VerticalDivider(width: kDividerThickness),
              drawingSizedBox,
            ],
          );
          return _withOverlay(row);
        } else {
          final rawCanvasLogicalH =
              constraints.maxHeight * kCanvasFraction - kDividerThickness;
          final snappedCanvasLogicalW = _snap(constraints.maxWidth, dpr);
          final snappedCanvasLogicalH = _snap(rawCanvasLogicalH, dpr);
          final refLogicalH =
              constraints.maxHeight - kDividerThickness - snappedCanvasLogicalH;
          final drawingSizedBox = SizedBox(
            width: snappedCanvasLogicalW,
            height: snappedCanvasLogicalH,
            child: Stack(
              children: [
                _wrapDrawing(snappedCanvasLogicalW, snappedCanvasLogicalH),
                if (drawingOverlay != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: drawingOverlay!,
                  ),
              ],
            ),
          );
          final refWidget = _buildReference();
          final col = Column(
            children: [
              SizedBox(height: refLogicalH, child: refWidget),
              const Divider(
                height: kDividerThickness,
                thickness: kDividerThickness,
              ),
              drawingSizedBox,
            ],
          );
          return _withOverlay(col);
        }
      },
    );
  }

  Widget _withOverlay(Widget child) {
    if (overlayTopRight == null) return child;
    return Stack(
      children: [
        child,
        Positioned(top: 8, right: 8, child: overlayTopRight!),
      ],
    );
  }

  Widget _buildReference() {
    Widget inner;
    if (referenceImage != null) {
      inner = letterboxReference
          ? LetterboxedImage(
              image: referenceImage!,
              background: kReferencePanelColor,
            )
          : RawImage(image: referenceImage!);
    } else if (referenceUrl != null) {
      inner = Image.network(
        referenceUrl!,
        fit: BoxFit.contain,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        filterQuality: FilterQuality.high,
        // For web scenarios where direct decoding not possible.
      );
    } else {
      inner = const Center(child: Text('No reference'));
    }
    return DecoratedBox(
      decoration: const BoxDecoration(color: kReferencePanelColor),
      child: Center(child: inner),
    );
  }

  Widget _wrapDrawing(double logicalW, double logicalH) {
    if (!letterboxDrawing) return drawingChild;
    // Drawing letterboxing: expect a widget that paints full available size.
    return DecoratedBox(
      decoration: const BoxDecoration(color: kPaperColor),
      child: drawingChild,
    );
  }
}

double _snap(double logical, double dpr) => (logical * dpr).floor() / dpr;
