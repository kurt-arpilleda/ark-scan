import 'dart:ui';
import 'corner_detector.dart';
import 'scan_config.dart';

class StabilityTracker {
  List<Offset>? _anchor;
  List<Offset>? _previous;
  int _streak = 0;
  int _misses = 0;
  final Stopwatch _clock = Stopwatch();

  bool get isStable => _streak >= kStableFrames && _clock.elapsedMilliseconds >= kStableMillis;

  void reset() {
    _anchor = null;
    _previous = null;
    _streak = 0;
    _misses = 0;
    _clock
      ..stop()
      ..reset();
  }

  bool update(FrameAnalysis analysis) {
    if (!analysis.ready) {
      _misses++;
      if (_misses > kGraceFrames) reset();
      return false;
    }
    _misses = 0;

    final centers = analysis.marks.whereType<Rect>().map((m) => Offset(m.center.dx, m.center.dy / analysis.aspect)).toList();
    final previous = _previous;
    final anchor = _anchor;

    if (previous == null ||
        anchor == null ||
        _maxShift(centers, previous) > kFrameMoveTolerance ||
        _maxShift(centers, anchor) > kAnchorTolerance) {
      _anchor = centers;
      _streak = 1;
      _clock
        ..reset()
        ..start();
    } else {
      _streak++;
    }
    _previous = centers;
    return isStable;
  }

  double _maxShift(List<Offset> a, List<Offset> b) {
    double worst = 0;
    for (int i = 0; i < a.length && i < b.length; i++) {
      final d = (a[i] - b[i]).distance;
      if (d > worst) worst = d;
    }
    return worst;
  }
}