import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../services/reference_search_service.dart';
import 'practice_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController(text: 'standing canine');

  @override
  void initState() {
    super.initState();
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'e621 tags (rating:safe enforced)',
                    ),
                    onSubmitted: (_) => search.search(_controller.text),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: search.isLoading
                      ? null
                      : () => search.search(_controller.text),
                  child: search.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Search'),
                ),
              ],
            ),
          ),
          if (search.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                search.error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
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
                return GestureDetector(
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    if (kIsWeb) {
                      // Web: pass only URL, decoding done by <img> element; drawing canvas remains separate.
                      navigator.push(
                        MaterialPageRoute(
                          builder: (_) => PracticeScreen(
                            reference: null,
                            referenceUrl: r.fullUrl.isNotEmpty
                                ? r.fullUrl
                                : r.previewUrl,
                            sourceUrl: 'https://e621.net/posts/${r.id}',
                          ),
                        ),
                      );
                      return;
                    }
                    final messenger = ScaffoldMessenger.of(context);
                    ui.Image img;
                    try {
                      img = await search.loadImage(r.fullUrl);
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
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          r.previewUrl,
                          fit: BoxFit.cover,
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
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${r.score}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
