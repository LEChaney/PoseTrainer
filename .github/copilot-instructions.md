PoseCoach – Copilot Instructions (stable core)

Purpose: Timed pose / figure drawing app with low‑latency brush, tag search, and overlay review. Code must stay clear and human‑readable.

Core Goals:
1. Smooth drawing (single soft round brush via drawAtlas + pressure sensitivity + One‑Euro smoothing).
2. e621 tag search (safe default) → pick reference → practice.
3. Save paired reference + drawing; review overlay & side‑by‑side with opacity.
4. Cross‑platform Flutter (no platform forks / native divergence).

Architecture:
- State: Provider + ChangeNotifier only (no Bloc/Riverpod unless explicitly requested).
- Services live in lib/services; plain classes, no global singletons.
- Keep UI widgets thin; move logic to services/models.
- Relative imports (package:posecoach/... only for public shared paths).

Brush Pipeline (current scope): soft disc sprite, batched dabs (drawAtlas), commit stroke on pointer up, One‑Euro for x/y/pressure.

Coding Style:
- Descriptive multi-line widgets (avoid dense one-liners).
- Extract helpers for long build / logic blocks.
- Material 3 components & theming.
- Minimize bang (!) usage; use early null guards and local vars (e.g. `final baseImage = _base;`) for non-null promotion.
- Avoid single character or ambiguous names; prefer descriptive identifiers.

Networking:
- http only; always send descriptive User-Agent for e621.
- Parse JSON into small immutable models.

Sessions & Review:
- Store reference + drawing together with minimal metadata (source URL, timestamp).
- Keep data small and explicit; add fields only when needed.

Quality:
- Prefer readability > cleverness; remove dead prototype code when migrated.
- Add focused tests for spacing, smoothing, session save/review when stabilizing.
- Dart's ui.Color class is now floating point by default and several functions / accessors have been deprecated. Use r/g/b/a properties and constructors with 0..1 floats. All withXxx() methods are deprecated and replaced a single withValues() method that takes named arguments.

Color Space & Alpha (Invariant):
- Never composite in sRGB space — do all math in Linear.
- Keep colors premultiplied at all times; do not unpremultiply.
- Convert channels directly: sRGB↔Linear on premultiplied RGB; leave alpha unchanged.
- Linear SrcOver (premultiplied):
	- rgb_out = rgb_src + rgb_dst * (1 − a_src)
	- a_out   = a_src  + a_dst  * (1 − a_src)
- Assets and framebuffers are stored as sRGB after being converted from premultiplied linear.
- This means that when they are loaded back in, and converted to linear, they will be in premultiplied linear space already.

Readability Addendum (beginner phase):
- Minimize nesting: prefer early returns, extract private widgets/helpers when a build method exceeds ~40 lines or has >2 nested conditionals.
- Split long onTap / async handlers into named methods.
- Keep widget tree vertical: one concern per widget; move complex branches into `_buildX()` helpers.
- Temporary tutorial comments: explain why (intent) before how (mechanics); okay to be verbose now—will trim later.
- Prefer section headers (// ---) to visually segment files: imports, models, state, build helpers.
- Comment decision points: platform checks, error handling, image decoding rationale.
- Comment all classes, functions, and non-trivial methods with API-style doc comments (///).
- Avoid anonymous deeply nested closures; name them for clarity if >5 lines.

Update this file only when core invariants change; keep <=50 lines.
