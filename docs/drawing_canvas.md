# Drawing Canvas Flow (Practice Screen)

Purpose: Provide a reliable, low‑latency sketch surface while keeping historical strokes cheap to display. The core pattern is a persistent backing image ("base") plus a transient in‑progress stroke layer ("live").

## Components
- **_base (ui.Image)**: Immutable bitmap containing all *committed* strokes. Re-render cost is a single `drawImage`.
- **BrushEngine.live (StrokeLayer)**: List of analytic dabs for the *current* stroke only.
- **_pending (List<InputPoint>)**: Short-lived buffer of raw pointer samples awaiting smoothing + spacing inside the engine.
- **Ticker (_ticker)**: Drives per‑frame flush of `_pending` into the engine (`addPoints`).
- **FitMode (contain | cover)**: Controls uniform scaling from backing image space -> on‑screen widget space while preserving aspect ratio.

## Coordinate Strategy
All stroke geometry lives in backing image space (`_base.width x _base.height`). During paint, the canvas is uniformly scaled/translated so `live` dabs and the `base` align 1:1 with their original coordinates (no resampling errors / snapping at commit time). Two viewport strategies:
- **contain**: Entire image visible, letterboxed; pointer input outside draw rect ignored.
- **cover**: Image fills available area (may crop); pointer input clamped to image bounds.

## Event → Stroke Lifecycle
1. **Pointer Event Arrival**: Each `PointerEvent` is transformed from widget coordinates -> image coordinates using the current fit transform.
2. **Buffer**: The transformed point becomes an `InputPoint` and is appended to `_pending` (no immediate smoothing / spacing work on the UI handler path).
3. **Per‑Frame Flush** (`_onFrame` via Ticker): If `_pending` is non‑empty, copy & clear it, feeding the snapshot into `BrushEngine.addPoints`.
4. **Smoothing & Dab Emission**: Inside the engine (see separate brush_engine doc) points are filtered, interpolated, and converted into dabs stored in `live`.
5. **Display**: `CustomPainter` paints: clear background → scaled draw of `_base` → draw of `live` dabs.
6. **Stroke End (PointerUp)**: Final point added, then `_flushPending()` is invoked to avoid losing tail samples that might otherwise wait for next frame. Afterwards `_commitStroke()` merges `live` into `_base`.

## Commit Mechanics (`_commitStroke`)
- Flush any remaining `_pending` (safety for tail samples).
- Record a new `ui.Picture` with: (a) current `_base` image and (b) all dabs in `engine.live` drawn in image space.
- Convert picture to a new `ui.Image` → replaces `_base`.
- Clear `engine.live` (stroke no longer transient).

Why this design:
- **Performance**: Historical strokes are a single bitmap blit instead of replaying hundreds/thousands of dabs every frame.
- **Simplicity**: Transient vs committed separation avoids partial redraw artifacts and simplifies undo (future: just snapshot `_base` or keep stroke list).
- **Latency**: Pointer handlers do O(1) work—just transform & append—while smoothing & spacing occur on the next frame without blocking input.

## Clear Action
`Clear` FAB:
- `_pending.clear()` (discard unsent samples)
- `engine.live.clear()` (remove transient stroke)
- `engine.resetStroke()` (reset smoothing filters / spacing state)
- Reinitialize `_base` to a blank image of the same size.

## Finish & Review
`_finish()`:
- Ensures the in‑progress stroke is committed.
- Saves session (reference + drawing) via `SessionService` (in‑memory for now).
- Navigates to `ReviewScreen`, transferring ownership of `_base` (flag `_handedOff = true` to skip disposal in `dispose`).

## Race Condition Fix (Tail Loss / Ghost Dabs)
Originally the last few samples could vanish if `PointerUp` happened just after a frame flush—those samples sat in `_pending` until the *next* frame (which might not occur before commit). Solution: explicit `_flushPending()` call in `onPointerUp` and at start of `_commitStroke`. Ghost dabs after Clear were due to not clearing the transient layer & pending buffer simultaneously.

## Extension Points
Future features can hook here without altering the core pattern:
- **Undo**: Keep a stack of base images or store stroke objects before merging.
- **Layers**: Multiple backing images composited in order before live.
- **Pan/Zoom**: Maintain a view matrix separate from the intrinsic image transform; pointer mapping already centralized.
- **Replay**: Persist sequence of committed strokes with timestamps.

## Invariants
- All stroke geometry is stored in *image space* until painting.
- `_base` only changes inside `_commitStroke` or `Clear` reinit.
- `engine.live` contains at most one active stroke.
- `_pending` is empty immediately after every flush or commit.
- Disposal only occurs if ownership of `_base` has not been transferred.

## Quick Pseudocode Summary
```
onPointerMove -> transform -> pending.add(point)
Ticker frame -> if pending: engine.addPoints(pending.copy); pending.clear
engine.addPoints -> smooth + space -> live.add(dabs); notifyListeners
Painter.paint -> scale -> draw(base) -> draw(live)
onPointerUp -> add final point -> flushPending -> commitStroke
commitStroke -> flushPending -> picture(base + live) -> new image -> live.clear
```