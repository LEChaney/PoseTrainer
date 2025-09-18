PoseTrainer
=========

Figure drawing practice app focused on: low-latency pencil‑like brushing, tag‑driven reference selection, and clear post‑session review (side‑by‑side + overlay). Built Flutter‑first for iOS, Android, desktop, and web using Impeller.

Why It Exists
-------------
Practice apps often lack: (a) a pleasant, responsive brush feel, (b) rich tag filtering on large public image sets, and (c) an immediate overlay comparison workflow. PoseTrainer aims to keep the core loop fast: search → draw → review → iterate.

Core (Stable) Goals
-------------------
1. Smooth single soft round brush (drawAtlas batching + One‑Euro smoothing).
2. e621 tag search (safe rating default) → choose reference.
3. Practice canvas: live stroke layer + committed layer (merge on stroke end).
4. Save paired reference + drawing with minimal metadata (in‑memory now; persistence later).
5. Review: overlay (independent opacities) & side‑by‑side (web fallback when overlay unavailable due to CORS).
6. Clean Material 3 UI, readable code, minimal dependencies.

Non‑Goals (Deferred)
--------------------
Advanced multibrush engines, AI coaching, cloud sync, multi‑layer compositing, undo stack, ABR import. These re‑enter only if MVP performance / adoption justifies them.

Tech Overview
-------------
- Framework: Flutter 3.x
- State: Provider + ChangeNotifier (no Bloc/Riverpod unless justified)
- Networking: http (descriptive User‑Agent for e621)
- Rendering: Canvas + drawAtlas soft disc sprite
- Image decode: built‑in `ui.instantiateImageCodec`

Project Layout (High Level)
---------------------------
```
lib/
	main.dart                  # Entry / providers / theme
	models/
		practice_session.dart    # Completed drawing + reference pairing
	services/
		reference_search_service.dart  # e621 tag search + decode
		session_service.dart     # In-memory session history
		brush_engine.dart        # Brush smoothing & dab batching (soft round)
	screens/
		search_screen.dart       # Tag search + reference selection
		practice_screen.dart     # Drawing canvas
		review_screen.dart       # Overlay / side-by-side comparison
		history_screen.dart      # Past sessions list
docs/                        # Design notes, conversations, prototypes
```

Running the App
---------------
Windows / Android:
```powershell
flutter pub get
flutter run
```
iOS (from macOS host):
```bash
flutter pub get
flutter run --device-timeout 120 -d <device_id>
```
Web (development only):
```bash
flutter run -d chrome
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

Testing (Planned)
-----------------
Initial tests will cover:
	* Brush spacing & smoothing
	* Session save + review data integrity (once persistence lands)
	* Reference search parsing / filtering

Reference Prototypes
--------------------
See `docs/chatgpt/prototypes/` for minimal brush and first‑playable search/draw/review examples. These are reference only—migrate logic into services before production use.

License
-------
TBD (add chosen license file before distribution).

Status Note
-----------
Legacy timed pose sequence prototype removed (simplifies code). README focuses on the active search → practice → review loop.
