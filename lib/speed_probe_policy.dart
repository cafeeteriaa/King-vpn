import 'dart:math' as math;

/// Validation and unit conversion for real HTTP throughput probes.
/// A non-success HTTP page must never be ranked as downloaded tunnel traffic.
bool isUsableSpeedProbeResponse(int statusCode, String? contentType) {
  if (statusCode != 200 && statusCode != 206) return false;
  final mime = (contentType ?? '').split(';').first.trim().toLowerCase();
  // A captive portal often answers HTTP 200 with an HTML login/error page.
  if (mime == 'text/html' || mime == 'application/xhtml+xml' ||
      mime == 'application/json') {
    return false;
  }
  return true;
}

double? throughputMegabytesPerSecond({
  required int bytes,
  required int elapsedMilliseconds,
}) {
  if (bytes <= 0 || elapsedMilliseconds <= 0) return null;
  return bytes / 1048576 / (elapsedMilliseconds / 1000);
}

/// Continuous age decay keeps older measurements useful as history without
/// allowing yesterday's peak speed to outrank a recently measured route.
/// A 15-minute half-life is a ranking weight, not a candidate-removal cutoff.
double? ageAdjustedThroughput({
  required double? megabytesPerSecond,
  required DateTime? measuredAt,
  required DateTime now,
  Duration halfLife = const Duration(minutes: 15),
}) {
  if (megabytesPerSecond == null || megabytesPerSecond <= 0 || measuredAt == null) {
    return null;
  }
  final age = now.difference(measuredAt);
  if (age.isNegative || halfLife <= Duration.zero) return null;
  final halfLives = age.inMicroseconds / halfLife.inMicroseconds;
  return megabytesPerSecond * math.pow(0.5, halfLives).toDouble();
}
