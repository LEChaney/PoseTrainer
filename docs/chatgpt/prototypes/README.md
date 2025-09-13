# Prototype Reference Code

This folder contains **reference-only** prototype snippets extracted from the earlier ChatGPT conversation. They are **not** integrated into the production `lib/` tree and may intentionally skip polishing, tests, or style conformance.

## Files
- `prototype_minimal_brush.dart` – Self-contained minimal low-latency brush demo (drawAtlas + One-Euro + spacing). Useful to recall the pure Flutter approach before adding app structure.
- `prototype_first_playable.dart` – Expanded demo adding e621 search, practice canvas, review (overlay / side-by-side) and in-memory history. Provided for architectural reference; not guaranteed to compile without adjustments (line breaks & formatting were condensed for brevity during extraction).

## Usage
If you want to experiment with one:
1. Copy the relevant file contents into a scratch `lib/main.dart` in a temporary Flutter project (or replace current main carefully).
2. Resolve any formatting / lint issues (long single-line widgets may need manual line breaking; some unused locals may be removed).
3. Do **NOT** import these prototypes directly into production—migrate the logic into services (`lib/services/`) and widgets with tests.

## Migration Guidance
When promoting ideas from the prototypes:
- Move brush emission + smoothing into a `BrushEngine` class under `lib/services/brush_engine.dart`.
- Wrap active drawing state (layers, current stroke) in a `ChangeNotifier` for integration with Provider.
- Add unit tests for: spacing correctness, smoothing stability, session lifecycle.
- For network (e621) add a simple repository abstraction to simplify future caching.

## Deferred Concepts (Not in these Prototypes)
- Persistence to disk
- Timed sequences / auto-advance
- Undo / multi-layer support
- Image caching layer
- Tag preset management

Keep prototypes lean—extend only in real app code with tests.
