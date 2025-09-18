# PoseTrainer Architecture

_Last updated: 2025-09-14 (reflects removal of legacy timed pose sequence)_

## Overview
PoseTrainer provides a tight loop for gesture / figure drawing practice:
Search reference → Practice (draw) → Review (overlay / side‑by‑side) → (optional) Revisit via History.
The codebase favors clarity over abstraction: thin UI widgets, plain services (Provider + ChangeNotifier), immutable session records, and a simple brush pipeline using `drawAtlas`.

## Core Loop (High Level)
1. User opens app (root: `main.dart`). Providers register search + session + brush services.
2. `SearchScreen` performs e621 tag search (safe rating default) via `ReferenceSearchService`.
3. User selects a post → attempt to decode image (native) or keep URL only (web fallback).
4. Navigate to `PracticeScreen` with reference (decoded `ui.Image?` + URL). User draws:
   - Pointer events → smoothed (One‑Euro) → brush emits dabs → `drawAtlas` batches into stroke layer.
   - On stroke end: stroke is committed to the base drawing image.
5. User taps Finish → new `PracticeSession` stored by `SessionService` (in‑memory list).
6. Navigate to `ReviewScreen`:
   - If decoded reference available → overlay mode (independent opacities) OR side‑by‑side.
   - If only URL (web) → side‑by‑side fallback (no pixel overlay, CORS).
7. History via `HistoryScreen` lists prior sessions; selecting opens review again.

## Directory Structure (Active Components Only)
```
lib/
  main.dart
  models/
    practice_session.dart
  services/
    brush_engine.dart
    reference_search_service.dart
    session_service.dart
  screens/
    search_screen.dart
    practice_screen.dart
    review_screen.dart
    history_screen.dart
```
`docs/` contains this architecture file plus conversation/design artifacts.

## Services
- `ReferenceSearchService`: e621 JSON query (adds User-Agent), filters safe posts, downloads & decodes image (native platforms). Returns either decoded `ui.Image` or just URL (web fallback).
- `BrushEngine` (soft round single brush): Maintains current stroke, applies One‑Euro smoothing (x, y, pressure), converts filtered points → dabs (sprite draws) via `Canvas.drawAtlas`, minimizing overdraw & allocations. Commits final stroke into backing image on stroke end.
- `SessionService`: In‑memory FIFO list (newest first) of `PracticeSession`. Persistence intentionally deferred for simpler iteration.

## Models
- `PracticeSession`: Immutable pairing of `sourceUrl`, `reference` (`ui.Image`), `drawing` (`ui.Image`), and `endedAt`. Designed for future serialization (will need image encoding + small metadata manifest).

## Brush Pipeline Details
1. Pointer event arrives (position, pressure if supported).
2. One‑Euro filter smooths x, y, and pressure values to reduce jitter while retaining responsiveness.
3. Interpolate dabs if movement > dab spacing threshold (distance based) to ensure continuous stroke.
4. Accumulate atlas transforms + color/alpha per dab; issue a single `drawAtlas` (or small batches) each frame.
5. On stroke end: composite temporary stroke layer into persistent drawing image; clear stroke buffer.

Why `drawAtlas`? Batching many identical textured quads (soft disc) is cheaper than repeated path-based soft brushes and avoids per-dab layer overhead.

## Data Flow (Simplified)
```
User Input → BrushEngine (smoothing + dabs) → Canvas (stroke layer)
Finish → SessionService.add() → HistoryScreen list
Search → ReferenceSearchService → (decoded image | URL) → PracticeScreen
PracticeScreen → ReviewScreen (after finish)
```

## Platform Notes
- Web: Cannot reliably read pixels of cross-origin images → overlay disabled when only URL available; side‑by‑side used instead.
- Native (iOS/Android/Desktop): Full overlay with opacity blending using `saveLayer`.
- Performance: Soft brush kept minimal (no blend modes or dynamic hardness) to maintain consistent frame times.

## Error Handling Strategy
- Network errors: surfaced as simple error banners / messages (retry manually).
- Image decode failures: degrade to URL-only fallback paths.
- No silent swallowing: most branches return early with comments explaining why (guided for newcomers).

## Future (Deferred)
- Persistence: Serialize sessions (PNG encode drawing + reference meta) to local storage.
- Undo / stroke history beyond single committed bitmap.
- Additional brushes (texture, pencil grain) & pressure curves.
- Tag caching / offline reference sets.
- Test Coverage: brush spacing math, search parsing, persistence integrity once added.

## Design Principles Recap
- Readability > cleverness (beginner-friendly comments kept until stabilized).
- Minimize nesting via early returns & helper widgets.
- Keep services stateless aside from essential mutable core state.
- Avoid premature abstraction; add layers only after demonstrated need.

---
For questions: start at `search_screen.dart` (entry task flow), then read `practice_screen.dart` for brush lifecycle, then `review_screen.dart` for overlay logic.
