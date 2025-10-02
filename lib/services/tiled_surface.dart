import 'dart:ui' as ui;
import 'debug_profiler.dart';
import 'dab_renderer.dart';
import 'brush_engine.dart'; // for Dab class
import 'debug_logger.dart';
import 'dart:async';
import 'dart:typed_data';

/// Sparse tiled surface storing composited ink.
/// Only tiles touched by brush dabs are rasterized; others stay absent.
/// Keeps per-frame cost bounded by recent activity instead of full canvas size.
class TiledSurface {
  final int tileSize; // Edge length in pixels (power of two preferred)
  final Map<_TileKey, ui.Image> _tiles = {};
  final DebugProfiler? profiler;
  int _dabLogCount = 0; // Count of dabs processed (for logging)
  ui.FragmentProgram? _pressureDabProgram; // lazy-loaded shader

  TiledSurface({this.tileSize = 256, this.profiler});

  /// Lazily load the pressure dab shader.
  Future<void> _ensureShader() async {
    if (_pressureDabProgram != null) return;
    try {
      _pressureDabProgram = await ui.FragmentProgram.fromAsset(
        'shaders/pressure_dab.frag',
      );
    } catch (e) {
      warningLog(
        'Failed to load pressure_dab.frag, falling back to CPU dabs: $e',
        tag: 'TiledSurface',
      );
    }
  }

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

