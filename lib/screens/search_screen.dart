import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';
import '../services/reference_search_service.dart';
import '../services/debug_logger.dart';
import 'session_runner_screen.dart';
import 'history_screen.dart';
import 'debug_settings_screen.dart';

// ---------------------------------------------------------------------------
// SearchScreen
// ---------------------------------------------------------------------------
// Lets the user enter e621 tags (rating:safe enforced automatically) and pick
// a reference image to draw from. Adds selectable tiles, manual time input,
// and an unlimited mode for session timing.

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController(
    text: 'standing canine favcount:>100',
  );
  int _count = 5;
  int _seconds = 60;
  bool _unlimited = false;
  final _secondsController = TextEditingController(text: '60');
  final Set<String> _selectedIds = <String>{};
  double _expansion = 1.0; // 1=fully expanded, 0=collapsed
  bool _manualOverlay = false;
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _overlayController;
  final GlobalKey _headerKey = GlobalKey();
  double _headerFullHeight = 0;
  final GlobalKey _collapsedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    infoLog('SearchScreen initialized', tag: 'SearchScreen');
    _overlayController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
          value: _expansion,
        )..addListener(() {
          // Drive UI from controller for smooth tap-to-expand animation.
          if (mounted) setState(() => _expansion = _overlayController.value);
        });
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      infoLog(
        'Starting initial search: ${_controller.text}',
        tag: 'SearchScreen',
      );
      context.read<ReferenceSearchService>().search(_controller.text);
    });
  }

  @override
  void dispose() {
    _secondsController.dispose();
    _overlayController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<ReferenceSearchService>();
    // Post-frame: measure heights used for anchoring/padding.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHeights());

    // Compute dynamic padding to keep the grid glued to the top UI while
    // collapsing. After collapse, keep it glued to the collapsed bar until
    // you've scrolled past its height, then switch to overlay.
    final double offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final double h = _headerFullHeight > 0 ? _headerFullHeight : 160.0;
    double padCore = h - offset;

    // desiredTop is how far below the top UI the first grid row should be.
    final double desiredTop = padCore;
    // Keep the seam glued: firstItemTop = topPadding - scrollOffset = desiredTop
    // => topPadding = desiredTop + scrollOffset (+ base spacing).
    final double gridTopPadding = 8.0 + offset + desiredTop;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reference Search'),
        actions: [
          if (_selectedIds.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _selectedIds.clear()),
              child: Text('Clear (${_selectedIds.length})'),
            ),
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          // Debug settings button (only in debug mode)
          if (kDebugMode)
            IconButton(
              tooltip: 'Debug Settings',
              icon: const Icon(Icons.bug_report),
              onPressed: () {
                infoLog('Opening debug settings', tag: 'SearchScreen');
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DebugSettingsScreen(),
                  ),
                );
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          // Content grid behind the overlaying controls
          Positioned.fill(
            child: GridView.builder(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(8, gridTopPadding, 8, 8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: search.results.length,
              itemBuilder: (context, i) {
                final r = search.results[i];
                final selected = _selectedIds.contains(r.id);
                return _ResultTile(
                  result: r,
                  selected: selected,
                  onToggle: () {
                    setState(() {
                      if (selected) {
                        _selectedIds.remove(r.id);
                      } else {
                        _selectedIds.add(r.id);
                      }
                    });
                  },
                );
              },
            ),
          ),

          // Collapsed bar (always at top, under the expanding header)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: KeyedSubtree(
              key: _collapsedKey,
              child: _CollapsedControlsBar(
                count: _count,
                seconds: _seconds,
                unlimited: _unlimited,
                onStart: search.results.isEmpty
                    ? null
                    : () => _startSession(search),
                onExpand: () {
                  _manualOverlay = true;
                  _overlayController.animateTo(1.0, curve: Curves.easeOutCubic);
                },
              ),
            ),
          ),

          // Expanding header overlay (clips height by _expansion)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: _expansion <= 0.001,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: _expansion.clamp(0.0, 1.0),
                  child: Material(
                    key: _headerKey,
                    elevation: 3,
                    color: Theme.of(context).colorScheme.surface,
                    child: _buildExpandedHeader(search),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final double collapseRange = _headerFullHeight > 0
        ? _headerFullHeight
        : 160.0;

    // If user tapped to expand and it's animating, don't fight the animation.
    if (_manualOverlay && _overlayController.isAnimating) return;
    // When user starts scrolling away from top, relinquish manual control.
    if (_manualOverlay && offset > 0) {
      _manualOverlay = false;
    }

    final target = (1.0 - (offset / collapseRange)).clamp(0.0, 1.0);
    if ((_overlayController.value - target).abs() > 0.001) {
      _overlayController.value = target;
    }
  }

  void _updateHeights() {
    final ctx = _headerKey.currentContext;
    if (ctx == null) return;
    final size = ctx.size;
    if (size == null) return;
    final h = size.height;
    // Only capture the "full" height when header is fully expanded to avoid
    // collapsing measurements feeding back into collapseRange.
    final bool shouldUpdateFull = _headerFullHeight == 0 || _expansion > 0.99;
    if (shouldUpdateFull && (h - _headerFullHeight).abs() > 1.0) {
      if (mounted) _headerFullHeight = h;
    }
  }

  void _startSession(ReferenceSearchService search) {
    final all = search.results;
    final items = _selectedIds.isNotEmpty
        ? all.where((r) => _selectedIds.contains(r.id)).toList()
        : all.take(_count).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionRunnerScreen(
          items: items,
          secondsPerImage: _unlimited ? null : _seconds,
        ),
      ),
    );
  }

  /// Builds the fully expanded header (search + controls) used by the overlay.
  Widget _buildExpandedHeader(ReferenceSearchService search) {
    return Column(
      children: [
        _SearchBar(
          controller: _controller,
          loading: search.isLoading,
          onSubmit: () => search.search(_controller.text),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 600;

              final startButton = FilledButton.icon(
                onPressed: search.results.isEmpty
                    ? null
                    : () => _startSession(search),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Session'),
              );

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _buildCountCluster()),
                        const SizedBox(width: 12),
                        Expanded(child: _buildSecondsCluster()),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(children: [_buildUnlimitedToggle()]),
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: startButton),
                  ],
                );
              }

              final leftControls = <Widget>[
                const Text('Count'),
                IconButton(
                  onPressed: () =>
                      setState(() => _count = (_count - 1).clamp(1, 100)),
                  icon: const Icon(Icons.remove),
                ),
                Text('$_count'),
                IconButton(
                  onPressed: () =>
                      setState(() => _count = (_count + 1).clamp(1, 100)),
                  icon: const Icon(Icons.add),
                ),
                const SizedBox(width: 16),
                const Text('Seconds'),
                const SizedBox(width: 6),
                SizedBox(
                  width: 84,
                  child: TextField(
                    enabled: !_unlimited,
                    controller: _secondsController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      hintText: 'e.g. 60',
                    ),
                    onChanged: (v) {
                      final parsed = int.tryParse(v) ?? _seconds;
                      setState(() => _seconds = parsed.clamp(1, 3600));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '−10s',
                  onPressed: _unlimited
                      ? null
                      : () => setState(() {
                          _seconds = (_seconds - 10).clamp(1, 3600);
                          _secondsController.text = '$_seconds';
                        }),
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  tooltip: '+10s',
                  onPressed: _unlimited
                      ? null
                      : () => setState(() {
                          _seconds = (_seconds + 10).clamp(1, 3600);
                          _secondsController.text = '$_seconds';
                        }),
                  icon: const Icon(Icons.add),
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _unlimited,
                      onChanged: (v) => setState(() {
                        _unlimited = v ?? false;
                      }),
                    ),
                    const Text('Unlimited'),
                  ],
                ),
                const SizedBox(width: 12),
              ];

              return Row(
                children: [...leftControls, const Spacer(), startButton],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Builds the compact 'Count' control cluster with label and +/- buttons.
  Widget _buildCountCluster() {
    final theme = Theme.of(context);
    return Column(
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
                child: Text('$_count', style: theme.textTheme.titleMedium),
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
    );
  }

  /// Builds the compact 'Seconds' cluster with field and +/-10s buttons.
  Widget _buildSecondsCluster() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Seconds', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 84,
              child: TextField(
                enabled: !_unlimited,
                controller: _secondsController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  hintText: 'e.g. 60',
                ),
                onChanged: (v) {
                  final parsed = int.tryParse(v) ?? _seconds;
                  setState(() => _seconds = parsed.clamp(1, 3600));
                },
              ),
            ),
            const SizedBox(width: 8),
            _smallTonalButton(
              label: '−10',
              onPressed: _unlimited
                  ? null
                  : () => setState(() {
                      _seconds = (_seconds - 10).clamp(1, 3600);
                      _secondsController.text = '$_seconds';
                    }),
            ),
            const SizedBox(width: 8),
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
    );
  }

  /// Builds the compact 'Unlimited' toggle row.
  Widget _buildUnlimitedToggle() {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Unlimited', style: theme.textTheme.labelMedium),
        const SizedBox(width: 8),
        Switch.adaptive(
          value: _unlimited,
          onChanged: (v) => setState(() => _unlimited = v),
        ),
      ],
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
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          minimumSize: WidgetStateProperty.all(const Size(0, 36)),
        ),
        child: Text(label),
      ),
    );
  }
}

