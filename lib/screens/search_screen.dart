import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../services/reference_search_service.dart';
import 'practice_screen.dart';

// ---------------------------------------------------------------------------
// SearchScreen
// ---------------------------------------------------------------------------
// Lets the user enter e621 tags (rating:safe enforced automatically) and pick
// a reference image to draw from.
// Platform nuance:
// - Native (desktop/mobile): we download + decode the image so we can access
//   pixels for overlay review later.
// - Web: CORS blocks pixel access, so we just pass the URL and use an <img>
//   element (Image.network) side-by-side with the canvas.

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  // Pre-fill with a sample query to make first run feel alive.
  final _controller = TextEditingController(
    text: 'standing canine favcount:>100',
  );

  // --- Lifecycle -----------------------------------------------------------

  @override
  void initState() {
    super.initState();
    // Trigger an initial search after the first frame (avoids doing provider
    // work during build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReferenceSearchService>().search(_controller.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<ReferenceSearchService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Reference Search')),
      body: Column(
        children: [
          _SearchBar(
            controller: _controller,
            loading: search.isLoading,
            onSubmit: () => search.search(_controller.text),
          ),
          if (search.error != null) _ErrorBanner(message: search.error!),
          // Expanded results grid.
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: search.results.length,
              itemBuilder: (context, i) => _ResultTile(
                result: search.results[i],
                loadImage: search.loadImage,
                onOpen: _openPractice,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Navigation / handlers -----------------------------------------------

  Future<void> _openPractice(ReferenceResult r) async {
    // WHY: Separate method keeps the GestureDetector onTap concise & readable.
    final navigator = Navigator.of(context);
    if (kIsWeb) {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => PracticeScreen(
            reference: null,
            referenceUrl: r.fullUrl.isNotEmpty ? r.fullUrl : r.previewUrl,
            sourceUrl: 'https://e621.net/posts/${r.id}',
          ),
        ),
      );
      return; // Early return—no further work for web path.
    }
    final messenger = ScaffoldMessenger.of(context);
    ui.Image img;
    try {
      img = await context.read<ReferenceSearchService>().loadImage(r.fullUrl);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to load image: $e')),
      );
      return;
    }
    if (!mounted) return;
    navigator.push(
      MaterialPageRoute(
        builder: (_) => PracticeScreen(
          reference: img,
          referenceUrl: null,
          sourceUrl: 'https://e621.net/posts/${r.id}',
        ),
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
  final Future<ui.Image> Function(String url) loadImage; // kept for symmetry
  final Future<void> Function(ReferenceResult r) onOpen;
  const _ResultTile({
    required this.result,
    required this.loadImage,
    required this.onOpen,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onOpen(result),
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
          ],
        ),
      ),
    );
  }
}