  /// Blend tiles from another tiled surface onto this one using standard SrcOver,
  /// scaling the source alpha by [opacityScale] (0..1). This is used to commit the
  /// current stroke layer into the base canvas according to the global brush opacity.
  Future<void> blendFrom(TiledSurface src, {double opacityScale = 1.0}) async {
    if (src._tiles.isEmpty) return;
    final ts = tileSize.toDouble();
    final rect = ui.Rect.fromLTWH(0, 0, ts, ts);
    profiler?.noteTileFlushStart();
    final futures = <Future<void>>[];
    src._tiles.forEach((key, srcImg) {
      futures.add(() async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder, rect);
        final existing = _tiles[key];
        if (existing != null) {
          canvas.drawImage(existing, ui.Offset.zero, ui.Paint());
        }

        // Draw the source tile with alpha scaled by [opacityScale]. We use a sub-layer
        // to multiply alpha (dstIn) before compositing back with SrcOver.
        canvas.saveLayer(rect, ui.Paint());
        canvas.drawImage(srcImg, ui.Offset.zero, ui.Paint());
        // Multiply the layer alpha by opacityScale
        final clamp = opacityScale.clamp(0.0, 1.0).toDouble();
        final mulPaint = ui.Paint()
          ..blendMode = ui.BlendMode.dstIn
          ..color = ui.Color.fromARGB((clamp * 255).round(), 255, 255, 255);
        canvas.drawRect(rect, mulPaint);
        canvas.restore();

        final pic = recorder.endRecording();
        final img = await pic.toImage(tileSize, tileSize);
        existing?.dispose();
        _tiles[key] = img;
      }());
    });
    await Future.wait(futures);
    profiler?.noteTileFlushEnd();
  }

  /// Directly bake a list of dabs into tiles without intermediate pending state.
  /// This simplifies the flow by eliminating the addDab->flush pattern.
  Future<void> bakeDabs(
    List<Dab> dabs,
    double coreRatio, {
    double? maxSizePx,
    double? spacing,
    double? runtimeSizeScale,
  }) async {
    if (dabs.isEmpty) {
      // No need to log empty baking calls (too verbose)
      return;
    }

    profiler?.noteTileFlushStart();

    // Group dabs by affected tiles for batch processing
    final Map<_TileKey, List<_PendingDab>> tileDabs = {};

    for (final dab in dabs) {
      // If both flow and clamp are zero, skip
      if (dab.flow <= 0 || dab.radius <= 0) continue;

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
              dab.flow,
              dab.opacityClamp,
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
      // Reduce per-tile logging (too verbose)
      // debugLog(
      //   'Rasterizing tile (${key.x}, ${key.y}) with ${dabList.length} dabs',
      //   tag: 'TiledSurface',
      // );
      futures.add(
        _rasterizeTile(key, dabList, maxSizePx, spacing, runtimeSizeScale),
      );
    });

    await Future.wait(futures);
    profiler?.noteTileFlushEnd();
  }

  Future<void> _rasterizeTile(
    _TileKey key,
    List<_PendingDab> dabs,
    double? maxSizePx,
    double? spacing,
    double? runtimeSizeScale,
  ) async {
    // Reduce individual tile rasterization logging (too verbose)
    // debugLog(
    //   'Rasterizing tile (${key.x}, ${key.y}) with ${dabs.length} dabs',
    //   tag: 'TiledSurface',
    // );
    final start = DateTime.now().microsecondsSinceEpoch;
    final ts = tileSize.toDouble();
    final rect = ui.Rect.fromLTWH(0, 0, ts, ts);

    // Start with existing tile image (or an empty tile) and iteratively update it per dab
    ui.Image? current = _tiles[key] ?? await _emptyTile();

    for (final d in dabs) {
      final local = d.center - d.tileOrigin; // tile-local center

      // Adaptive log throttling
      int logRate = 100000; // Default rate
      if (maxSizePx != null && spacing != null && runtimeSizeScale != null) {
        final effectiveSize = maxSizePx * runtimeSizeScale;
        final dabsPerPixel = 1.0 / spacing;
        final expectedDabRate = dabsPerPixel / effectiveSize;
        logRate = (101 * expectedDabRate).clamp(50, 1000000).round();
      }
      if (_dabLogCount % logRate == 0) {
        debugLog(
          'Drawing dab at tile-local $local, radius=${d.radius.toStringAsFixed(1)} [logRate=$logRate]',
          tag: 'TiledSurface',
        );
      }
      _dabLogCount++;

      // Prepare a new picture
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder, rect);

      // Try shader path first; fallback to CPU analytic dab (no clamp guarantee)
      await _ensureShader();
      final program = _pressureDabProgram;
      if (program != null) {
        // Build ImageShader from the current accumulated tile
        final mat = Float64List.fromList(<double>[
          1,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          1,
        ]);
        final dstImageShader = ui.ImageShader(
          current!,
          ui.TileMode.clamp,
          ui.TileMode.clamp,
          mat,
          filterQuality: ui.FilterQuality.none,
        );
        final shader = program.fragmentShader();
        // Float uniforms follow declaration order (set individually for older API)
        // GLSL uniform order: u_flow, u_opacity_clamp, u_core_ratio,
        // u_center.x, u_center.y, u_radius, u_resolution.x, u_resolution.y
        shader.setFloat(0, d.flow.clamp(0.0, 1.0)); // u_flow
        shader.setFloat(1, d.opacityClamp.clamp(0.0, 1.0)); // u_opacity_clamp
        shader.setFloat(2, d.coreRatio.clamp(0.0, 1.0)); // u_core_ratio
        shader.setFloat(3, local.dx); // u_center.x (px)
        shader.setFloat(4, local.dy); // u_center.y (px)
        shader.setFloat(5, d.radius); // u_radius (px)
        shader.setFloat(6, ts); // u_resolution.x
        shader.setFloat(7, ts); // u_resolution.y
        // Try to bind the child shader (uniform shader u_dst)
        try {
          // Try binding as sampler2D by setting the image sampler
          shader.setImageSampler(0, current);
        } catch (_) {
          // If image sampler not available, attempt newer API with ImageShader
          try {
            (shader as dynamic).setShader(0, dstImageShader);
          } catch (__) {
            // Give up binding sampler; the shader may fail at runtime
          }
        }

        final paint = ui.Paint()
          ..shader = shader
          ..blendMode = ui.BlendMode.src; // replace with shader output exactly
        // Execute across the whole tile so shader can read/return dst everywhere
        canvas.drawRect(rect, paint);
      } else {
        // Fallback: approximate by drawing a feathered dab with alpha ~= flow * opacityClamp
        if (current != null) {
          canvas.drawImage(current, ui.Offset.zero, ui.Paint());
        }
        final alpha = (d.flow.clamp(0.0, 1.0) * d.opacityClamp.clamp(0.0, 1.0))
            .clamp(0.0, 1.0);
        final a = (alpha * 255).round();
        final centerColor = ui.Color.fromARGB(a, 255, 255, 255);
        drawDabWithColorAndCore(
          canvas,
          local,
          d.radius,
          centerColor,
          d.coreRatio,
        );
      }

      final pic = recorder.endRecording();
      final nextImage = await pic.toImage(tileSize, tileSize);
      if (!identical(current, _tiles[key])) {
        // Dispose intermediate images (keep original _tiles[key] for now, will be disposed after assignment)
        current?.dispose();
      }
      current = nextImage;
    }

    // Replace stored tile with the accumulated result
    final previous = _tiles[key];
    _tiles[key] = current!;
    previous?.dispose();

    final end = DateTime.now().microsecondsSinceEpoch;
    profiler?.noteTileRasterized((end - start) / 1000.0);
  }

  Future<ui.Image> _emptyTile() async {
    final recorder = ui.PictureRecorder();
    // Intentionally empty tile (fully transparent)
    ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, tileSize.toDouble(), tileSize.toDouble()),
    );
    final pic = recorder.endRecording();
    return pic.toImage(tileSize, tileSize);
  }

  /// Draw all tiles by simple blit. Assumes caller sets up transform for viewport.
  void draw(ui.Canvas canvas) {
    // Per-frame tile drawing logging is too verbose
    // debugLog('Drawing ${_tiles.length} tiles', tag: 'TiledSurface');
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
    _tiles.forEach((key, img) {
      // Per-tile drawing logging is too verbose
      // debugLog(
      //   'Drawing tile (${key.x}, ${key.y}) at offset (${key.x * tileSize.toDouble()}, ${key.y * tileSize.toDouble()})',
      //   tag: 'TiledSurface',
      // );
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
  final double flow; // 0..1
  final double opacityClamp; // 0..1
  final double coreRatio;
  final ui.Offset tileOrigin;
  _PendingDab(
    this.center,
    this.radius,
    this.flow,
    this.opacityClamp,
    this.coreRatio, {
    required this.tileOrigin,
  });
}
