// screens/folder_select_screen_drive.dart
// ----------------------------------------
// WHY: Allow users to select from their Google Drive folders for practice sessions.
// Images are uniformly sampled from all selected folders (including subfolders).
// OAuth tokens persist across sessions, eliminating re-authentication on reload.
//
// CURRENT SCOPE:
// - OAuth2 authentication with Google Drive
// - Browse and select folders from Drive root
// - Display preview thumbnails from folder contents
// - Multi-select folders before starting session
// - Persistent folder selections via Hive
//
// ADVANTAGES:
// - Works on iOS Safari (no File System API needed)
// - No re-selection required on app reload
// - Built-in thumbnails from Drive API
// - Cross-device folder access
//
// FUTURE:
// - Navigate into subfolders (breadcrumb navigation)
// - Search folders by name
// - Sort by name/date/size
// - Folder statistics (total images, last modified)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;
import '../services/google_drive_folder_service.dart';
import '../services/session_service.dart';
import '../services/debug_logger.dart';
import '../models/practice_result.dart';
import '../models/review_result.dart';
import '../models/practice_session.dart';
import 'history_screen.dart';
import 'debug_settings_screen.dart';
import 'practice_screen.dart';
import 'review_screen.dart';

/// Screen for selecting Google Drive folders to sample images from.
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

  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _secondsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GoogleDriveFolderService>(
      builder: (context, driveService, child) {
        final folders = driveService.folders;
        final selectedCount = _selectedIds.length;
        final totalImages = folders
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
              // Add folder button
              if (driveService.isAuthenticated)
                IconButton(
                  tooltip: 'Add Folder',
                  icon: const Icon(Icons.create_new_folder),
                  onPressed: () => _showAddFolderDialog(context, driveService),
                ),
              IconButton(
                tooltip: 'History',
                icon: const Icon(Icons.history),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  );
                },
              ),
              IconButton(
                tooltip: 'Debug Settings',
                icon: const Icon(Icons.bug_report),
                onPressed: () {
                  infoLog('Opening debug settings', tag: 'FolderSelect');
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DebugSettingsScreen(),
                    ),
                  );
                },
              ),
              // Account menu
              if (driveService.isAuthenticated)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.account_circle),
                  onSelected: (value) {
                    if (value == 'signout') {
                      _handleSignOut(context, driveService);
                    } else if (value == 'clear') {
                      _handleClearFolders(context, driveService);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'clear',
                      child: Text('Clear All Folders'),
                    ),
                    const PopupMenuItem(
                      value: 'signout',
                      child: Text('Sign Out'),
                    ),
                  ],
                ),
            ],
          ),
          body: Column(
            children: [
              // Authentication status / instructions
              if (!driveService.isAuthenticated)
                _buildAuthPrompt(context, driveService)
              else if (folders.isEmpty)
                _buildEmptyState(context)
              else
                _buildFolderInstructions(context, selectedCount, totalImages),

              // Folder grid
              Expanded(child: _buildFolderGrid(context, driveService, folders)),

              // Bottom controls
              if (_selectedIds.isNotEmpty && driveService.isAuthenticated)
                _buildBottomControls(context, totalImages, driveService),
            ],
          ),
        );
      },
    );
  }

  /// Builds authentication prompt for non-authenticated users.
  Widget _buildAuthPrompt(
    BuildContext context,
    GoogleDriveFolderService service,
  ) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      margin: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            Icons.cloud,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Connect to Google Drive',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Access your folders on any device. Your selections persist across sessions.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: service.isAuthenticating
                ? null
                : () => _handleAuthentication(context, service),
            icon: service.isAuthenticating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(
              service.isAuthenticating
                  ? 'Connecting...'
                  : 'Sign In with Google',
            ),
          ),
        ],
      ),
    );
  }

  /// Builds empty state when authenticated but no folders added.
  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open,
              size: 64,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No folders added yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the folder icon in the app bar to browse your Drive',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Builds folder selection instructions and stats.
  Widget _buildFolderInstructions(
    BuildContext context,
    int selectedCount,
    int totalImages,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select one or more folders to practice from',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (selectedCount > 0)
            Text(
              '$selectedCount folder${selectedCount == 1 ? '' : 's'} selected · $totalImages image${totalImages == 1 ? '' : 's'} available',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }

  /// Builds the folder grid.
  Widget _buildFolderGrid(
    BuildContext context,
    GoogleDriveFolderService service,
    List<DriveFolderInfo> folders,
  ) {
    if (!service.isAuthenticated) {
      return const SizedBox.shrink();
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        childAspectRatio: 0.85,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folder = folders[index];
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
          onRemove: () => _handleRemoveFolder(context, service, folder),
        );
      },
    );
  }

  /// Builds the bottom control bar with session settings and start button.
  Widget _buildBottomControls(
    BuildContext context,
    int totalImages,
    GoogleDriveFolderService service,
  ) {
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
                Checkbox(
                  value: _unlimited,
                  onChanged: (v) => setState(() {
                    _unlimited = v ?? false;
                  }),
                ),
                const Text('Unlimited time'),
              ],
            ),
            const SizedBox(height: 12),
            // Start session button
            FilledButton(
              onPressed: () => _startSession(context, service),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.play_arrow),
                    const SizedBox(width: 8),
                    Text(
                      'Start Session ($_count image${_count == 1 ? '' : 's'})',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Handle Google authentication.
  Future<void> _handleAuthentication(
    BuildContext context,
    GoogleDriveFolderService service,
  ) async {
    infoLog('Starting authentication', tag: 'FolderSelect');

    final success = await service.authenticate();

    if (!mounted) return;

    if (success) {
      infoLog('Authentication successful', tag: 'FolderSelect');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connected to Google Drive')),
      );
    } else {
      errorLog('Authentication failed', tag: 'FolderSelect');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to connect. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Show dialog to add a folder from Drive.
  Future<void> _showAddFolderDialog(
    BuildContext context,
    GoogleDriveFolderService service,
  ) async {
    infoLog('Opening add folder dialog', tag: 'FolderSelect');

    // Show loading dialog while fetching folders
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading folders...'),
              ],
            ),
          ),
        ),
      ),
    );

    final driveFolders = await service.listDriveFolders();

    if (!mounted) return;
    Navigator.of(context).pop(); // Close loading dialog

    if (driveFolders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No folders found in Drive root')),
      );
      return;
    }

    // Show folder selection dialog
    final selected = await showDialog<DriveFolderInfo>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Folder'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: driveFolders.length,
            itemBuilder: (context, index) {
              final folder = driveFolders[index];
              return ListTile(
                leading: const Icon(Icons.folder),
                title: Text(folder.name),
                subtitle: folder.modifiedTime != null
                    ? Text('Modified ${_formatDate(folder.modifiedTime!)}')
                    : null,
                onTap: () => Navigator.of(context).pop(folder),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected == null || !mounted) return;

    // Show loading while scanning
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Scanning folder...'),
              ],
            ),
          ),
        ),
      ),
    );

    final added = await service.addFolder(selected);

    if (!mounted) return;
    Navigator.of(context).pop(); // Close loading dialog

    if (added) {
      infoLog('Folder added: ${selected.name}', tag: 'FolderSelect');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Added folder: ${selected.name}')));
    } else {
      warningLog(
        'Folder already exists: ${selected.name}',
        tag: 'FolderSelect',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Folder ${selected.name} already added')),
      );
    }
  }

  /// Handle removing a folder.
  Future<void> _handleRemoveFolder(
    BuildContext context,
    GoogleDriveFolderService service,
    DriveFolderInfo folder,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Folder?'),
        content: Text('Remove "${folder.name}" from your collection?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await service.removeFolder(folder.id);
      setState(() => _selectedIds.remove(folder.id));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Removed ${folder.name}')));
      }
    }
  }

  /// Handle sign out.
  Future<void> _handleSignOut(
    BuildContext context,
    GoogleDriveFolderService service,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out?'),
        content: const Text(
          'This will remove access to your Drive folders. Your folder selections will be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await service.signOut();
      setState(() => _selectedIds.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed out from Google Drive')),
        );
      }
    }
  }

  /// Handle clearing all folders.
  Future<void> _handleClearFolders(
    BuildContext context,
    GoogleDriveFolderService service,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Folders?'),
        content: const Text('This will remove all folder selections.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await service.clearFolders();
      setState(() => _selectedIds.clear());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('All folders cleared')));
      }
    }
  }

  /// Start a practice session with selected folders.
  Future<void> _startSession(
    BuildContext context,
    GoogleDriveFolderService service,
  ) async {
    if (_selectedIds.isEmpty) return;

    final seconds = _unlimited ? null : _seconds;
    infoLog(
      'Starting folder session: ${_selectedIds.length} folders, count=$_count, ${_unlimited ? 'unlimited' : '${seconds}s'}',
      tag: 'FolderSelect',
    );

    // Show loading dialog while sampling images
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Preparing session...'),
              ],
            ),
          ),
        ),
      ),
    );

    // Sample images from selected folders
    final images = await service.sampleImages(_selectedIds.toList(), _count);

    if (!mounted) return;
    Navigator.of(context).pop(); // Close loading dialog

    if (images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No images found in selected folders'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    infoLog('Sampled ${images.length} images for session', tag: 'FolderSelect');

    // Navigate to Drive session runner (custom implementation for Drive images)
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DriveSessionRunnerScreen(
          images: images,
          driveService: service,
          secondsPerImage: seconds,
        ),
      ),
    );
  }

  Widget _smallIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
    );
  }

  Widget _smallTonalButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} months ago';
    return '${(diff.inDays / 365).floor()} years ago';
  }
}

