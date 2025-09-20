// services/debug_logger.dart
// -------------------------
// In-app debug logging service that captures logs and displays them in a
// floating overlay. Provides multiple output targets: in-app display,
// file export, and network transmission to development PC.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:hive_ce/hive.dart';

/// Log levels for filtering and display
enum LogLevel { debug, info, warning, error }

/// A single log entry with metadata
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? tag;
  final Object? error;
  final StackTrace? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.tag,
    this.error,
    this.stackTrace,
  });

  /// Formatted string representation
  String get formatted {
    final timeStr = timestamp.toIso8601String().substring(
      11,
      23,
    ); // HH:mm:ss.SSS
    final levelStr = level.name.toUpperCase().padRight(7);
    final tagStr = tag != null ? '[$tag] ' : '';
    var result = '$timeStr $levelStr $tagStr$message';

    if (error != null) {
      result += '\nError: $error';
    }
    if (stackTrace != null) {
      result +=
          '\nStack: ${stackTrace.toString().split('\n').take(5).join('\n')}';
    }

    return result;
  }

  /// JSON representation for network transmission
  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'message': message,
    'tag': tag,
    'error': error?.toString(),
    'stackTrace': stackTrace?.toString(),
  };
}

/// Debug logging service with multiple output targets
class DebugLogger extends ChangeNotifier {
  static DebugLogger? _instance;
  static DebugLogger get instance => _instance ??= DebugLogger._();

  DebugLogger._() {
    // Initialize settings asynchronously
    _initializeAsync();
  }

  Future<void> _initializeAsync() async {
    await _loadSettings();
  }

  final List<LogEntry> _logs = [];
  final StreamController<LogEntry> _logStream = StreamController.broadcast();

  /// Maximum number of logs to keep in memory
  int maxLogCount = 1000;

  /// Network logging configuration
  String? _networkLogUrl;
  bool _networkLoggingEnabled = false;

  /// File logging (mobile/desktop only)
  bool _fileLoggingEnabled = false;

  /// Current minimum log level
  LogLevel _minLevel = LogLevel.debug;

  /// Hive box for persistent settings
  Box<dynamic>? _settingsBox;

  /// Whether settings have been loaded from storage
  bool _settingsLoaded = false;

  // Getters
  List<LogEntry> get logs => List.unmodifiable(_logs);
  Stream<LogEntry> get logStream => _logStream.stream;
  bool get networkLoggingEnabled => _networkLoggingEnabled;
  bool get fileLoggingEnabled => _fileLoggingEnabled;
  LogLevel get minLevel => _minLevel;
  String get networkLogUrl => _networkLogUrl ?? '';
  bool get settingsLoaded => _settingsLoaded;

  /// Load settings from Hive
  Future<void> _loadSettings() async {
    try {
      if (!Hive.isBoxOpen('debug_settings')) {
        _settingsBox = await Hive.openBox('debug_settings');
      } else {
        _settingsBox = Hive.box('debug_settings');
      }

      // Load persisted settings
      _networkLogUrl = _settingsBox?.get('networkLogUrl', defaultValue: '');
      _networkLoggingEnabled =
          _settingsBox?.get('networkLoggingEnabled', defaultValue: false) ??
          false;
      _fileLoggingEnabled =
          _settingsBox?.get('fileLoggingEnabled', defaultValue: false) ?? false;

      final levelIndex =
          _settingsBox?.get(
            'minLevelIndex',
            defaultValue: LogLevel.debug.index,
          ) ??
          LogLevel.debug.index;
      _minLevel =
          LogLevel.values[levelIndex.clamp(0, LogLevel.values.length - 1)];

      _settingsLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading debug settings: $e');
      _settingsLoaded =
          true; // Mark as loaded even if failed to avoid infinite loading
    }
  }

  /// Save settings to Hive
  Future<void> _saveSettings() async {
    try {
      await _settingsBox?.put('networkLogUrl', _networkLogUrl);
      await _settingsBox?.put('networkLoggingEnabled', _networkLoggingEnabled);
      await _settingsBox?.put('fileLoggingEnabled', _fileLoggingEnabled);
      await _settingsBox?.put('minLevelIndex', _minLevel.index);
    } catch (e) {
      debugPrint('Error saving debug settings: $e');
    }
  }

  /// Configure network logging endpoint (e.g., http://192.168.1.100:8080/logs)
  void configureNetworkLogging({required String url, required bool enabled}) {
    _networkLogUrl = url;
    _networkLoggingEnabled = enabled;
    _saveSettings(); // Persist settings
    if (enabled) {
      info('Network logging enabled: $url', tag: 'DebugLogger');
    }
  }

  /// Enable/disable file logging
  void configureFileLogging(bool enabled) {
    _fileLoggingEnabled = enabled;
    _saveSettings(); // Persist settings
    if (enabled) {
      info('File logging enabled', tag: 'DebugLogger');
    }
  }

  /// Set minimum log level
  void setMinLevel(LogLevel level) {
    _minLevel = level;
    _saveSettings(); // Persist settings
    info('Log level set to: ${level.name}', tag: 'DebugLogger');
  }

