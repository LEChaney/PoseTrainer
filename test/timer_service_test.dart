import 'package:flutter_test/flutter_test.dart';
import 'package:posecoach/services/timer_service.dart';

void main() {
  test(
    'TimerService start accumulates elapsed on manual tick simulation',
    () async {
      final svc = TimerService();
      expect(svc.elapsed, Duration.zero);
      svc.start(step: const Duration(milliseconds: 10));
      await Future.delayed(const Duration(milliseconds: 35));
      svc.pause();
      expect(svc.elapsed >= const Duration(milliseconds: 20), true);
    },
  );
}
