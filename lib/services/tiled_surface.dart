import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' as vm;
import 'linear_blend_shader.dart';
import 'linear_blend_uniform_shader.dart';
import '../theme/colors.dart';

/// Sparse tiled surface storing composited ink.
/// Only tiles touched by brush dabs are rasterized; others stay absent.
/// Keeps per-frame cost bounded by recent activity instead of full canvas size.
class TiledSurface {
  final int tileSize; // Edge length in pixels (power of two preferred)
  final Map<_TileKey, ui.Image> _tiles = {};
  final Map<_TileKey, List<_PendingDab>> _pending = {};
  LinearBlendShader? _shader;
  LinearBlendUniformShader? _uniformShader;
  ui.FragmentProgram? _presentProgram;
  bool useUniforms = true; // toggle for A/B

  TiledSurface({this.tileSize = 256});

  void dispose() {
    for (final img in _tiles.values) {
      img.dispose();
    }
    _tiles.clear();
    _pending.clear();
  }

  void clear() {
    for (final img in _tiles.values) {
      img.dispose();
    }
    _tiles.clear();
    _pending.clear();
  }

  /// Queue a dab for later flush. The same dab may touch multiple tiles.
  void addDab(ui.Offset center, double radius, ui.Color color) {
    final left = center.dx - radius;
    final top = center.dy - radius;
    final right = center.dx + radius;
    final bottom = center.dy + radius;
    final minTileX = (left / tileSize).floor();
    final maxTileX = (right / tileSize).floor();
    final minTileY = (top / tileSize).floor();
    final maxTileY = (bottom / tileSize).floor();
    for (var ty = minTileY; ty <= maxTileY; ty++) {
      for (var tx = minTileX; tx <= maxTileX; tx++) {
        final key = _TileKey(tx, ty);
        (_pending[key] ??= []).add(
          _PendingDab(
            center,
            radius,
            color,
            tileOrigin: ui.Offset(
              tx * tileSize.toDouble(),
              ty * tileSize.toDouble(),
            ),
          ),
        );
      }
    }
  }

  bool get hasPending => _pending.isNotEmpty;

  /// Flush all queued dabs into their tiles. Small tiles keep work distribution smooth.
  Future<void> flush() async {
    if (_pending.isEmpty) return;
    if (useUniforms) {
      _uniformShader ??= await LinearBlendUniformShader.load();
    } else {
      _shader ??= await LinearBlendShader.load();
    }
    _presentProgram ??= await ui.FragmentProgram.fromAsset(
      'shaders/present_tile_over_paper.frag',
    );
    final futures = <Future<void>>[];
    _pending.forEach((key, list) {
      futures.add(_rasterizeTile(key, list));
    });
    _pending.clear();
    await Future.wait(futures);
  }