// --- Helper Widgets --------------------------------------------------------

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSubmit;
  const _SearchBar({
    required this.controller,
    required this.loading,
    required this.onSubmit,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'e621 tags (rating:safe enforced)',
              ),
              onSubmitted: (_) => onSubmit(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: loading ? null : onSubmit,
            child: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Search'),
          ),
        ],
      ),
    );
  }
}

// (Removed unused _ErrorBanner)

class _ResultTile extends StatelessWidget {
  final ReferenceResult result;
  final bool selected;
  final VoidCallback onToggle;
  const _ResultTile({
    required this.result,
    required this.selected,
    required this.onToggle,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Use contain to preserve the image's intrinsic aspect ratio and
            // avoid the horizontal stretching/cropping seen with cover.
            // Letterboxed areas show a neutral dark background.
            ColoredBox(
              color: const Color(0xFF202024),
              child: Image.network(
                result.previewUrl,
                fit: BoxFit.contain,
                webHtmlElementStrategy: kIsWeb
                    ? WebHtmlElementStrategy.fallback
                    : WebHtmlElementStrategy.never,
                errorBuilder: (ctx, err, st) => const ColoredBox(
                  color: Colors.black26,
                  child: Icon(
                    Icons.broken_image,
                    size: 20,
                    color: Colors.white54,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${result.score}',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
            if (selected)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.lightBlueAccent, width: 3),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.lightBlueAccent.withValues(alpha: 0.15),
                ),
              ),
            if (selected)
              const Positioned(
                top: 6,
                left: 6,
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.lightBlue,
                  child: Icon(Icons.check, size: 16, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact, collapsed controls shown when the user scrolls down.
class _CollapsedControlsBar extends StatelessWidget {
  final int count;
  final int seconds;
  final bool unlimited;
  final VoidCallback? onStart;
  final VoidCallback onExpand;
  const _CollapsedControlsBar({
    required this.count,
    required this.seconds,
    required this.unlimited,
    required this.onExpand,
    this.onStart,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Expand',
            icon: const Icon(Icons.unfold_more),
            onPressed: onExpand,
          ),
          Text('Count: $count', style: theme.textTheme.bodyMedium),
          const SizedBox(width: 12),
          Text(
            unlimited ? 'Unlimited' : 'Seconds: $seconds',
            style: theme.textTheme.bodyMedium,
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start'),
          ),
        ],
      ),
    );
  }
}