  /// Add a log entry
  void _log(
    LogLevel level,
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < _minLevel.index) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );

    // Add to in-memory buffer
    _logs.add(entry);
    if (_logs.length > maxLogCount) {
      _logs.removeAt(0);
    }

    // Notify listeners (debug overlay)
    _logStream.add(entry);
    notifyListeners();

    // Also send to Flutter's debug console
    if (kDebugMode) {
      debugPrint(entry.formatted);
    }

    // Send to network endpoint if configured
    if (_networkLoggingEnabled && _networkLogUrl != null) {
      _sendToNetwork(entry);
    }

    // TODO: File logging for mobile/desktop
    if (_fileLoggingEnabled) {
      _writeToFile(entry);
    }
  }

  /// Send log to network endpoint
  Future<void> _sendToNetwork(LogEntry entry) async {
    try {
      final response = await http
          .post(
            Uri.parse(_networkLogUrl!),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(entry.toJson()),
          )
          .timeout(const Duration(seconds: 2));

      if (response.statusCode != 200) {
        // Don't log this failure to avoid infinite loops
        debugPrint('Network log failed: ${response.statusCode}');
      }
    } catch (e) {
      // Silently fail network logging to avoid disrupting the app
      debugPrint('Network log error: $e');
    }
  }

  /// Write log to file (mobile/desktop)
  Future<void> _writeToFile(LogEntry entry) async {
    if (kIsWeb) {
      // Web doesn't support file system access - skip file logging
      return;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final logFile = File('${directory.path}/posetrainer_debug.log');

      // Append log entry to file
      await logFile.writeAsString(
        '${entry.formatted}\n',
        mode: FileMode.append,
      );
    } catch (e) {
      // Silently fail file logging to avoid infinite loops
      debugPrint('File logging error: $e');
    }
  }

  /// Public logging methods
  void debug(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      LogLevel.debug,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void info(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      LogLevel.info,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void warning(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      LogLevel.warning,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      LogLevel.error,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Clear all logs
  void clear() {
    _logs.clear();
    notifyListeners();
    info('Logs cleared', tag: 'DebugLogger');
  }

  /// Export logs as text for sharing
  String exportLogsAsText() {
    final buffer = StringBuffer();
    buffer.writeln('=== PoseTrainer Debug Logs ===');
    buffer.writeln('Exported: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Total entries: ${_logs.length}');
    buffer.writeln('');

    for (final log in _logs) {
      buffer.writeln(log.formatted);
    }

    return buffer.toString();
  }

  /// Export logs as JSON
  String exportLogsAsJson() {
    return jsonEncode({
      'metadata': {
        'exported': DateTime.now().toIso8601String(),
        'count': _logs.length,
        'app': 'PoseTrainer',
      },
      'logs': _logs.map((log) => log.toJson()).toList(),
    });
  }

  /// Copy logs to clipboard
  Future<void> copyLogsToClipboard({bool asJson = false}) async {
    final content = asJson ? exportLogsAsJson() : exportLogsAsText();
    await Clipboard.setData(ClipboardData(text: content));
    info('Logs copied to clipboard', tag: 'DebugLogger');
  }

  /// Share logs via platform share sheet (mobile)
  Future<void> shareLogs() async {
    if (kIsWeb) {
      // Web: fallback to clipboard
      await copyLogsToClipboard();
      return;
    }

    try {
      if (Platform.isIOS || Platform.isAndroid) {
        // Mobile: create temporary file and share it
        final directory = await getTemporaryDirectory();
        final tempFile = File(
          '${directory.path}/posetrainer_logs_${DateTime.now().millisecondsSinceEpoch}.txt',
        );

        await tempFile.writeAsString(exportLogsAsText());

        await Share.shareXFiles(
          [XFile(tempFile.path)],
          text: 'PoseTrainer Debug Logs',
          subject: 'Debug Logs - ${DateTime.now().toIso8601String()}',
        );

        info('Logs shared via share sheet', tag: 'DebugLogger');
      } else {
        // Desktop: fallback to clipboard
        await copyLogsToClipboard();
        info('Logs copied to clipboard (desktop)', tag: 'DebugLogger');
      }
    } catch (e) {
      // Fallback to clipboard on any error
      await copyLogsToClipboard();
      error(
        'Share failed, copied to clipboard instead',
        tag: 'DebugLogger',
        error: e,
      );
    }
  }

  /// Get the path to the log file (mobile/desktop only)
  Future<String?> getLogFilePath() async {
    if (kIsWeb) return null;

    try {
      final directory = await getApplicationDocumentsDirectory();
      return '${directory.path}/posetrainer_debug.log';
    } catch (e) {
      return null;
    }
  }

  /// Get log file size in bytes
  Future<int> getLogFileSize() async {
    final path = await getLogFilePath();
    if (path == null) return 0;

    try {
      final file = File(path);
      if (await file.exists()) {
        return await file.length();
      }
    } catch (e) {
      debugPrint('Error getting log file size: $e');
    }
    return 0;
  }

  /// Clear log file
  Future<void> clearLogFile() async {
    final path = await getLogFilePath();
    if (path == null) return;

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        info('Log file cleared', tag: 'DebugLogger');
      }
    } catch (e) {
      error('Failed to clear log file', tag: 'DebugLogger', error: e);
    }
  }

  @override
  void dispose() {
    _logStream.close();
    super.dispose();
  }
}

/// Convenience functions for global access
void debugLog(
  String message, {
  String? tag,
  Object? error,
  StackTrace? stackTrace,
}) {
  DebugLogger.instance.debug(
    message,
    tag: tag,
    error: error,
    stackTrace: stackTrace,
  );
}

void infoLog(
  String message, {
  String? tag,
  Object? error,
  StackTrace? stackTrace,
}) {
  DebugLogger.instance.info(
    message,
    tag: tag,
    error: error,
    stackTrace: stackTrace,
  );
}

void warningLog(
  String message, {
  String? tag,
  Object? error,
  StackTrace? stackTrace,
}) {
  DebugLogger.instance.warning(
    message,
    tag: tag,
    error: error,
    stackTrace: stackTrace,
  );
}

void errorLog(
  String message, {
  String? tag,
  Object? error,
  StackTrace? stackTrace,
}) {
  DebugLogger.instance.error(
    message,
    tag: tag,
    error: error,
    stackTrace: stackTrace,
  );
}
