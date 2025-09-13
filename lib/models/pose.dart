import 'package:flutter/foundation.dart';

// pose.dart
// ---------
// A "model" file: small immutable data classes that represent domain
// concepts. Keeping models simple (no UI code) makes them easy to test and
// reuse.

// Enum = fixed set of named values. Lets us express difficulty in a type
// safe way instead of using strings like 'easy'.
enum PoseDifficulty { easy, medium, hard }

class Pose {
  // Unique id so we can reference this pose in lists or logs.
  final String id;
  // How long the user should draw this pose during a timed session.
  final Duration duration;
  // Optional reference image URL (legacy / placeholder concept — newer
  // reference flow uses external search instead of static URLs here).
  final String? imageUrl; // optional reference image
  final PoseDifficulty difficulty;
  // Optional developer / future user note.
  final String? note;

  const Pose({
    required this.id,
    required this.duration,
    this.imageUrl,
    this.difficulty = PoseDifficulty.easy,
    this.note,
  });

  // A small hard‑coded sample list for early development. In production this
  // could be generated or loaded from user configuration.
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
  // The pose we are currently timing.
  final Pose pose;
  // How much time has elapsed for this pose so far.
  final Duration elapsed;
  const PoseProgress({required this.pose, required this.elapsed});

  // Returns a number between 0 and 1 for UI progress bars. Guard against
  // divide-by-zero if a duration were accidentally zero.
  double get fraction => pose.duration.inMilliseconds == 0
      ? 0
      : (elapsed.inMilliseconds / pose.duration.inMilliseconds).clamp(0, 1);
  bool get isComplete => elapsed >= pose.duration;
}
