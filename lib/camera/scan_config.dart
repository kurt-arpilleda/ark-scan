import 'package:camera/camera.dart';

const double kMarginX = 0.05;
const double kMarginY = 0.04;
const double kBoxSizeFrac = 0.15;

const ResolutionPreset kCaptureResolution = ResolutionPreset.medium;

const double kMinAreaFrac = 0.012;
const double kMaxAreaFrac = 0.6;
const double kMinInnerDark = 0.85;
const double kMinContrast = 55.0;

const double kMinSharpness = 0.22;
const double kStillSharpnessFactor = 0.6;
const double kMinBrightness = 70.0;
const double kMaxBrightness = 225.0;

const double kMaxSizeRatio = 1.7;
const double kMaxEdgeRatio = 1.35;
const double kMaxSkewCos = 0.3;
const double kMaxRotationDeg = 18.0;
const double kMaxMidpointOffset = 0.08;

const int kStableFrames = 3;
const int kStableMillis = 150;
const int kGraceFrames = 1;
const double kFrameMoveTolerance = 0.008;
const double kAnchorTolerance = 0.012;

const int kFocusSettleMs = 150;
const int kMaxVerifyRetries = 2;