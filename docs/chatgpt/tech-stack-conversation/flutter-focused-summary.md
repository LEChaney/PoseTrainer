# PoseCoach – Flutter-Focused Conversation Summary

This file condenses the original long ChatGPT tech stack discussion to ONLY the parts that matter for the **current Flutter-first implementation path**. All deep Rust / wgpu / custom GPU pipeline planning has been intentionally omitted (deferred for a later phase). Keep this as a quick strategic + tactical reference while building the MVP.

---
## 1. Core MVP Goals (from original brief)
- Timed drawing / gesture practice app (initially iPad but truly cross‑platform: Android, Windows, Web are nice to have)
- Use online tagged image sources (start with e621) to build reference sets via tag queries
- Draw with low-latency, pleasant brush feel (SAI‑like round soft brush is enough for MVP)
- Save finished session: reference image + user drawing paired for review
- Review mode: side‑by‑side and overlay with adjustable opacities
- Stretch (later): auto overlay alignment, multi-device reference display, AI feedback, advanced brushes, cloud sync

---
## 2. Chosen Stack (Flutter-First Rationale)
- **Framework:** Flutter with Impeller renderer (good baseline latency, rapid iteration, one codebase for desktop + mobile + web)
- **State mgmt:** Keep it light—`ChangeNotifier` / `Provider` (already matches repo direction). Avoid heavier Bloc/Riverpod for now.
- **Networking:** `http` for e621 API calls
- **Image handling:** Use built-in `ui.instantiateImageCodec` for now; add caching later
- **Persistence (later):** Add `path_provider` + simple JSON & PNG/WebP files
- **No FFI / GPU native layer yet:** The pure Dart Canvas + `drawAtlas` approach is fast enough for a single-layer round brush prototype

(Original conversation explored a Rust + wgpu brush engine for pro features; decision: *defer until MVP pressures actual performance limits*.)

---
## 3. Brush & Input Strategy (Pure Flutter)
**Key decisions extracted:**
- Represent strokes as *dabs* (stamped soft disc) batched each frame via `Canvas.drawAtlas` (one GPU call)
- Maintain two layers:
  - Base (committed strokes merged on pointer-up)
  - Live stroke (current in-progress dabs only)
- Use a **One-Euro filter** for x, y, pressure to reduce jitter without adding latency
- Emit dabs using spacing = `brush.spacing * diameter`
- Pressure affects size and flow separately (parameters: `pressureSize`, `pressureFlow`)
- Soft disc sprite generated once (radial gradient; hardness influences inner falloff)
- Latency optimization: accumulate raw pointer events between frames; process & redraw exactly once per vsync (Ticker)

**Why this is “good enough” now:**
- Avoids per-dab immediate painting (no large repaint storm)
- Smooth curves with fewer samples
- Easy to extend to tilt / different shapes later

---
## 4. e621 Tag Search Integration (MVP)
**Essential points:**
- Use endpoint: `https://e621.net/posts.json?limit=<n>&tags=<space_or_plus_joined>`
- MUST send a descriptive `User-Agent` (replace placeholder email)
- Start with safe rating filter default: e.g. `rating:safe` plus user tags
- Extract fields: preview (thumbnail), sample/file (full image), id, score
- Load chosen reference via HTTP → decode to `ui.Image` for practice session
- Future improvements: pagination, blacklist, error handling, local cache

---
## 5. Session Flow (Current Flutter Prototype)
1. Search screen → fetch posts with tag query
2. User taps thumbnail → Practice screen opens with reference
3. User draws (single working layer, no zoom yet)
4. Finish → commit drawing & create in-memory session record
5. Review screen shows:
   - Overlay mode (two images composited with adjustable opacities)
   - Side-by-side mode (independent scaling but consistent aspect fit)
6. Optional: View history list of previous sessions stored in memory (will persist later)

---
## 6. Review / Overlay Design Choices
- Overlay uses same contain-fit rect for both images to simplify initial alignment
- Opacity sliders control reference and drawing independently
- Side-by-side uses `AspectRatio` inside a `Row` for clarity
- Future (deferred): manual transform (pan/scale/rotate), auto alignment via feature matching, contrast/heatmap diff

