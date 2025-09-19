import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/session_service.dart';
import '../services/storage_diagnostics.dart';

class StorageDiagnosticsScreen extends StatefulWidget {
  const StorageDiagnosticsScreen({super.key});
  @override
  State<StorageDiagnosticsScreen> createState() =>
      _StorageDiagnosticsScreenState();
}

class _StorageDiagnosticsScreenState extends State<StorageDiagnosticsScreen> {
  Future<StorageInfo>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sessions = context.read<SessionService>().history.length;
    _future = getStorageInfo(sessionsCount: sessions);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Clear storage',
            icon: const Icon(Icons.delete_forever),
            onPressed: _confirmAndClear,
          ),
        ],
      ),
      body: FutureBuilder<StorageInfo>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Failed to load diagnostics: ${snap.error}'),
              ),
            );
          }
          final info = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _kv('OPFS available', info.opfsAvailable ? 'Yes' : 'No'),
              _kv('Persistent granted', info.persistentGranted ? 'Yes' : 'No'),
              _kv('Sessions count', info.sessionsCount.toString()),
              _kv('Usage', _fmtBytes(info.usageBytes)),
              _kv('Quota', _fmtBytes(info.quotaBytes)),
              const SizedBox(height: 16),
              Text('Notes', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text(
                'OPFS typically stores drawings efficiently and is less costly to write than IndexedDB blobs. '
                'Persistent storage reduces eviction risk on low-disk situations. '
                'On browsers without OPFS, the app falls back to IndexedDB (Hive).',
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmAndClear() async {
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all stored data?'),
        content: const Text(
          'This will delete saved sessions and drawings from persistent storage. '
          'You can’t undo this. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => navigator.pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await clearAllStorage();
    // Also refresh in-memory session list so UI updates immediately.
    try {
      context.read<SessionService>().clear();
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Storage cleared. Reload the app.')),
    );
    setState(() {
      // Refresh diagnostics after clearing.
      final sessions = context.read<SessionService>().history.length;
      _future = getStorageInfo(sessionsCount: sessions);
    });
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(k)),
          Text(
            v,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtBytes(int? n) {
    if (n == null) return '—';
    const units = ['B', 'KB', 'MB', 'GB'];
    double s = n.toDouble();
    int idx = 0;
    while (s >= 1024 && idx < units.length - 1) {
      s /= 1024;
      idx++;
    }
    return '${s.toStringAsFixed(1)} ${units[idx]}';
  }
}
