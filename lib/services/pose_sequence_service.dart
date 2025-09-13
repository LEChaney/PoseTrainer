import 'package:flutter/foundation.dart';
import '../models/pose.dart';

// pose_sequence_service.dart
// --------------------------
// Drives a timed sequence of `Pose` objects (legacy feature). Components can
// listen to it for progress updates. This logic intentionally lives outside
// the UI layer so timing/state can be tested or swapped easily.

class PoseSequenceService extends ChangeNotifier {
  final List<Pose> poses; // Ordered list of poses to cycle through
  final int cycles; // How many times to repeat the full list
  int _currentPoseIndex = 0; // Index into `poses`
  int _currentCycle = 0; // Completed cycle count
  Duration _currentElapsed = Duration.zero; // Elapsed time on current pose
  bool _active = false; // Whether sequence is currently running

  PoseSequenceService({required this.poses, this.cycles = 1});

  Pose get currentPose => poses[_currentPoseIndex];
  int get currentPoseIndex => _currentPoseIndex;
  int get currentCycle => _currentCycle;
  bool get isActive => _active;
  Duration get elapsedCurrent => _currentElapsed;

  // Convenience object for UI progress bars.
  PoseProgress get progress =>
      PoseProgress(pose: currentPose, elapsed: _currentElapsed);

  /// Advance elapsed time. Caller supplies `delta` (time since last tick)
  /// instead of this service owning a Timer—gives more control to UI.
  void tick(Duration delta) {
    if (!_active) return;
    _currentElapsed += delta;
    if (_currentElapsed >= currentPose.duration) {
      _advance();
    } else {
      notifyListeners();
    }
  }

  /// Begin a run from the start. If `silent` true we suppress the initial
  /// notify to avoid a redundant rebuild during setup.
  void start({bool silent = false}) {
    if (_active) return;
    _active = true;
    _currentPoseIndex = 0;
    _currentCycle = 0;
    _currentElapsed = Duration.zero;
    if (!silent) notifyListeners();
  }

  /// Immediately halt progression (does not reset indices).
  void stop() {
    _active = false;
    notifyListeners();
  }

  /// Move to next pose or cycle; stop when all cycles complete.
  void _advance() {
    _currentElapsed = Duration.zero;
    _currentPoseIndex++;
    if (_currentPoseIndex >= poses.length) {
      _currentPoseIndex = 0;
      _currentCycle++;
      if (_currentCycle >= cycles) {
        _active = false; // finished all cycles
      }
    }
    notifyListeners();
  }
}
