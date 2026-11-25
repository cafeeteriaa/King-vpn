/// Strict validation for Cloudflare's /cdn-cgi/trace probe response.
///
/// A matching word in an error page is not proof of a working Cloudflare
/// endpoint. Require HTTP 200 and the expected plain-text trace fields.
bool isValidCloudflareTraceResponse(String response) {
  final normalized = response.toLowerCase();
  final separator = normalized.indexOf('\r\n\r\n');
  if (separator < 0) return false;

  final headers = normalized.substring(0, separator);
  final body = normalized.substring(separator + 4);
  final statusLine = headers.split('\r\n').first.trim();
  if (!RegExp(r'^http/1\.[01]\s+200(?:\s|$)').hasMatch(statusLine)) {
    return false;
  }

  final fields = <String, String>{};
  for (final line in body.split(RegExp(r'\r?\n'))) {
    final split = line.indexOf('=');
    if (split <= 0) continue;
    final key = line.substring(0, split).trim();
    final value = line.substring(split + 1).trim();
    if (key.isNotEmpty && value.isNotEmpty) fields[key] = value;
  }
  return (fields['fl']?.isNotEmpty ?? false) &&
      (fields['ip']?.isNotEmpty ?? false) &&
      (fields['ts']?.isNotEmpty ?? false);
}
