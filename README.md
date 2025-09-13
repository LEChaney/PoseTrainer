PoseCoach
=========

Timed pose / figure drawing practice app focused on: low-latency pencil‑like brushing, tag‑driven reference selection, and clear post‑session review (side‑by‑side + overlay). Built Flutter‑first for iOS, Android, desktop, and web using Impeller.

Why It Exists
-------------
Practice apps often lack: (a) a pleasant, responsive brush feel, (b) rich tag filtering on large public image sets, and (c) an immediate overlay comparison workflow. PoseCoach aims to keep the core loop fast: search → draw → review → iterate.

Core (Stable) Goals
-------------------
1. Smooth single soft round brush (drawAtlas batching + One‑Euro smoothing).
2. e621 tag search (safe rating default) → choose reference.
3. Practice canvas: live stroke layer + committed layer (merge on stroke end).
4. Save paired reference + drawing with minimal metadata.
5. Review: overlay (independent opacities) & side‑by‑side.
6. Clean Material 3 UI, readable code, minimal dependencies.

Non‑Goals (Deferred)
--------------------
Advanced multibrush engines, AI coaching, cloud sync, multi‑layer compositing, undo stack, ABR import. These re‑enter only if MVP performance / adoption justifies them.

Tech Overview
-------------
- Framework: Flutter 3.x (Impeller renderer)  
- State: Provider + ChangeNotifier (no Bloc/Riverpod unless justified)  
- Networking: http (descriptive User‑Agent for e621)  
- Rendering: Canvas + drawAtlas soft disc sprite  
- Image decode: built‑in `ui.instantiateImageCodec`  

Project Layout (High Level)
---------------------------
```
lib/
	main.dart                # Entry / navigation wiring
	models/
		pose.dart              # (Sample pose/sequence model)
	services/
		timer_service.dart     # Duration + tick management
		pose_sequence_service.dart # Pose sequencing logic
		(future) brush_engine.dart  # Brush emission & smoothing service
		(future) session_service.dart # Session store / persistence
	screens/
		home_screen.dart       # Launch / configuration
		session_screen.dart    # Active timed session UI
docs/chatgpt/prototypes/    # Reference-only prototypes (not imported)
docs/                       # Design notes, tech stack discussion
```

Running the App
---------------
Windows / Android:
```powershell
flutter pub get
flutter run --enable-impeller
```
iOS (from macOS host):
```bash
flutter pub get
flutter run --device-timeout 120 --enable-impeller -d <device_id>
```
Web (development only):
```bash
flutter run -d chrome
```
Compare Impeller vs legacy (diagnostics):
```bash
flutter run --no-enable-impeller
```

Publishing for iOS from Windows
-------------------------------
You cannot produce a signed App Store build directly on Windows. Common workflow:
1. Maintain code on Windows; keep `pubspec.yaml` and assets committed.
2. Use a macOS CI (e.g. GitHub Actions + macOS runner, Codemagic, or Flutter’s build pipelines) to run: `flutter build ipa --release`.
3. Provide signing assets (App Store Connect API key or uploaded certificates + provisioning profiles) as encrypted CI secrets.
4. Archive & notarize automatically; upload via `xcodebuild -exportArchive` (handled by Flutter build) or Fastlane `deliver`.
5. Test with TestFlight before public release.
For ad‑hoc local testing without the store, generate an `.ipa` on CI and install via Apple Configurator or TestFlight internal distribution.

Testing
-------
Execute all tests:
```bash
flutter test
```
Planned / important coverage areas:
- Brush spacing & smoothing (when brush service lands)
- TimerService tick accumulation & pause/resume
- Pose sequencing transitions
- Session save + review data integrity

Reference Prototypes
--------------------
See `docs/chatgpt/prototypes/` for minimal brush and first‑playable search/draw/review examples. These are reference only—migrate logic into services before production use.

License
-------
TBD (add chosen license file before distribution).

Status Note
-----------
This README describes stable invariants. Avoid adding speculative future plans here; keep it focused so new contributors quickly grasp the core loop.
