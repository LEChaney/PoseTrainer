// screens/start_screen.dart
// -------------------------
// WHY: Provides mode selection between e621 tag search and local folder sampling.
// This is the app's new entry point, allowing users to choose their preferred
// practice source. Both modes lead to the same practice flow; only the reference
// source differs.
//
// DESIGN:
// - Two large, clear mode cards for easy selection on mobile and desktop.
// - AppBar includes History and Debug buttons for quick access from startup.
// - Future: could add recent sessions or quick-start shortcuts here.

import 'package:flutter/material.dart';
import 'search_screen.dart';
import 'folder_select_screen.dart';
import 'history_screen.dart';
import 'debug_settings_screen.dart';
import '../services/debug_logger.dart';

/// Entry screen for selecting practice mode: e621 search or local folders.
class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PoseTrainer'),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const HistoryScreen()));
            },
          ),
          IconButton(
            tooltip: 'Debug Settings',
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              infoLog('Opening debug settings from start screen', tag: 'Start');
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DebugSettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Choose Practice Mode',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                _ModeCard(
                  icon: Icons.search,
                  title: 'e621 Search',
                  description:
                      'Search by tags and practice from online references',
                  onTap: () {
                    infoLog('Navigating to e621 search mode', tag: 'Start');
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SearchScreen()),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _ModeCard(
                  icon: Icons.folder,
                  title: 'Folder Practice',
                  description:
                      'Practice from randomly sampled images in your folders',
                  onTap: () {
                    infoLog('Navigating to folder select mode', tag: 'Start');
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FolderSelectScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A large, tappable card representing a practice mode.
class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Icon(icon, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
