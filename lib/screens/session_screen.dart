import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/pose_sequence_service.dart';
import '../services/timer_service.dart';
import '../models/pose.dart';

// TODO: Legacy timed pose sequence screen. Keep temporarily until new timed
// practice integrates with reference-driven sessions.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Defer startup until after first frame to avoid notifying providers during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final seq = context.read<PoseSequenceService>();
      // Start silently then trigger an initial manual notify by tick(0) below.
      seq.start(silent: true);
      final timerSvc = context.read<TimerService>();
      timerSvc.reset();
      timerSvc.start(step: const Duration(seconds: 1));
      // Force a zero-delta tick to push initial state to listeners after build.
      seq.tick(Duration.zero);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        seq.tick(const Duration(seconds: 1));
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    context.read<TimerService>().pause();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Session')),
      body: Consumer<PoseSequenceService>(
        builder: (context, seq, _) {
          final progress = seq.progress;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Cycle ${seq.currentCycle + 1} / ${seq.cycles}'),
                Text('Pose ${seq.currentPoseIndex + 1} / ${seq.poses.length}'),
                const SizedBox(height: 8),
                _PoseCountdown(progress: progress),
                const SizedBox(height: 24),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blueGrey.shade100),
                    ),
                    child: Center(
                      child: Text(
                        progress.pose.id,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (!seq.isActive)
                  FilledButton(
                    onPressed: () {
                      seq.start();
                    },
                    child: const Text('Restart Sequence'),
                  )
                else
                  FilledButton.tonal(
                    onPressed: () => seq.stop(),
                    child: const Text('Stop'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PoseCountdown extends StatelessWidget {
  final PoseProgress progress;
  const _PoseCountdown({required this.progress});

  @override
  Widget build(BuildContext context) {
    final remaining = progress.pose.duration - progress.elapsed;
    String fmt(Duration d) =>
        '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: progress.fraction),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Elapsed: ${fmt(progress.elapsed)}'),
            Text(
              'Remaining: ${fmt(remaining.isNegative ? Duration.zero : remaining)}',
            ),
          ],
        ),
      ],
    );
  }
}
