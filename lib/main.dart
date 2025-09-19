// main.dart
// ---------
// This is the entry point of the Flutter application. If you are new to
// Flutter/Dart, read the comments below—they explain the core ideas:
// - `main()` runs first and calls `runApp` with the *root widget*.
// - Everything you see on screen is described by a tree of widgets.
// - We use the Provider package to expose shared state objects (services)
//   to the widget tree without passing them manually through every level.
// - Each service here extends `ChangeNotifier`, which lets widgets listen for
//   changes and rebuild when data updates.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Local project imports (grouped logically) ---------------------------------
import 'services/reference_search_service.dart';
import 'services/session_service.dart';
import 'widgets/auth_gate.dart';

/// Application entry point. In Dart, execution starts with `main()`.
/// `runApp` attaches the widget tree to the screen and starts the rendering
/// + event (gesture) loop.
void main() {
  runApp(const PoseTrainerApp());
}

/// Root widget of the app.
///
/// Stateless because it holds no mutable UI state itself—state lives in the
/// services we register below. Those services are injected using
/// `MultiProvider`, which is just a convenience wrapper around several
/// individual `ChangeNotifierProvider` widgets.
class PoseTrainerApp extends StatelessWidget {
  const PoseTrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      // Shared service instances (only the flows we actively use).
      providers: [
        ChangeNotifierProvider(create: (_) => ReferenceSearchService()),
        ChangeNotifierProvider(create: (_) => SessionService()),
      ],
      child: MaterialApp(
        title: 'PoseTrainer',
        theme: ThemeData(
          // Material 3 theming; a seeded color scheme generates harmonious colors.
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
          useMaterial3: true,
        ),
        // Gate access behind Firebase Auth; allow only your accounts.
        home: const AuthGate(allowedEmails: {'lance.e.chaney@gmail.com'}),
      ),
    );
  }
}
