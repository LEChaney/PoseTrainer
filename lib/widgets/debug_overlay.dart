// widgets/debug_overlay.dart
// -------------------------
// Floating debug overlay that displays logs and provides debugging controls.
// Can be toggled via gesture or button. Stays on top of all content.

import 'package:flutter/material.dart';
import '../services/debug_logger.dart';

/// Floating debug overlay widget
class DebugOverlay extends StatefulWidget {
  /// Child widget that the overlay will appear on top of
  final Widget child;

  /// Whether the overlay starts visible
  final bool initiallyVisible;

  /// Gesture to toggle overlay (defaults to 3-finger tap)
  final int toggleFingerCount;

  const DebugOverlay({
    super.key,
    required this.child,
    this.initiallyVisible = false,
    this.toggleFingerCount = 3,
  });

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  bool _isVisible = false;
  bool _isExpanded = true;
  LogLevel _filterLevel = LogLevel.debug;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _isVisible = widget.initiallyVisible;

    // Auto-scroll to bottom when new logs arrive
    DebugLogger.instance.logStream.listen((_) {
      if (_scrollController.hasClients && _isVisible && _isExpanded) {
        Future.microtask(() {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleVisibility() {
    setState(() {
      _isVisible = !_isVisible;
    });
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  List<LogEntry> get _filteredLogs {
    return DebugLogger.instance.logs
        .where((log) => log.level.index >= _filterLevel.index)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main app content with gesture detector
        GestureDetector(
          onTap: () {
            // Handle single tap normally
          },
          onScaleStart: (details) {
            // Check for multi-finger tap
            if (details.pointerCount == widget.toggleFingerCount) {
              _toggleVisibility();
            }
          },
          child: widget.child,
        ),

        // Debug overlay (only shown when visible)
        if (_isVisible)
          Positioned(
            top: 50,
            right: 10,
            bottom: 100,
            width: 400,
            child: _buildDebugPanel(context),
          ),
      ],
    );
  }

  Widget _buildDebugPanel(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: Colors.black.withOpacity(0.9),
      child: Column(
        children: [
          // Header with controls
          _buildHeader(context),

          // Log content (if expanded)
          if (_isExpanded) ...[
            _buildFilterBar(context),
            Expanded(child: _buildLogList(context)),
            _buildActionBar(context),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.8),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.bug_report, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          const Text(
            'Debug Console',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _toggleExpanded,
            icon: Icon(
              _isExpanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.white,
              size: 18,
            ),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            padding: EdgeInsets.zero,
          ),
          IconButton(
            onPressed: _toggleVisibility,
            icon: const Icon(Icons.close, color: Colors.white, size: 18),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Colors.grey[800],
      child: Row(
        children: [
          const Text(
            'Filter:',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(width: 8),
          ...LogLevel.values.map((level) {
            final isSelected = level == _filterLevel;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(
                  level.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    color: isSelected ? Colors.black : Colors.white,
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _filterLevel = level;
                    });
                  }
                },
                backgroundColor: Colors.grey[700],
                selectedColor: _getLevelColor(level),
                checkmarkColor: Colors.black,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLogList(BuildContext context) {
    return Container(
      color: Colors.black,
      child: ListenableBuilder(
        listenable: DebugLogger.instance,
        builder: (context, _) {
          final logs = _filteredLogs;

          if (logs.isEmpty) {
            return const Center(
              child: Text(
                'No logs to display',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            );
          }

          return ListView.builder(
            controller: _scrollController,
            itemCount: logs.length,
            itemBuilder: (context, index) => _buildLogItem(logs[index]),
          );
        },
      ),
    );
  }

  Widget _buildLogItem(LogEntry log) {
    final color = _getLevelColor(log.level);
    final timeStr = log.timestamp.toIso8601String().substring(
      11,
      19,
    ); // HH:mm:ss

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main log line
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              children: [
                TextSpan(
                  text: timeStr,
                  style: const TextStyle(color: Colors.grey),
                ),
                const TextSpan(text: ' '),
                TextSpan(
                  text: log.level.name.toUpperCase().padRight(5),
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
                if (log.tag != null) ...[
                  const TextSpan(text: ' '),
                  TextSpan(
                    text: '[${log.tag}]',
                    style: const TextStyle(color: Colors.cyan),
                  ),
                ],
                const TextSpan(text: ' '),
                TextSpan(
                  text: log.message,
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),

          // Error details (if present)
          if (log.error != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: Text(
                'Error: ${log.error}',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.grey[800],
      child: Row(
        children: [
          _buildActionButton(
            'Clear',
            Icons.clear_all,
            () => DebugLogger.instance.clear(),
          ),
          _buildActionButton(
            'Copy',
            Icons.copy,
            () => DebugLogger.instance.copyLogsToClipboard(),
          ),
          _buildActionButton(
            'Share',
            Icons.share,
            () => DebugLogger.instance.shareLogs(),
          ),
          const Spacer(),
          Text(
            '${_filteredLogs.length} logs',
            style: const TextStyle(color: Colors.grey, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    VoidCallback onPressed,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.white),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }
}

/// Debug overlay toggle button widget (for easy access)
class DebugToggleButton extends StatelessWidget {
  final VoidCallback onPressed;

  const DebugToggleButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 50,
      right: 10,
      child: FloatingActionButton.small(
        onPressed: onPressed,
        backgroundColor: Colors.black.withOpacity(0.7),
        child: const Icon(Icons.bug_report, color: Colors.green, size: 18),
      ),
    );
  }
}