  Future<void> _rasterizeTile(_TileKey key, List<_PendingDab> dabs) async {
    if (useUniforms && _uniformShader != null) {
      final shader = _uniformShader!;
      final groups = <int, List<_PendingDab>>{}; // color value -> dabs
      for (final d in dabs) {
        (groups[d.color.value] ??= []).add(d);
      }
      ui.Image? tile = _tiles[key];
      for (final entry in groups.entries) {
        final color = ui.Color(entry.key);
        final payload = entry.value
            .map(
              (e) => DabUniform(
                e.center.dx - e.tileOrigin.dx,
                e.center.dy - e.tileOrigin.dy,
                e.radius,
                e.color.a, // already 0..1 per Color invariant
              ),
            )
            .toList(growable: false);
        tile = await shader.blendOntoTile(
          existing: tile,
          dabs: payload,
          tileSize: tileSize,
          brushColor: color,
          hardness: 1.0,
        );
      }
      final old = _tiles[key];
      if (old != null && old != tile) old.dispose();
      if (tile != null) _tiles[key] = tile;
      return;
    }

    final shader = _shader;
    if (shader != null) {
      // Group dabs by color to avoid per-dab color changes within one pass.
      final groups = <int, List<_PendingDab>>{}; // color value -> dabs
      for (final d in dabs) {
        (groups[d.color.value] ??= []).add(d);
      }
      ui.Image? tile = _tiles[key];
      for (final entry in groups.entries) {
        final color = ui.Color(entry.key);
        final payload = entry.value
            .map(
              (e) => DabPayload(
                e.center - e.tileOrigin,
                e.radius,
                e.color.a, // already 0..1 per Color invariant
              ),
            )
            .toList(growable: false);
        tile = await shader.blendOntoTile(
          existing: tile,
          dabs: payload,
          tileSize: tileSize,
          brushColor: color,
          hardness: 1.0,
        );
      }
      final old = _tiles[key];
      if (old != null && old != tile) old.dispose();
      if (tile != null) _tiles[key] = tile;
      return;
    }
    final ts = tileSize.toDouble();
    final recorder = ui.PictureRecorder();
    final rect = ui.Rect.fromLTWH(0, 0, ts, ts);
    final canvas = ui.Canvas(recorder, rect);
    final existing = _tiles[key];
    if (existing != null) {
      canvas.drawImage(existing, ui.Offset.zero, ui.Paint());
    }
    final paint = ui.Paint()..isAntiAlias = true;
    for (final d in dabs) {
      // Convert to tile local coordinates
      final local = d.center - d.tileOrigin;
      paint.color = d.color;
      // Simple analytic circle; softness currently handled by StrokeLayer before baking.
      canvas.drawCircle(local, d.radius, paint);
    }
    final pic = recorder.endRecording();
    final img = await pic.toImage(tileSize, tileSize);
    existing?.dispose();
    _tiles[key] = img;
  }

  /// Draw all tiles by simple blit. Assumes caller sets up transform for viewport.
  void draw(ui.Canvas canvas) {
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
    final present = _presentProgram?.fragmentShader();
    final hasPresent = present != null;

    vm.Vector3 srgbToLinear(vm.Vector3 c) {
      double conv(double v) {
        // v is in 0..1
        if (v <= 0.04045) return v / 12.92;
        return math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      }

      return vm.Vector3(conv(c.x), conv(c.y), conv(c.z));
    }

    final paperColorLin = srgbToLinear(
      vm.Vector3(kPaperColor.r, kPaperColor.g, kPaperColor.b),
    );

    _tiles.forEach((key, img) {
      final dx = key.x * tileSize.toDouble();
      final dy = key.y * tileSize.toDouble();
      if (hasPresent) {
        // Use present shader to composite over paper in linear space, output opaque
        final rect = ui.Rect.fromLTWH(
          dx,
          dy,
          tileSize.toDouble(),
          tileSize.toDouble(),
        );
        present.setImageSampler(0, img);
        present.setFloat(0, tileSize.toDouble());
        // Paper color (sRGB) from theme kPaperColor
        final pc = paperColorLin; // requires theme import
        present.setFloat(1, pc.r);
        present.setFloat(2, pc.g);
        present.setFloat(3, pc.b);
        final sp = ui.Paint()
          ..shader = present
          ..blendMode = ui.BlendMode.src;
        canvas.drawRect(rect, sp);
      } else {
        canvas.save();
        canvas.translate(dx, dy);
        canvas.clipRect(
          ui.Rect.fromLTWH(0, 0, tileSize.toDouble(), tileSize.toDouble()),
          doAntiAlias: false,
        );
        canvas.drawImage(img, ui.Offset.zero, paint);
        canvas.restore();
      }
    });
  }

  /// Composite tiles + optional live stroke into a new image of given size.
  Future<ui.Image> toImage(
    int width,
    int height, {
    void Function(ui.Canvas)? drawExtra,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    draw(canvas); // all tiles
    if (drawExtra != null) drawExtra(canvas);
    final pic = recorder.endRecording();
    return pic.toImage(width, height);
  }
}

class _TileKey {
  final int x, y;
  const _TileKey(this.x, this.y);
  @override
  bool operator ==(Object other) =>
      other is _TileKey && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}

class _PendingDab {
  final ui.Offset center;
  final double radius;
  final ui.Color color;
  final ui.Offset tileOrigin;
  _PendingDab(this.center, this.radius, this.color, {required this.tileOrigin});
}
