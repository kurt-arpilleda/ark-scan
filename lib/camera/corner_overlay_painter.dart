import 'package:flutter/material.dart';
import 'scan_config.dart';

class CornerOverlayPainter extends CustomPainter {
  final List<Rect?> marks;

  CornerOverlayPainter(this.marks);

  @override
  void paint(Canvas canvas, Size size) {
    final boxSize = size.width * kBoxSizeFrac;
    final marginX = size.width * kMarginX;
    final marginY = size.height * kMarginY;

    final guideRects = [
      Rect.fromLTWH(marginX, marginY, boxSize, boxSize),
      Rect.fromLTWH(size.width - marginX - boxSize, marginY, boxSize, boxSize),
      Rect.fromLTWH(marginX, size.height - marginY - boxSize, boxSize, boxSize),
      Rect.fromLTWH(size.width - marginX - boxSize, size.height - marginY - boxSize, boxSize, boxSize),
    ];

    final guidePaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final markFillPaint = Paint()
      ..color = Colors.greenAccent.shade400
      ..style = PaintingStyle.fill;

    final markBorderPaint = Paint()
      ..color = Colors.green.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (int i = 0; i < guideRects.length; i++) {
      canvas.drawRect(guideRects[i], guidePaint);

      final normalizedMark = i < marks.length ? marks[i] : null;
      if (normalizedMark == null) continue;

      final markRect = Rect.fromLTWH(
        normalizedMark.left * size.width,
        normalizedMark.top * size.height,
        normalizedMark.width * size.width,
        normalizedMark.height * size.height,
      );

      canvas.drawRect(markRect, markFillPaint);
      canvas.drawRect(markRect, markBorderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CornerOverlayPainter oldDelegate) {
    return oldDelegate.marks != marks;
  }
}