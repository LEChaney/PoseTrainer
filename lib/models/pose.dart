import 'package:flutter/foundation.dart';

enum PoseDifficulty { easy, medium, hard }

class Pose {
  final String id;
  final Duration duration;
  final String? imageUrl; // optional reference image
  final PoseDifficulty difficulty;
  final String? note;

  Pose({
    required this.id,
    required this.duration,
    this.imageUrl,
    this.difficulty = PoseDifficulty.easy,
    this.note,
  });

  static List<Pose> sampleSet() => [
    Pose(
      id: 'warmup1',
      duration: const Duration(seconds: 30),
      difficulty: PoseDifficulty.easy,
    ),
    Pose(
      id: 'gesture1',
      duration: const Duration(minutes: 1),
      difficulty: PoseDifficulty.easy,
    ),
    Pose(
      id: 'gesture2',
      duration: const Duration(minutes: 1),
      difficulty: PoseDifficulty.easy,
    ),
    Pose(
      id: 'long1',
      duration: const Duration(minutes: 5),
      difficulty: PoseDifficulty.medium,
    ),
  ];
}

@immutable
class PoseProgress {
  final Pose pose;
  final Duration elapsed;
  const PoseProgress({required this.pose, required this.elapsed});

  double get fraction => pose.duration.inMilliseconds == 0
      ? 0
      : (elapsed.inMilliseconds / pose.duration.inMilliseconds).clamp(0, 1);
  bool get isComplete => elapsed >= pose.duration;
}
