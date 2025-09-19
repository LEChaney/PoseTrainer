import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/practice_session.dart';
import '../models/practice_result.dart';
import '../models/review_result.dart';
import '../services/reference_search_service.dart';
import '../services/session_service.dart';
import 'practice_screen.dart';
import 'review_screen.dart';
import 'history_screen.dart';

/// Drives a multi-image timed practice session.
class SessionRunnerScreen extends StatefulWidget {
  final List<ReferenceResult> items;
  final int secondsPerImage;
  const SessionRunnerScreen({
    super.key,
    required this.items,
    required this.secondsPerImage,
  });

  @override
  State<SessionRunnerScreen> createState() => _SessionRunnerScreenState();
}

class _SessionRunnerScreenState extends State<SessionRunnerScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCurrent());
  }

  Future<void> _startCurrent() async {
    if (!mounted) return;
    if (_index >= widget.items.length) {
      // All done -> show history list for quick revisit
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HistoryScreen()),
      );
      return;
    }
    final item = widget.items[_index];
    final sourceUrl = 'https://e621.net/posts/${item.id}';
    ui.Image? decoded;
    String? url;
    if (kIsWeb) {
      url = item.fullUrl.isNotEmpty ? item.fullUrl : item.previewUrl;
    } else {
      try {
        decoded = await context.read<ReferenceSearchService>().loadImage(
          item.fullUrl,
        );
      } catch (_) {
        // Fall back to URL if decode fails (still allow drawing side-by-side)
        url = item.fullUrl;
      }
    }
    if (!mounted) return;
    final practiceResult = await Navigator.of(context).push<PracticeResult>(
      MaterialPageRoute(
        builder: (_) => PracticeScreen(
          reference: decoded,
          referenceUrl: url,
          sourceUrl: sourceUrl,
          timeLimitSeconds: widget.secondsPerImage,
          sessionMode: true,
        ),
      ),
    );
    if (!mounted) return;
    if (practiceResult == null) return; // user backed out
    if (practiceResult.skipped) {
      // Skip without saving; advance to next
      setState(() => _index++);
      _startCurrent();
      return;
    }
    final drawing = practiceResult.drawing!;
    // Show review to allow overlay tweak and then choose Next/Finish
    final reviewResult = await Navigator.of(context).push<ReviewResult>(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          reference: decoded,
          referenceUrl: url,
          drawing: drawing,
          sourceUrl: sourceUrl,
          initialOverlay: const OverlayTransform(
            scale: 1.0,
            offset: ui.Offset.zero,
          ),
          sessionControls: true,
          isLast: _index == widget.items.length - 1,
        ),
      ),
    );
    if (!mounted) return;
    if (reviewResult != null && reviewResult.save) {
      context.read<SessionService>().add(
        sourceUrl: sourceUrl,
        reference: decoded,
        referenceUrl: url,
        drawing: drawing,
        overlay: reviewResult.overlay,
      );
    }
    if (reviewResult == null || reviewResult.action == ReviewAction.next) {
      setState(() => _index++);
      _startCurrent();
    } else {
      // End requested -> go to history
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HistoryScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
