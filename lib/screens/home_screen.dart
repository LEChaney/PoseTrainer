import 'package:flutter/material.dart';
import 'session_screen.dart';

// home_screen.dart (LEGACY)
// ------------------------
// This screen is deprecated in favor of the newer reference search -> practice
// -> review flow. It is kept temporarily while the older timed sequence code
// is still accessible. Safe to remove once history + practice flow fully cover
// user needs.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PoseCoach')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Timed Figure Drawing',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Start a practice session with a sequence of timed poses. This early build uses a fixed sample set.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SessionScreen())),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Session'),
            ),
          ],
        ),
      ),
    );
  }
}