---
## 7. Performance & Quality Tips (From Conversation)
- Keep working canvas roughly at display resolution to avoid unnecessary pixel cost
- Use `FilterQuality.low` for dab sprite (sharper + faster)
- Only merge stroke into base layer at stroke end to reduce repeated composites
- Reuse sprite + data structures; avoid allocating inside the per-frame path
- Consider predicted touches / tilt via platform channels later (not blocking MVP)

---
## 8. Deferred / Future Enhancements (Explicitly Trimmed Out for Now)
These were in the original discussion but **removed from daily focus**:
- Rust / wgpu brush engine (advanced blend modes, smudge, linear color pipeline)
- libmypaint integration
- ONNX small model for smarter overlay alignment
- Multi-device reference streaming / cloud sync (Supabase or custom backend)
- AI coaching / iterative improvement suggestions
- Advanced layer system + undo stack + blending modes
- ABR / Clip Studio brush import

Keep this list visible so scope creep is resisted until core loop is stable.

---
## 9. Incremental Next Steps (Flutter-Only Roadmap)
Short horizon items that align with current codebase:
1. Add basic **timer configuration** (e.g. 30s / 60s / 2m sequence) and per-reference auto advance
2. Persist sessions to disk (`sessions/<timestamp>/reference.png`, `drawing.png`, `meta.json`)
3. Add simple **tag preset / favorites** UI
4. Basic **image caching** (avoid refetching same e621 images during a session)
5. Add a **pause / resume** to timed sessions (update tests accordingly)
6. Introduce a **reference queue prefetch** (download next N images asynchronously)
7. Unit tests: brush emitter spacing, One-Euro smoothing stability, session state transitions
8. Optional: simple pan/zoom of drawing surface with resolution-aware stroke mapping

---
## 10. Testing Focus (Suggested)
- Brush emitter: given a synthetic linear stroke, verify number of emitted dabs ≈ path length / spacing
- One-Euro: jittery sine input reduces standard deviation after filter
- Session timing: advancing after duration, pause halts countdown, resume continues
- e621 fetch: parse minimal mock JSON and map to model

---
## 11. Minimal Data Concepts to Mirror in App Code
- `PracticeSession` (reference image handle, drawing image handle, source URL, endedAt)
- Future meta file: `{ id, sourceUrl, tags, endedAt, durationSeconds, brushParamsVersion }`
- Brush params (current constants OK; later allow user presets)

---
## 12. Notes on Compliance / Content
- Always respect e621 rating filters and supply a proper `User-Agent`
- Provide user controls for safe content defaults before expanding sources

---
## 13. When to Revisit Native/Rust Path
Reassess if/when ALL are true:
- Need >1 advanced brush (smudge / mixing / textured / tilt elliptical)
- Layer compositing or large canvas ( > ~8 MP ) causes frame drops
- Desire for deterministic identical rendering across platforms including Web via WebGPU

Until then, Flutter-only keeps iteration velocity highest.

---
## 14. Quick Reminder of Current MVP Implementation Choices
- Input handling via `Listener` + batched per-frame processing (Ticker)
- Rendering via `drawAtlas` single pass of sprite‑based dabs
- No undo (clearing resets canvas) – add incremental stroke history later if needed
- In-memory history (not persisted yet)

---
## 15. Actionable Immediate Tasks (If Continuing Today)
- [ ] Extract brush logic already prototyped into a dedicated service / class under `lib/services/` (e.g. `brush_engine.dart`)
- [ ] Add a simple `SessionManager` ChangeNotifier to manage active session state
- [ ] Introduce timer-driven auto-advance (placeholder: cycle through selected references list)
- [ ] Write first unit test: brush spacing count

---
## 16. Source Reference
This summary is distilled from the prior ChatGPT conversation; sections unrelated to the Flutter-first path (notably Rust/wgpu architectural deep dives and advanced GPU rendering details) were intentionally removed to reduce noise. For any postponed technical rationale, consult the original `full-conversation.md` if needed.

---
**End of Flutter-focused summary.**
