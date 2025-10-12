// screens/folder_select_screen.dart
// ---------------------------------
// WHY: Allow users to select from local folder collections for practice sessions.
// Images are uniformly sampled from all selected folders (including subfolders).
// This mode enables offline practice or using personal reference libraries.
//
// CURRENT SCOPE:
// - Placeholder fake folders for testing layout and visuals.
// - Grid display with content preview thumbnails.
// - Multi-select folders before starting session.
// - Folder management (add/remove folders) deferred until UI is stable.
//
// FUTURE:
// - Platform file picker integration for adding real folders.
// - Persist folder list to local storage.
// - Display folder stats (image count, last used).
// - Filter by subfolder or tag metadata.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'history_screen.dart';
import 'debug_settings_screen.dart';
import '../services/debug_logger.dart';

/// Screen for selecting folders to sample images from for practice.
class FolderSelectScreen extends StatefulWidget {
  const FolderSelectScreen({super.key});

  @override
  State<FolderSelectScreen> createState() => _FolderSelectScreenState();
}

class _FolderSelectScreenState extends State<FolderSelectScreen> {
  // Session configuration
  int _count = 5;
  int _seconds = 60;
  bool _unlimited = false;
  final _secondsController = TextEditingController(text: '60');

  // Placeholder fake folders for testing layout
  final List<FolderInfo> _folders = [
    FolderInfo(
      id: '1',
      name: 'Anatomy Studies',
      path: '/Users/me/Pictures/Anatomy',
      imageCount: 342,
      previewUrls: [
        'https://picsum.photos/seed/anat1/300/300',
        'https://picsum.photos/seed/anat2/300/300',
        'https://picsum.photos/seed/anat3/300/300',
        'https://picsum.photos/seed/anat4/300/300',
      ],
    ),
    FolderInfo(
      id: '2',
      name: 'Figure Drawing',
      path: '/Users/me/Pictures/Figures',
      imageCount: 157,
      previewUrls: [
        'https://picsum.photos/seed/fig1/300/300',
        'https://picsum.photos/seed/fig2/300/300',
        'https://picsum.photos/seed/fig3/300/300',
        'https://picsum.photos/seed/fig4/300/300',
      ],
    ),
    FolderInfo(
      id: '3',
      name: 'Animals',
      path: '/Users/me/Pictures/Animals',
      imageCount: 89,
      previewUrls: [
        'https://picsum.photos/seed/animal1/300/300',
        'https://picsum.photos/seed/animal2/300/300',
        'https://picsum.photos/seed/animal3/300/300',
        'https://picsum.photos/seed/animal4/300/300',
      ],
    ),
    FolderInfo(
      id: '4',
      name: 'Gestures',
      path: '/Users/me/Pictures/Gestures',
      imageCount: 423,
      previewUrls: [
        'https://picsum.photos/seed/gest1/300/300',
        'https://picsum.photos/seed/gest2/300/300',
        'https://picsum.photos/seed/gest3/300/300',
        'https://picsum.photos/seed/gest4/300/300',
      ],
    ),
    FolderInfo(
      id: '5',
      name: 'Hands & Feet',
      path: '/Users/me/Pictures/Extremities',
      imageCount: 234,
      previewUrls: [
        'https://picsum.photos/seed/hand1/300/300',
        'https://picsum.photos/seed/hand2/300/300',
        'https://picsum.photos/seed/hand3/300/300',
        'https://picsum.photos/seed/hand4/300/300',
      ],
    ),
    FolderInfo(
      id: '6',
      name: 'Portrait Reference',
      path: '/Users/me/Pictures/Portraits',
      imageCount: 198,
      previewUrls: [
        'https://picsum.photos/seed/port1/300/300',
        'https://picsum.photos/seed/port2/300/300',
        'https://picsum.photos/seed/port3/300/300',
        'https://picsum.photos/seed/port4/300/300',
      ],
    ),
  ];

  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _secondsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedIds.length;
    final totalImages = _folders
        .where((f) => _selectedIds.contains(f.id))
        .fold(0, (sum, f) => sum + f.imageCount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Folders'),
        actions: [
          if (_selectedIds.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _selectedIds.clear()),
              child: Text('Clear ($selectedCount)'),
            ),
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
              infoLog('Opening debug settings', tag: 'FolderSelect');
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DebugSettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Instructions and stats header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select one or more folders to practice from',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_selectedIds.isNotEmpty)
                  Text(
                    '$selectedCount folder${selectedCount == 1 ? '' : 's'} selected · $totalImages image${totalImages == 1 ? '' : 's'} available',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),

          // Folder grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
                childAspectRatio: 0.85,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: _folders.length,
              itemBuilder: (context, index) {
                final folder = _folders[index];
                final selected = _selectedIds.contains(folder.id);
                return _FolderCard(
                  folder: folder,
                  selected: selected,
                  onToggle: () {
                    setState(() {
                      if (selected) {
                        _selectedIds.remove(folder.id);
                      } else {
                        _selectedIds.add(folder.id);
                      }
                    });
                  },
                );
              },
            ),
          ),

          // Bottom controls
          if (_selectedIds.isNotEmpty)
            _buildBottomControls(context, totalImages),
        ],
      ),
    );
  }

  /// Builds the bottom control bar with session settings and start button.
  Widget _buildBottomControls(BuildContext context, int totalImages) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Session configuration controls
            Row(
              children: [
                // Count control
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Count', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _smallIconButton(
                            icon: Icons.remove,
                            onPressed: () => setState(() {
                              _count = (_count - 1).clamp(1, 100);
                            }),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 28,
                            child: Center(
                              child: Text(
                                '$_count',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _smallIconButton(
                            icon: Icons.add,
                            onPressed: () => setState(() {
                              _count = (_count + 1).clamp(1, 100);
                            }),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Seconds control
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Seconds', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 68,
                            child: TextField(
                              enabled: !_unlimited,
                              controller: _secondsController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                hintText: '60',
                              ),
                              onChanged: (v) {
                                final parsed = int.tryParse(v) ?? _seconds;
                                setState(() {
                                  _seconds = parsed.clamp(1, 3600);
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          _smallTonalButton(
                            label: '−10',
                            onPressed: _unlimited
                                ? null
                                : () => setState(() {
                                    _seconds = (_seconds - 10).clamp(1, 3600);
                                    _secondsController.text = '$_seconds';
                                  }),
                          ),
                          const SizedBox(width: 6),
                          _smallTonalButton(
                            label: '+10',
                            onPressed: _unlimited
                                ? null
                                : () => setState(() {
                                    _seconds = (_seconds + 10).clamp(1, 3600);
                                    _secondsController.text = '$_seconds';
                                  }),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Unlimited toggle
            Row(
              children: [
                Text('Unlimited', style: theme.textTheme.labelMedium),
                const SizedBox(width: 8),
                Switch.adaptive(
                  value: _unlimited,
                  onChanged: (v) => setState(() => _unlimited = v),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 16),
            // Start button
            FilledButton.icon(
              onPressed: () {
                infoLog(
                  'Starting folder session: ${_selectedIds.length} folders, '
                  'count=$_count, ${_unlimited ? 'unlimited' : '${_seconds}s'}',
                  tag: 'FolderSelect',
                );
                // TODO: Navigate to session runner with folder-based image source
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Folder sessions not yet implemented. Coming soon!',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.play_arrow),
              label: Text('Start Session ($totalImages images)'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact utility: small square icon button.
  Widget _smallIconButton({required IconData icon, VoidCallback? onPressed}) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        iconSize: 20,
        icon: Icon(icon),
      ),
    );
  }

  /// Compact utility: small tonal text button.
  Widget _smallTonalButton({required String label, VoidCallback? onPressed}) {
    return SizedBox(
      height: 36,
      child: FilledButton.tonal(
        onPressed: onPressed,
        style: ButtonStyle(
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
          minimumSize: WidgetStateProperty.all(const Size(0, 36)),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Data model for a folder that contains practice images.
class FolderInfo {
  final String id;
  final String name;
  final String path;
  final int imageCount;
  final List<String> previewUrls; // Up to 4 preview image URLs

  FolderInfo({
    required this.id,
    required this.name,
    required this.path,
    required this.imageCount,
    required this.previewUrls,
  });
}

/// Card widget displaying a folder with preview thumbnails.
class _FolderCard extends StatelessWidget {
  final FolderInfo folder;
  final bool selected;
  final VoidCallback onToggle;

  const _FolderCard({
    required this.folder,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: selected ? 4 : 1,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Preview grid (2x2 thumbnails)
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildPreviewGrid(),
                  if (selected)
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 3,
                        ),
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.15,
                        ),
                      ),
                    ),
                  if (selected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: theme.colorScheme.primary,
                        child: const Icon(
                          Icons.check,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Folder info
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${folder.imageCount} images',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a 2x2 grid of preview thumbnails.
  Widget _buildPreviewGrid() {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 1,
        crossAxisSpacing: 1,
      ),
      itemCount: math.min(4, folder.previewUrls.length),
      itemBuilder: (context, index) {
        if (index >= folder.previewUrls.length) {
          return Container(color: Colors.grey[300]);
        }
        return Image.network(
          folder.previewUrls[index],
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.grey[300],
            child: const Icon(Icons.broken_image, color: Colors.grey),
          ),
        );
      },
    );
  }
}
