import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'scan_config.dart';

class FrameAnalysis {
  final List<Rect?> marks;
  final double sharpness;
  final double brightness;
  final bool geometryValid;
  final double aspect;

  const FrameAnalysis({
    required this.marks,
    required this.sharpness,
    required this.brightness,
    required this.geometryValid,
    required this.aspect,
  });

  factory FrameAnalysis.empty() => const FrameAnalysis(
    marks: [null, null, null, null],
    sharpness: 0,
    brightness: 0,
    geometryValid: false,
    aspect: 1,
  );

  int get count => marks.where((m) => m != null).length;
  bool get allFound => count == 4;
  bool get sharpEnough => sharpness >= kMinSharpness;
  bool get exposureOk => brightness >= kMinBrightness && brightness <= kMaxBrightness;
  bool get ready => allFound && geometryValid && sharpEnough && exposureOk;
}

class _Mark {
  final Rect rect;
  final double sharpness;

  _Mark(this.rect, this.sharpness);
}

class _MarkStats {
  final double innerMean;
  final double innerDark;
  final double contrast;
  final double sharpness;

  _MarkStats(this.innerMean, this.innerDark, this.contrast, this.sharpness);
}

Future<FrameAnalysis> analyzeFrame(CameraImage image, int sensorOrientation) async {
  final gray = _extractGray(image);
  final grayMat = cv.Mat.fromList(image.height, image.width, cv.MatType.CV_8UC1, gray);
  final rotated = _rotateMat(grayMat, sensorOrientation);
  grayMat.dispose();
  final analysis = _analyzeMat(rotated);
  rotated.dispose();
  return analysis;
}

FrameAnalysis analyzeStill(String path, int sensorOrientation) {
  final mat = cv.imread(path, flags: cv.IMREAD_GRAYSCALE);
  if (mat.isEmpty) {
    mat.dispose();
    return FrameAnalysis.empty();
  }
  cv.Mat oriented = mat;
  if (mat.cols > mat.rows) {
    oriented = _rotateMat(mat, sensorOrientation);
    mat.dispose();
  }
  final analysis = _analyzeMat(oriented);
  oriented.dispose();
  return analysis;
}

FrameAnalysis _analyzeMat(cv.Mat mat) {
  final w = mat.cols;
  final h = mat.rows;
  if (w == 0 || h == 0) return FrameAnalysis.empty();
  final data = mat.data;
  final boxPx = (w * kBoxSizeFrac).round();
  final regions = <cv.Rect>[
    cv.Rect((w * kMarginX).round(), (h * kMarginY).round(), boxPx, boxPx),
    cv.Rect((w * (1 - kMarginX)).round() - boxPx, (h * kMarginY).round(), boxPx, boxPx),
    cv.Rect((w * kMarginX).round(), (h * (1 - kMarginY)).round() - boxPx, boxPx, boxPx),
    cv.Rect((w * (1 - kMarginX)).round() - boxPx, (h * (1 - kMarginY)).round() - boxPx, boxPx, boxPx),
  ];

  final marks = <Rect?>[];
  double sharpSum = 0;
  int sharpCount = 0;
  for (final r in regions) {
    final mark = _detectSquare(data, w, h, r);
    if (mark == null) {
      marks.add(null);
      continue;
    }
    marks.add(Rect.fromLTWH(
      mark.rect.left / w,
      mark.rect.top / h,
      mark.rect.width / w,
      mark.rect.height / h,
    ));
    sharpSum += mark.sharpness;
    sharpCount++;
  }

  return FrameAnalysis(
    marks: marks,
    sharpness: sharpCount == 0 ? 0 : sharpSum / sharpCount,
    brightness: _meanBrightness(data, w, h),
    geometryValid: _validGeometry(marks, w, h),
    aspect: w / h,
  );
}

