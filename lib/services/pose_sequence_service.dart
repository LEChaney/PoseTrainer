import 'package:flutter/foundation.dart';
import '../models/pose.dart';

class PoseSequenceService extends ChangeNotifier {
  final List<Pose> poses;
  final int cycles;
  int _currentPoseIndex = 0;
  int _currentCycle = 0;
  Duration _currentElapsed = Duration.zero;
  bool _active = false;

  PoseSequenceService({required this.poses, this.cycles = 1});

  Pose get currentPose => poses[_currentPoseIndex];
  int get currentPoseIndex => _currentPoseIndex;
  int get currentCycle => _currentCycle;
  bool get isActive => _active;
  Duration get elapsedCurrent => _currentElapsed;

  PoseProgress get progress =>
      PoseProgress(pose: currentPose, elapsed: _currentElapsed);

  void tick(Duration delta) {
    if (!_active) return;
    _currentElapsed += delta;
    if (_currentElapsed >= currentPose.duration) {
      _advance();
    } else {
      notifyListeners();
    }
  }

  void start({bool silent = false}) {
    if (_active) return;
    _active = true;
    _currentPoseIndex = 0;
    _currentCycle = 0;
    _currentElapsed = Duration.zero;
    if (!silent) notifyListeners();
  }

  void stop() {
    _active = false;
    notifyListeners();
  }

  void _advance() {
    _currentElapsed = Duration.zero;
    _currentPoseIndex++;
    if (_currentPoseIndex >= poses.length) {
      _currentPoseIndex = 0;
      _currentCycle++;
      if (_currentCycle >= cycles) {
        _active = false;
      }
    }
    notifyListeners();
  }
}
