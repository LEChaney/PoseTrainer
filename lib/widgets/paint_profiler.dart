import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import '../services/debug_profiler.dart';

/// PaintProfiler
/// Wrap any subtree to profile how long its paint pass takes on the UI thread.
/// Uses a RenderProxyBox that times paint() and reports duration to DebugProfiler
/// under the provided [label]. Keep scope small to avoid overhead.
class PaintProfiler extends SingleChildRenderObjectWidget {
  final DebugProfiler profiler;
  final String label;

  const PaintProfiler({
    super.key,
    required this.profiler,
    required this.label,
    required Widget child,
  }) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPaintProfiler(profiler, label);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderPaintProfiler renderObject,
  ) {
    renderObject
      ..profiler = profiler
      ..label = label;
  }
}

class _RenderPaintProfiler extends RenderProxyBox {
  DebugProfiler _profiler;
  String _label;
  _RenderPaintProfiler(this._profiler, this._label);

  set profiler(DebugProfiler v) => _profiler = v;
  set label(String v) => _label = v;

  @override
  void paint(PaintingContext context, Offset offset) {
    final sw = Stopwatch()..start();
    super.paint(context, offset);
    sw.stop();
    _profiler.noteSubtreePaint(_label, sw.elapsedMicroseconds / 1000.0);
  }
}
