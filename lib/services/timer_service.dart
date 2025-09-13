import 'dart:async';
import 'package:flutter/foundation.dart';

class TimerService extends ChangeNotifier {
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _running = false;

  Duration get elapsed => _elapsed;
  bool get isRunning => _running;

  void start({Duration step = const Duration(seconds: 1)}) {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(step, (t) {
      _elapsed += step;
      notifyListeners();
    });
    notifyListeners();
  }

  void pause() {
    _timer?.cancel();
    _running = false;
    notifyListeners();
  }

  void reset() {
    _timer?.cancel();
    _running = false;
    _elapsed = Duration.zero;
    notifyListeners();
  }
}
