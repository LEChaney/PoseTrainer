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
- Use Duration objects (no raw ms ints in prod code).
- Material 3 components & theming.
- Avoid bang operators unless obviously safe; prefer early null guards.

Networking:
- http only; always send descriptive User-Agent for e621.
- Parse JSON into small immutable models.

Sessions & Review:
- Store reference + drawing together with minimal metadata (source URL, timestamp).
- Keep data small and explicit; add fields only when needed.

Out of Scope (defer): advanced brushes, multi-layer compositing, AI, cloud sync.

Quality:
- Prefer readability > cleverness; remove dead prototype code when migrated.
- Add focused tests for spacing, smoothing, session save/review when stabilizing.

Update this file only when core invariants change; keep <=50 lines.
