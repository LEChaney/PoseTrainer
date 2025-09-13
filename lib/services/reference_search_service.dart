import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
  bool _loading = false;
  String? _error;
  List<ReferenceResult> _results = [];

  bool get isLoading => _loading;
  String? get error => _error;
  List<ReferenceResult> get results => List.unmodifiable(_results);

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
      final q = cleaned.replaceAll(RegExp(r'\s+'), '+');
      final uri = Uri.parse(
        'https://e621.net/posts.json?limit=30&tags=rating:safe+$q',
      );
      final resp = await http.get(
        uri,
        headers: const {
          'User-Agent': 'PoseCoach/0.1 (contact: example@example.com)',
        },
      );
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final posts = (data['posts'] as List? ?? []);
      _results = posts
          .map((e) => e as Map<String, dynamic>)
          .where((m) => m['preview']?['url'] != null)
          .map(
            (m) => ReferenceResult(
              id: '${m['id']}',
              previewUrl: m['preview']['url'] as String,
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

  Future<ui.Image> loadImage(String url) async {
    final resp = await http.get(
      Uri.parse(url),
      headers: const {
        'User-Agent': 'PoseCoach/0.1 (contact: example@example.com)',
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
