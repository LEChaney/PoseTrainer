// screens/debug_settings_screen.dart
// ----------------------------------
// Debug settings screen for configuring logging options.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/debug_logger.dart';

class DebugSettingsScreen extends StatefulWidget {
  const DebugSettingsScreen({super.key});

  @override
  State<DebugSettingsScreen> createState() => _DebugSettingsScreenState();
}

class _DebugSettingsScreenState extends State<DebugSettingsScreen> {
  final _urlController = TextEditingController();
  late bool _networkLoggingEnabled;
  late bool _fileLoggingEnabled;
  late LogLevel _minLevel;

  @override
  void initState() {
    super.initState();
    _loadSettings();

    // Listen for settings changes
    DebugLogger.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    DebugLogger.instance.removeListener(_onSettingsChanged);
    _urlController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) {
      _loadSettings();
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

    // Update UI to reflect loaded settings
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
