/// Validation and unit conversion for real HTTP throughput probes.
/// A non-success HTTP page must never be ranked as downloaded tunnel traffic.
bool isUsableSpeedProbeStatus(int statusCode) =>
    statusCode == 200 || statusCode == 206;

double? throughputMegabytesPerSecond({
  required int bytes,
  required int elapsedMilliseconds,
}) {
  if (bytes <= 0 || elapsedMilliseconds <= 0) return null;
  return bytes / 1048576 / (elapsedMilliseconds / 1000);
}
