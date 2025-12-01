// screens/debug_settings_screen.dart
// ----------------------------------
// Debug settings screen for configuring logging options.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/debug_logger.dart';
import '../services/e621_settings_service.dart';

class DebugSettingsScreen extends StatefulWidget {
  const DebugSettingsScreen({super.key});

  @override
  State<DebugSettingsScreen> createState() => _DebugSettingsScreenState();
}

class _DebugSettingsScreenState extends State<DebugSettingsScreen> {
  final _urlController = TextEditingController();
  final _customTagsController = TextEditingController();
  final _pageLimitController = TextEditingController();
  final _baseUrlController = TextEditingController();
  late bool _networkLoggingEnabled;
  late bool _fileLoggingEnabled;
  late LogLevel _minLevel;

  // e621 settings
  late E621Rating _e621Rating;
  late bool _e621ExcludeCub;

  @override
  void initState() {
    super.initState();
    _loadSettings();

    // Listen for settings changes
    DebugLogger.instance.addListener(_onSettingsChanged);
    E621SettingsService.instance.addListener(_onE621SettingsChanged);
  }

  @override
  void dispose() {
    DebugLogger.instance.removeListener(_onSettingsChanged);
    E621SettingsService.instance.removeListener(_onE621SettingsChanged);
    _urlController.dispose();
    _customTagsController.dispose();
    _pageLimitController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) {
      _loadSettings();
    }
  }

  void _onE621SettingsChanged() {
    if (mounted) {
      _loadE621Settings();
    }
  }

  void _loadSettings() {
    final logger = DebugLogger.instance;
    _networkLoggingEnabled = logger.networkLoggingEnabled;
    _fileLoggingEnabled = logger.fileLoggingEnabled;
    _minLevel = logger.minLevel;

    // Use saved URL or provide a reasonable default
    final savedUrl = logger.networkLogUrl;
    _urlController.text = savedUrl.isNotEmpty
        ? savedUrl
        : 'http://192.168.1.100:8080/logs';

    // Load e621 settings
    _loadE621Settings();

    // Update UI to reflect loaded settings
    if (mounted) {
      setState(() {});
    }
  }

  void _loadE621Settings() {
    final e621 = E621SettingsService.instance;
    _e621Rating = e621.rating;
    _e621ExcludeCub = e621.excludeCub;

    // Only update text controllers if they differ from the service value
    // to avoid overwriting user input mid-typing
    if (_baseUrlController.text != e621.baseUrl) {
      _baseUrlController.text = e621.baseUrl;
    }
    if (_customTagsController.text != e621.customTags) {
      _customTagsController.text = e621.customTags;
    }
    if (_pageLimitController.text != e621.pageLimit.toString()) {
      _pageLimitController.text = e621.pageLimit.toString();
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _saveSettings() {
    final logger = DebugLogger.instance;

    if (_networkLoggingEnabled && _urlController.text.isNotEmpty) {
      logger.configureNetworkLogging(url: _urlController.text, enabled: true);
    } else {
      logger.configureNetworkLogging(url: '', enabled: false);
    }

    logger.configureFileLogging(_fileLoggingEnabled);
    logger.setMinLevel(_minLevel);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Debug settings saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Settings'),
        actions: [
          TextButton(onPressed: _saveSettings, child: const Text('SAVE')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Configure debug logging options',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),

            // Log Level
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Log Level',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    ...LogLevel.values.map((level) {
                      return RadioListTile<LogLevel>(
                        title: Text(level.name.toUpperCase()),
                        subtitle: Text(_getLevelDescription(level)),
                        value: level,
                        groupValue: _minLevel,
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _minLevel = value;
                            });
                          }
                        },
                      );
                    }),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Network Logging
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.wifi,
                          color: _networkLoggingEnabled
                              ? Colors.green
                              : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Network Logging',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const Spacer(),
                        Switch(
                          value: _networkLoggingEnabled,
                          onChanged: (value) {
                            setState(() {
                              _networkLoggingEnabled = value;
                            });
                          },
                        ),
                      ],
                    ),
                    if (_networkLoggingEnabled) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _urlController,
                        decoration: const InputDecoration(
                          labelText: 'Log Server URL',
                          hintText: 'http://192.168.1.100:8080/logs',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.url,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Run log_receiver.py on your PC to receive logs',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // File Logging
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.file_copy,
                          color: _fileLoggingEnabled
                              ? Colors.green
                              : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'File Logging',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const Spacer(),
                        Switch(
                          value: _fileLoggingEnabled,
                          onChanged: (value) {
                            setState(() {
                              _fileLoggingEnabled = value;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Save logs to files that can be shared via iOS/Android share sheet',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<String?>(
                      future: DebugLogger.instance.getLogFilePath(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data != null) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Log file: ${snapshot.data}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontFamily: 'monospace'),
                              ),
                              FutureBuilder<int>(
                                future: DebugLogger.instance.getLogFileSize(),
                                builder: (context, sizeSnapshot) {
                                  if (sizeSnapshot.hasData) {
                                    final kb = (sizeSnapshot.data! / 1024)
                                        .toStringAsFixed(1);
                                    return Text(
                                      'Size: ${kb} KB',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ],
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Action buttons
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await DebugLogger.instance.copyLogsToClipboard();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Logs copied to clipboard'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy Logs'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await DebugLogger.instance.shareLogs();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Logs shared')),
                            );
                          }
                        },
                        icon: const Icon(Icons.share),
                        label: const Text('Share Logs'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          DebugLogger.instance.clear();
                          await DebugLogger.instance.clearLogFile();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('All logs cleared')),
                            );
                            setState(() {}); // Refresh file size display
                          }
                        },
                        icon: const Icon(Icons.clear_all),
                        label: const Text('Clear All'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[100],
                          foregroundColor: Colors.red[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Instructions
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          'How to use',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: Colors.blue[700]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. Use a 3-finger tap anywhere in the app to show/hide the debug overlay\n'
                      '2. For network logging, run "python tools/log_receiver.py" on your PC\n'
                      '3. Set the URL to your PC\'s IP address (check your router/WiFi settings)\n'
                      '4. Both devices must be on the same WiFi network',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // e621 API Settings Section
            Text(
              'e621 API Settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Configure search query parameters for e621 reference images',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

            // Base URL
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Base URL',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _baseUrlController,
                      decoration: const InputDecoration(
                        hintText: 'https://e621.net',
                        border: OutlineInputBorder(),
                        helperText: 'API base URL (e.g., https://e621.net)',
                      ),
                      keyboardType: TextInputType.url,
                      onChanged: (value) {
                        E621SettingsService.instance.setBaseUrl(value);
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Rating Filter
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rating Filter',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    ...E621Rating.values.map((rating) {
                      return RadioListTile<E621Rating>(
                        title: Text(rating.displayName),
                        subtitle: rating.value.isNotEmpty
                            ? Text('rating:${rating.value}')
                            : const Text('No rating restriction'),
                        value: rating,
                        groupValue: _e621Rating,
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _e621Rating = value;
                            });
                            E621SettingsService.instance.setRating(value);
                          }
                        },
                      );
                    }),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Other Settings
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Other Settings',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),

                    // Exclude cub toggle
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Exclude cub content'),
                              Text(
                                'Adds -cub tag to all searches',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _e621ExcludeCub,
                          onChanged: (value) {
                            setState(() {
                              _e621ExcludeCub = value;
                            });
                            E621SettingsService.instance.setExcludeCub(value);
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Page limit
                    TextField(
                      controller: _pageLimitController,
                      decoration: const InputDecoration(
                        labelText: 'Results per page',
                        hintText: '30',
                        border: OutlineInputBorder(),
                        helperText: 'Max 320',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null) {
                          E621SettingsService.instance.setPageLimit(parsed);
                        }
                      },
                    ),

                    const SizedBox(height: 16),

                    // Custom tags
                    TextField(
                      controller: _customTagsController,
                      decoration: const InputDecoration(
                        labelText: 'Custom fixed tags',
                        hintText: 'e.g., order:score -animated',
                        border: OutlineInputBorder(),
                        helperText:
                            'Space-separated tags added to every search',
                      ),
                      onChanged: (value) {
                        E621SettingsService.instance.setCustomTags(value);
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // URL Preview
            Card(
              color: Colors.grey[100],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.preview, color: Colors.grey[700]),
                        const SizedBox(width: 8),
                        Text(
                          'URL Preview',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      E621SettingsService.instance.previewUrl,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Reset button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  E621SettingsService.instance.resetToDefaults();
                  _loadE621Settings();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('e621 settings reset to defaults'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.restore),
                label: const Text('Reset e621 Settings to Defaults'),
              ),
            ),

            // Extra bottom padding for comfortable scrolling
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _getLevelDescription(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'All messages (very verbose)';
      case LogLevel.info:
        return 'Info, warnings, and errors';
      case LogLevel.warning:
        return 'Warnings and errors only';
      case LogLevel.error:
        return 'Errors only';
    }
  }
}