_Mark? _detectSquare(Uint8List full, int fullCols, int fullRows, cv.Rect roi) {
  if (roi.x < 0 || roi.y < 0 || roi.x + roi.width > fullCols || roi.y + roi.height > fullRows) {
    return null;
  }
  final bytes = _cropGray(full, fullCols, roi.x, roi.y, roi.width, roi.height);
  final roiMat = cv.Mat.fromList(roi.height, roi.width, cv.MatType.CV_8UC1, bytes);
  final (_, binary) = cv.threshold(roiMat, 0, 255, cv.THRESH_BINARY_INV | cv.THRESH_OTSU);

  final roiArea = (roi.width * roi.height).toDouble();
  final darkRatio = cv.countNonZero(binary) / roiArea;
  if (darkRatio > 0.6 || darkRatio < 0.004) {
    binary.dispose();
    roiMat.dispose();
    return null;
  }

  final (contours, hierarchy) = cv.findContours(binary, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);

  _Mark? best;
  double bestArea = 0;

  for (final c in contours) {
    final area = cv.contourArea(c);
    if (area < roiArea * kMinAreaFrac || area > roiArea * kMaxAreaFrac) continue;

    final perimeter = cv.arcLength(c, true);
    final approx = cv.approxPolyDP(c, perimeter * 0.04, true);
    if (approx.length != 4) continue;
    if (!cv.isContourConvex(approx)) continue;

    final rect = cv.boundingRect(c);
    if (rect.x <= 1 ||
        rect.y <= 1 ||
        rect.x + rect.width >= roi.width - 1 ||
        rect.y + rect.height >= roi.height - 1) {
      continue;
    }

    final ratio = rect.width / rect.height;
    if (ratio < 0.7 || ratio > 1.3) continue;

    final extent = area / (rect.width * rect.height);
    if (extent < 0.68) continue;

    if (area <= bestArea) continue;

    final stats = _markStats(bytes, roi.width, roi.height, rect.x, rect.y, rect.width, rect.height);
    if (stats == null) continue;
    if (stats.innerMean > 140 || stats.innerDark < kMinInnerDark || stats.contrast < kMinContrast) {
      continue;
    }

    bestArea = area;
    best = _Mark(
      Rect.fromLTWH(
        (roi.x + rect.x).toDouble(),
        (roi.y + rect.y).toDouble(),
        rect.width.toDouble(),
        rect.height.toDouble(),
      ),
      stats.sharpness,
    );
  }

  roiMat.dispose();
  binary.dispose();
  hierarchy.dispose();
  return best;
}

_MarkStats? _markStats(Uint8List b, int cw, int ch, int rx, int ry, int rw, int rh) {
  final pad = math.max(3, (math.min(rw, rh) * 0.4).round());
  final x0 = math.max(1, rx - pad);
  final y0 = math.max(1, ry - pad);
  final x1 = math.min(cw - 2, rx + rw + pad - 1);
  final y1 = math.min(ch - 2, ry + rh + pad - 1);
  final ix0 = rx + (rw * 0.25).round();
  final ix1 = rx + rw - (rw * 0.25).round();
  final iy0 = ry + (rh * 0.25).round();
  final iy1 = ry + rh - (rh * 0.25).round();
  if (ix1 <= ix0 || iy1 <= iy0 || x1 <= x0 || y1 <= y0) return null;

  int innerSum = 0;
  int innerN = 0;
  for (int y = iy0; y < iy1; y++) {
    final row = y * cw;
    for (int x = ix0; x < ix1; x++) {
      innerSum += b[row + x];
      innerN++;
    }
  }

  int ringSum = 0;
  int ringN = 0;
  for (int y = y0; y <= y1; y++) {
    final row = y * cw;
    final inRows = y >= ry && y < ry + rh;
    for (int x = x0; x <= x1; x++) {
      if (inRows && x >= rx && x < rx + rw) continue;
      ringSum += b[row + x];
      ringN++;
    }
  }
  if (innerN == 0 || ringN == 0) return null;

  final innerMean = innerSum / innerN;
  final ringMean = ringSum / ringN;
  final contrast = ringMean - innerMean;
  if (contrast <= 0) return null;

  final level = (innerMean + ringMean) / 2;
  int darkN = 0;
  for (int y = iy0; y < iy1; y++) {
    final row = y * cw;
    for (int x = ix0; x < ix1; x++) {
      if (b[row + x] <= level) darkN++;
    }
  }
  final innerDark = darkN / innerN;

  double gxSum = 0;
  int gxN = 0;
  for (int y = iy0; y < iy1; y++) {
    final row = y * cw;
    double bestG = 0;
    for (int x = x0; x <= x1; x++) {
      final g = (b[row + x + 1] - b[row + x - 1]).abs() / 2;
      if (g > bestG) bestG = g;
    }
    gxSum += bestG;
    gxN++;
  }

  double gySum = 0;
  int gyN = 0;
  for (int x = ix0; x < ix1; x++) {
    double bestG = 0;
    for (int y = y0; y <= y1; y++) {
      final g = (b[(y + 1) * cw + x] - b[(y - 1) * cw + x]).abs() / 2;
      if (g > bestG) bestG = g;
    }
    gySum += bestG;
    gyN++;
  }

  final gx = gxN == 0 ? 0.0 : gxSum / gxN;
  final gy = gyN == 0 ? 0.0 : gySum / gyN;
  final sharpness = math.min(gx, gy) / contrast;
  return _MarkStats(innerMean, innerDark, contrast, sharpness);
}