/// Card widget displaying a Drive folder with preview thumbnails.
class _FolderCard extends StatelessWidget {
  final DriveFolderInfo folder;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  const _FolderCard({
    required this.folder,
    required this.selected,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: selected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Preview thumbnails (2x2 grid)
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: _buildPreviewGrid(),
              ),
            ),
            // Folder info
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.folder,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          folder.name,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Remove button
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: onRemove,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        tooltip: 'Remove folder',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${folder.imageCount} image${folder.imageCount == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (selected)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Selected',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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

  Widget _buildPreviewGrid() {
    if (folder.previewUrls.isEmpty) {
      // No previews - show folder icon
      return Container(
        color: Colors.grey[200],
        child: const Center(
          child: Icon(Icons.folder_open, size: 48, color: Colors.grey),
        ),
      );
    }

    // Build 2x2 grid of thumbnails
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 1,
        mainAxisSpacing: 1,
      ),
      itemCount: 4,
      itemBuilder: (context, index) {
        if (index < folder.previewUrls.length) {
          // Google Drive thumbnails require authentication headers
          // For now, use a placeholder until we implement authenticated image loading
          return Container(
            color: Colors.grey[300],
            child: const Center(
              child: Icon(Icons.image, size: 32, color: Colors.grey),
            ),
          );
        } else {
          // Empty cell
          return Container(color: Colors.grey[200]);
        }
      },
    );
  }
}

