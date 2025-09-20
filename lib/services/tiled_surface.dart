import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'debug_profiler.dart';
import 'dab_renderer.dart';
import 'brush_engine.dart'; // for Dab class

/// Sparse tiled surface storing composited ink.
/// Only tiles touched by brush dabs are rasterized; others stay absent.
/// Keeps per-frame cost bounded by recent activity instead of full canvas size.
class TiledSurface {
  final int tileSize; // Edge length in pixels (power of two preferred)
  final Map<_TileKey, ui.Image> _tiles = {};
  final DebugProfiler? profiler;

  TiledSurface({this.tileSize = 256, this.profiler});

  void dispose() {
    for (final img in _tiles.values) {
      img.dispose();
    }
    _tiles.clear();
  }

  void clear() {
    for (final img in _tiles.values) {
      img.dispose();
    }
    _tiles.clear();
  }

  /// Directly bake a list of dabs into tiles without intermediate pending state.
  /// This simplifies the flow by eliminating the addDab->flush pattern.
  Future<void> bakeDabs(List<Dab> dabs, double coreRatio) async {
    if (dabs.isEmpty) {
      debugPrint('[TiledSurface] bakeDabs: no dabs to bake');
      return;
    }

    debugPrint('[TiledSurface] Baking ${dabs.length} dabs directly to tiles');
    profiler?.noteTileFlushStart();

    // Group dabs by affected tiles for batch processing
    final Map<_TileKey, List<_PendingDab>> tileDabs = {};

    for (final dab in dabs) {
      final a = (dab.alpha * 255).clamp(0, 255).round();
      if (a == 0) continue;

      final color = ui.Color.fromARGB(a, 255, 255, 255);
      final left = dab.center.dx - dab.radius;
      final top = dab.center.dy - dab.radius;
      final right = dab.center.dx + dab.radius;
      final bottom = dab.center.dy + dab.radius;

      final minTileX = (left / tileSize).floor();
      final maxTileX = (right / tileSize).floor();
      final minTileY = (top / tileSize).floor();
      final maxTileY = (bottom / tileSize).floor();

      for (var ty = minTileY; ty <= maxTileY; ty++) {
        for (var tx = minTileX; tx <= maxTileX; tx++) {
          final key = _TileKey(tx, ty);
          final tileOrigin = ui.Offset(
            tx * tileSize.toDouble(),
            ty * tileSize.toDouble(),
          );
          (tileDabs[key] ??= []).add(
            _PendingDab(
              dab.center,
              dab.radius,
              color,
              coreRatio,
              tileOrigin: tileOrigin,
            ),
          );
        }
      }
    }

    // Rasterize affected tiles in parallel
    final futures = <Future<void>>[];
    tileDabs.forEach((key, dabList) {
      debugPrint(
        '[TiledSurface] Rasterizing tile (${key.x}, ${key.y}) with ${dabList.length} dabs',
      );
      futures.add(_rasterizeTile(key, dabList));
    });

    await Future.wait(futures);
    debugPrint(
      '[TiledSurface] Baking complete, now have ${_tiles.length} total tiles',
    );
    profiler?.noteTileFlushEnd();
  }

  Future<void> _rasterizeTile(_TileKey key, List<_PendingDab> dabs) async {
    debugPrint(
      '[TiledSurface] Rasterizing tile (${key.x}, ${key.y}) with ${dabs.length} dabs',
    );
    final start = DateTime.now().microsecondsSinceEpoch;
    final ts = tileSize.toDouble();
    final recorder = ui.PictureRecorder();
    final rect = ui.Rect.fromLTWH(0, 0, ts, ts);
    final canvas = ui.Canvas(recorder, rect);
    final existing = _tiles[key];
    if (existing != null) {
      debugPrint('[TiledSurface] Building on existing tile');
      canvas.drawImage(existing, ui.Offset.zero, ui.Paint());
    }
    for (final d in dabs) {
      // Convert to tile local coordinates
      final local = d.center - d.tileOrigin;
      debugPrint(
        '[TiledSurface] Drawing dab at tile-local ${local}, radius=${d.radius.toStringAsFixed(1)}',
      );
      // Render a radial alpha mask using a hard core up to coreRatio, then linear fade to edge
      drawFeatheredDab(canvas, local, d.radius, d.color, d.coreRatio);
    }
    final pic = recorder.endRecording();
    final img = await pic.toImage(tileSize, tileSize);
    existing?.dispose();
    debugPrint(
      '[TiledSurface] Tile (${key.x}, ${key.y}) rasterized successfully',
    );
    _tiles[key] = img;
    final end = DateTime.now().microsecondsSinceEpoch;
    profiler?.noteTileRasterized((end - start) / 1000.0);
  }

  /// Draw all tiles by simple blit. Assumes caller sets up transform for viewport.
  void draw(ui.Canvas canvas) {
    debugPrint('[TiledSurface] Drawing ${_tiles.length} tiles');
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
    _tiles.forEach((key, img) {
      debugPrint(
        '[TiledSurface] Drawing tile (${key.x}, ${key.y}) at offset (${key.x * tileSize.toDouble()}, ${key.y * tileSize.toDouble()})',
      );
      canvas.drawImage(
        img,
        ui.Offset(key.x * tileSize.toDouble(), key.y * tileSize.toDouble()),
        paint,
      );
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
  final double coreRatio;
  final ui.Offset tileOrigin;
  _PendingDab(
    this.center,
    this.radius,
    this.color,
    this.coreRatio, {
    required this.tileOrigin,
  });
}
