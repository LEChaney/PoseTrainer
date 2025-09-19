import 'dart:ui' as ui;

class PracticeResult {
  final ui.Image? drawing;
  final bool skipped;
  const PracticeResult.skipped() : drawing = null, skipped = true;
  const PracticeResult.completed(this.drawing) : skipped = false;
}
