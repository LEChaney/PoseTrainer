import 'package:flutter_test/flutter_test.dart';
import 'package:posecoach/models/pose.dart';
import 'package:posecoach/services/pose_sequence_service.dart';

void main() {
  test('PoseSequenceService advances after duration', () {
    final poses = [
      Pose(id: 'a', duration: const Duration(seconds: 1)),
      Pose(id: 'b', duration: const Duration(seconds: 1)),
    ];
    final seq = PoseSequenceService(poses: poses, cycles: 1);
    seq.start();
    expect(seq.currentPose.id, 'a');
    seq.tick(const Duration(seconds: 1));
    expect(seq.currentPose.id, 'b');
    seq.tick(const Duration(seconds: 1));
    expect(
      seq.isActive,
      false,
      reason: 'Sequence should finish after last pose',
    );
  });
}