double _meanBrightness(Uint8List data, int w, int h) {
  int sum = 0;
  int count = 0;
  for (int y = 0; y < h; y += 6) {
    final row = y * w;
    for (int x = 0; x < w; x += 6) {
      sum += data[row + x];
      count++;
    }
  }
  if (count == 0) return 0;
  return sum / count;
}

double _cosBetween(Offset a, Offset b) {
  final d = a.distance * b.distance;
  if (d == 0) return 1;
  return (a.dx * b.dx + a.dy * b.dy) / d;
}

bool _validGeometry(List<Rect?> marks, int w, int h) {
  final rects = marks.whereType<Rect>().toList();
  if (rects.length != 4) return false;

  final p = rects.map((m) => Offset(m.center.dx * w, m.center.dy * h)).toList();
  final sizes = rects.map((m) => math.sqrt((m.width * w) * (m.height * h))).toList();
  final minSize = sizes.reduce(math.min);
  final maxSize = sizes.reduce(math.max);
  if (minSize <= 0 || maxSize / minSize > kMaxSizeRatio) return false;

  final top = p[1] - p[0];
  final bottom = p[3] - p[2];
  final left = p[2] - p[0];
  final right = p[3] - p[1];
  if (top.distance == 0 || bottom.distance == 0 || left.distance == 0 || right.distance == 0) {
    return false;
  }

  final hr = top.distance / bottom.distance;
  final vr = left.distance / right.distance;
  if (hr > kMaxEdgeRatio || hr < 1 / kMaxEdgeRatio) return false;
  if (vr > kMaxEdgeRatio || vr < 1 / kMaxEdgeRatio) return false;

  final rotation = math.atan2(top.dy, top.dx).abs() * 180 / math.pi;
  if (rotation > kMaxRotationDeg) return false;

  if (_cosBetween(top, left).abs() > kMaxSkewCos) return false;
  if (_cosBetween(top, right).abs() > kMaxSkewCos) return false;
  if (_cosBetween(bottom, left).abs() > kMaxSkewCos) return false;
  if (_cosBetween(bottom, right).abs() > kMaxSkewCos) return false;

  final mid1 = (p[0] + p[3]) / 2;
  final mid2 = (p[1] + p[2]) / 2;
  final diag = ((p[3] - p[0]).distance + (p[2] - p[1]).distance) / 2;
  if (diag == 0 || (mid1 - mid2).distance / diag > kMaxMidpointOffset) return false;

  return true;
}

Uint8List _cropGray(Uint8List full, int cols, int x0, int y0, int w, int h) {
  final out = Uint8List(w * h);
  for (int r = 0; r < h; r++) {
    final srcStart = (y0 + r) * cols + x0;
    out.setRange(r * w, r * w + w, full, srcStart);
  }
  return out;
}

cv.Mat _rotateMat(cv.Mat src, int sensorOrientation) {
  switch (sensorOrientation) {
    case 90:
      return cv.rotate(src, cv.ROTATE_90_CLOCKWISE);
    case 180:
      return cv.rotate(src, cv.ROTATE_180);
    case 270:
      return cv.rotate(src, cv.ROTATE_90_COUNTERCLOCKWISE);
    default:
      return src.clone();
  }
}

Uint8List _extractGray(CameraImage image) {
  final width = image.width;
  final height = image.height;
  final plane = image.planes[0];
  if (image.format.group == ImageFormatGroup.bgra8888) {
    final bytesPerRow = plane.bytesPerRow;
    final bytes = plane.bytes;
    final gray = Uint8List(width * height);
    for (int y = 0; y < height; y++) {
      final rowStart = y * bytesPerRow;
      for (int x = 0; x < width; x++) {
        final idx = rowStart + x * 4;
        final b = bytes[idx];
        final g = bytes[idx + 1];
        final r = bytes[idx + 2];
        gray[y * width + x] = (r * 299 + g * 587 + b * 114) ~/ 1000;
      }
    }
    return gray;
  }
  if (plane.bytesPerRow == width) {
    return Uint8List.sublistView(plane.bytes, 0, width * height);
  }
  final gray = Uint8List(width * height);
  for (int y = 0; y < height; y++) {
    final srcStart = y * plane.bytesPerRow;
    gray.setRange(y * width, y * width + width, plane.bytes, srcStart);
  }
  return gray;
}