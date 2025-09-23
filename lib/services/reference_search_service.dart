import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// reference_search_service.dart
// -----------------------------
// Responsibility: perform a tag search against the e621 API (safe rating
// enforced) and expose results to the UI. Also decodes selected images into
// `ui.Image` objects on native platforms.
//
// Why decode manually instead of using Image.network? We need raw pixel data
// for overlay comparison on native; decoding here centralizes networking and
// allows adding caching / headers once.

/// Simple model for a remote reference image result.
@immutable
class ReferenceResult {
  final String id;
  final String previewUrl;
  final String fullUrl;
  final int score;
  const ReferenceResult({
    required this.id,
    required this.previewUrl,
    required this.fullUrl,
    required this.score,
  });
}

/// Performs e621 search (safe rating default). No pagination yet.
class ReferenceSearchService extends ChangeNotifier {
  bool _loading = false; // Whether a search is currently in flight
  String? _error; // Last error message (simple string for now)
  List<ReferenceResult> _results = []; // Current page of results

  bool get isLoading => _loading;
  String? get error => _error;
  List<ReferenceResult> get results => List.unmodifiable(_results);

  /// Perform a new search. Replaces any existing results.
  Future<void> search(String tags) async {
    final cleaned = tags.trim();
    if (cleaned.isEmpty) {
      _results = [];
      _error = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    _results = [];
    notifyListeners();
    try {
      // Collapse whitespace to '+' which e621 expects for tag separation.
      final q = cleaned.replaceAll(RegExp(r'\s+'), '+');
      final uri = Uri.parse(
        'https://e621.net/posts.json?limit=30&tags=rating:safe+-cub+$q',
      );
      final resp = await http.get(
        uri,
        headers: const {
          // Including a descriptive User-Agent is required by e621's API policy.
          'User-Agent': 'PoseTrainer/0.1 (contact: example@example.com)',
        },
      );
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      // Use utf8.decode(resp.bodyBytes) to be explicit about encoding.
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final posts = (data['posts'] as List? ?? []);
      _results = posts
          .map((e) => e as Map<String, dynamic>)
          // Only keep posts that have a preview image URL.
          .where((m) => m['preview']?['url'] != null)
          .map(
            (m) => ReferenceResult(
              id: '${m['id']}',
              previewUrl: m['preview']['url'] as String,
              // Prefer sample (smaller but decent quality), fall back to file, else preview.
              fullUrl:
                  (m['sample']?['url'] ?? m['file']?['url']) as String? ??
                  m['preview']['url'] as String,
              score: (m['score']?['total'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Download and decode an image into a `ui.Image` (gives raw pixel access).
  /// Note: On web CORS may block pixel access—our web flow avoids calling this
  /// and uses `Image.network` instead.
  Future<ui.Image> loadImage(String url) async {
    final resp = await http.get(
      Uri.parse(url),
      headers: const {
        'User-Agent': 'PoseTrainer/0.1 (contact: example@example.com)',
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final codec = await ui.instantiateImageCodec(resp.bodyBytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
