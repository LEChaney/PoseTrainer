import 'dart:async';
import 'package:flutter/foundation.dart';

// timer_service.dart
// ------------------
// A tiny reusable timer. Widgets can watch it (via Provider) to rebuild when
// elapsed time changes. Using a service keeps timing logic out of UI code.

class TimerService extends ChangeNotifier {
  Timer? _timer; // Periodic timer instance
  Duration _elapsed = Duration.zero; // Accumulated elapsed time
  bool _running = false; // Whether the timer is currently ticking

  Duration get elapsed => _elapsed;
  bool get isRunning => _running;

  /// Start ticking forward. `step` is how often we increment elapsed.
  void start({Duration step = const Duration(seconds: 1)}) {
    if (_running) return; // Guard: ignore if already running
    _running = true;
    _timer = Timer.periodic(step, (t) {
      _elapsed += step;
      notifyListeners(); // Tell listeners (widgets) to rebuild with new value
    });
    notifyListeners();
  }

  /// Pause without clearing the elapsed value.
  void pause() {
    _timer?.cancel();
    _running = false;
    notifyListeners();
  }

  /// Stop and clear elapsed time.
  void reset() {
    _timer?.cancel();
    _running = false;
    _elapsed = Duration.zero;
    notifyListeners();
  }
}