/// Custom session runner for Google Drive images.
/// Downloads and decodes images using authenticated Drive API.
class _DriveSessionRunnerScreen extends StatefulWidget {
  final List<DriveImageFile> images;
  final GoogleDriveFolderService driveService;
  final int? secondsPerImage;

  const _DriveSessionRunnerScreen({
    required this.images,
    required this.driveService,
    required this.secondsPerImage,
  });

  @override
  State<_DriveSessionRunnerScreen> createState() =>
      _DriveSessionRunnerScreenState();
}

class _DriveSessionRunnerScreenState extends State<_DriveSessionRunnerScreen> {
  int _index = 0;
  bool _loading = true;
  ui.Image? _currentImage;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCurrentImage();
  }

  Future<void> _loadCurrentImage() async {
    if (_index >= widget.images.length) {
      // Session complete
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HistoryScreen()),
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final imageFile = widget.images[_index];

    try {
      // Download image bytes from Drive
      final bytes = await widget.driveService.downloadImageBytes(imageFile.id);

      if (bytes == null) {
        throw Exception('Failed to download image');
      }

      // Decode bytes to ui.Image
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();

      if (!mounted) return;

      setState(() {
        _currentImage = frame.image;
        _loading = false;
      });

      // Start practice screen
      _startPractice();
    } catch (e, stack) {
      errorLog(
        'Failed to load Drive image',
        tag: 'DriveSessionRunner',
        error: e,
        stackTrace: stack,
      );

      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _startPractice() async {
    if (_currentImage == null) return;

    final imageFile = widget.images[_index];
    final sourceUrl = 'Google Drive: ${imageFile.name}';

    final practiceResult = await Navigator.of(context).push<PracticeResult>(
      MaterialPageRoute(
        builder: (_) => PracticeScreen(
          reference: _currentImage,
          referenceUrl: null, // No URL fallback since we have decoded image
          sourceUrl: sourceUrl,
          timeLimitSeconds: widget.secondsPerImage,
          sessionMode: true,
        ),
      ),
    );

    if (!mounted) return;

    if (practiceResult == null) {
      // User backed out of session
      Navigator.of(context).pop();
      return;
    }

    if (practiceResult.skipped) {
      // Skip to next image
      setState(() {
        _index++;
        _currentImage = null;
      });
      _loadCurrentImage();
      return;
    }

    // Show review
    final drawing = practiceResult.drawing!;
    final reviewResult = await Navigator.of(context).push<ReviewResult>(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          reference: _currentImage,
          referenceUrl: null,
          drawing: drawing,
          sourceUrl: sourceUrl,
          initialOverlay: const OverlayTransform(
            scale: 1.0,
            offset: ui.Offset.zero,
          ),
          sessionControls: true,
          isLast: _index == widget.images.length - 1,
        ),
      ),
    );

    if (!mounted) return;

    // Save if requested
    if (reviewResult != null && reviewResult.save) {
      final imageFile = widget.images[_index];
      context.read<SessionService>().add(
        sourceUrl: sourceUrl,
        reference: _currentImage,
        referenceUrl: null,
        driveFileId:
            imageFile.id, // Save Drive file ID for re-downloading full image
        drawing: drawing,
        overlay: reviewResult.overlay,
      );
    }

    // Check if user wants to continue or end session
    if (reviewResult == null || reviewResult.action == ReviewAction.next) {
      setState(() {
        _index++;
        _currentImage = null;
      });
      _loadCurrentImage();
    } else {
      // End session -> go to history
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HistoryScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Loading image ${_index + 1} of ${widget.images.length}...',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Failed to load image',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 16),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _index++;
                          _currentImage = null;
                        });
                        _loadCurrentImage();
                      },
                      child: const Text('Skip'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Should never reach here since practice screen is pushed
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
