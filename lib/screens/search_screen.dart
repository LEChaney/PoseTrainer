import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/reference_search_service.dart';
import 'session_runner_screen.dart';
import 'history_screen.dart';

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

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController(
    text: 'standing canine favcount:>100',
  );
  int _count = 5;
  int _seconds = 60;
  bool _unlimited = false;
  final _secondsController = TextEditingController(text: '60');
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReferenceSearchService>().search(_controller.text);
    });
  }

  @override
  void dispose() {
    _secondsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<ReferenceSearchService>();
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
        ],
      ),
      body: Column(
        children: [
          _SearchBar(
            controller: _controller,
            loading: search.isLoading,
            onSubmit: () => search.search(_controller.text),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
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
                const Spacer(),
                FilledButton.icon(
                  onPressed: search.results.isEmpty
                      ? null
                      : () {
                          final all = search.results;
                          final items = _selectedIds.isNotEmpty
                              ? all
                                    .where((r) => _selectedIds.contains(r.id))
                                    .toList()
                              : all.take(_count).toList();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SessionRunnerScreen(
                                items: items,
                                secondsPerImage: _unlimited ? null : _seconds,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Session'),
                ),
              ],
            ),
          ),
          if (search.error != null) _ErrorBanner(message: search.error!),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
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
        ],
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

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Text(message, style: const TextStyle(color: Colors.redAccent)),
  );
}

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
                  color: Colors.lightBlueAccent.withOpacity(0.15),
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
