import 'dart:ui' as ui;

/// Sparse tiled surface storing composited ink.
/// Only tiles touched by brush dabs are rasterized; others stay absent.
/// Keeps per-frame cost bounded by recent activity instead of full canvas size.
class TiledSurface {
  final int tileSize; // Edge length in pixels (power of two preferred)
  final Map<_TileKey, ui.Image> _tiles = {};
  final Map<_TileKey, List<_PendingDab>> _pending = {};

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
    final futures = <Future<void>>[];
    _pending.forEach((key, list) {
      futures.add(_rasterizeTile(key, list));
    });
    _pending.clear();
    await Future.wait(futures);
  }

  Future<void> _rasterizeTile(_TileKey key, List<_PendingDab> dabs) async {
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
    _tiles.forEach((key, img) {
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
  final ui.Offset tileOrigin;
  _PendingDab(this.center, this.radius, this.color, {required this.tileOrigin});
}
