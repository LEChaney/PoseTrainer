import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/session_service.dart';
import 'review_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final history = context.watch<SessionService>().history;
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: history.isEmpty
          ? const Center(child: Text('No sessions yet.'))
          : ListView.separated(
              itemCount: history.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final s = history[i];
                return ListTile(
                  title: Text(
                    s.sourceUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(s.endedAt.toLocal().toString()),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReviewScreen(
                        reference: s.reference,
                        drawing: s.drawing,
                        sourceUrl: s.sourceUrl,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
