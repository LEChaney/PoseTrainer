import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/session_service.dart';
import 'review_screen.dart';
import '../models/practice_session.dart';
import '../theme/colors.dart';

// history_screen.dart
// -------------------
// WHY this screen: After finishing practice users often want to quickly revisit
// earlier attempts for pattern spotting (e.g. consistently short forearms). A
// lightweight, always-available list gives rapid access without committing to a
// heavy gallery feature yet.
// CURRENT SCOPE:
// - In-memory only: list is lost on app restart (persistence deferred).
// - Minimal metadata: just source URL + finished timestamp; adding tags or pose
//   labels can wait until we store structured reference metadata.
// DESIGN NOTES:
// - Keep build simple: early return for empty state improves readability.
// - Navigation isolates review concerns: we pass only what ReviewScreen needs
//   (images + sourceUrl) leaving session model evolution isolated from it.
// FUTURE:
// - Add disk persistence, filtering, maybe quick overlay launch from thumbnail.
// - Could show small time delta or duration once we finalize timing semantics.
// READABILITY STRATEGY:
// - Extract list & tile widgets; name them descriptively.
// - Avoid multi-underscore param placeholders (lint) by giving simple names.

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final history = context.watch<SessionService>().history;
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: history.isEmpty
          ? const _EmptyHistoryMessage()
          : _HistoryList(sessions: history),
    );
  }
}

// --- Empty State -----------------------------------------------------------

class _EmptyHistoryMessage extends StatelessWidget {
  const _EmptyHistoryMessage();
  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('No sessions yet.'));
}

// --- List + Tiles ----------------------------------------------------------

class _HistoryList extends StatelessWidget {
  final List<PracticeSession> sessions;
  const _HistoryList({required this.sessions});
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: sessions.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) => _HistoryTile(session: sessions[index]),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final PracticeSession session;
  const _HistoryTile({required this.session});
  @override
  Widget build(BuildContext context) {
    // Single tap: push the review screen using a Material route. We deliberately
    // avoid Hero animations or extra transitions to keep iteration fast.
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      leading: _ThumbPair(session: session),
      title: Text(
        session.sourceUrl,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(session.endedAt.toLocal().toString()),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => ReviewScreen(
            reference: session.reference,
            referenceUrl: session.referenceUrl,
            drawing: session.drawing,
            sourceUrl: session.sourceUrl,
            initialOverlay: session.overlay,
          ),
        ),
      ),
    );
  }
}

class _ThumbPair extends StatelessWidget {
  final PracticeSession session;
  const _ThumbPair({required this.session});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Row(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: const BoxDecoration(color: kReferencePanelColor),
                child: session.reference != null
                    ? FittedBox(
                        fit: BoxFit.cover,
                        child: RawImage(image: session.reference),
                      )
                    : (session.referenceUrl != null
                          ? Image.network(
                              session.referenceUrl!,
                              fit: BoxFit.cover,
                            )
                          : const SizedBox.shrink()),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: const BoxDecoration(color: kPaperColor),
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: RawImage(image: session.drawing),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
