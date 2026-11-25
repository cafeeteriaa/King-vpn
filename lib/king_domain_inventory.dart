import 'dart:io';

/// Normalize domain inventories without mistaking IP literals for hostnames.
///
/// Scanner inventories may contain DNS names, `domain:` rules and `full:`
/// rules from independent sources. IPv4 relay addresses are useful endpoint
/// data, but are not DNS names and must not leak into hostname probe queues.
List<String> kingNormalizeDomainHosts(Iterable<String> source) {
  final seen = <String>{};
  final result = <String>[];
  final labelPattern = RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$');

  for (final raw in source) {
    var host = raw.trim().toLowerCase();
    if (host.startsWith('domain:')) {
      host = host.substring('domain:'.length);
    } else if (host.startsWith('full:')) {
      host = host.substring('full:'.length);
    }
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    if (host.isEmpty || host.length > 253 || !host.contains('.')) continue;
    if (InternetAddress.tryParse(host) != null) continue;

    final labels = host.split('.');
    if (labels.any((label) =>
        label.isEmpty || label.length > 63 || !labelPattern.hasMatch(label))) {
      continue;
    }
    if (seen.add(host)) result.add(host);
  }
  return result;
}
