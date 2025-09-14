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
import 'screens/search_screen.dart';

/// Application entry point. In Dart, execution starts with `main()`.
/// `runApp` attaches the widget tree to the screen and starts the rendering
/// + event (gesture) loop.
void main() {
  runApp(const PoseCoachApp());
}

/// Root widget of the app.
///
/// Stateless because it holds no mutable UI state itself—state lives in the
/// services we register below. Those services are injected using
/// `MultiProvider`, which is just a convenience wrapper around several
/// individual `ChangeNotifierProvider` widgets.
class PoseCoachApp extends StatelessWidget {
  const PoseCoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      // Shared service instances (only the flows we actively use).
      providers: [
        ChangeNotifierProvider(create: (_) => ReferenceSearchService()),
        ChangeNotifierProvider(create: (_) => SessionService()),
      ],
      child: MaterialApp(
        title: 'PoseCoach',
        theme: ThemeData(
          // Material 3 theming; a seeded color scheme generates harmonious colors.
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
          useMaterial3: true,
        ),
        // First screen presented to the user: search for a reference image.
        home: const SearchScreen(),
      ),
    );
  }
}
