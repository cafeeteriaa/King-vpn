import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'king_domain_inventory.dart';

/// Extract the hostname column from one Majestic Million CSV row.
/// The feed is an expandable discovery source, not an application allowlist.
String? kingMajesticDomainFromCsvLine(String line) {
  final fields = line.split(',');
  if (fields.length < 3) return null;
  final host = fields[2].trim();
  if (host.isEmpty || host.toLowerCase() == 'domain') return null;
  final normalized = kingNormalizeDomainHosts([host]);
  return normalized.isEmpty ? null : normalized.first;
}

/// Load every domain in the current public global-domain feed.
/// The upstream publishes a daily one-million-domain dataset (~80 MB); the
/// application imposes no row/count ceiling and merges it with all local,
/// user, SNI and learned inventories. A 24-hour cache respects the provider's
/// daily update cadence and avoids repeatedly downloading the full dataset.
/// On network failure the last complete cache is preserved and returned.
Future<List<String>> kingDiscoverGlobalDnsDomains() async {
  File? temporary;
  final client = http.Client();
  Future<List<String>> readCache() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}/king_dns_global_domains.csv');
      if (!await file.exists()) return const <String>[];
      final hosts = <String>{};
      await for (final line in file.openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final normalized = kingNormalizeDomainHosts([line]);
        if (normalized.isNotEmpty) hosts.add(normalized.first);
      }
      return hosts.toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  try {
    final directory = await getApplicationSupportDirectory();
    final cache = File('${directory.path}/king_dns_global_domains.csv');
    if (await cache.exists()) {
      final age = DateTime.now().difference(await cache.lastModified());
      if (age < const Duration(hours: 24)) return await readCache();
    }

    final tempFile = File('${cache.path}.download');
    temporary = tempFile;
    if (await tempFile.exists()) await tempFile.delete();
    final request = http.Request(
      'GET',
      Uri.https('downloads.majestic.com', '/majestic_million.csv'),
    )..headers['Accept'] = 'text/csv';
    final response = await client.send(request)
        .timeout(const Duration(seconds: 90));
    if (response.statusCode != HttpStatus.ok) {
      return await readCache();
    }

    final hosts = <String>{};
    final sink = tempFile.openWrite();
    try {
      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final host = kingMajesticDomainFromCsvLine(line);
        if (host == null) continue;
        if (hosts.add(host)) sink.writeln(host);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (hosts.isEmpty) {
      await tempFile.delete();
      return await readCache();
    }
    // Rename only after a complete, non-empty feed; old cache survives errors.
    await tempFile.rename(cache.path);
    temporary = null;
    return hosts.toList(growable: false);
  } catch (_) {
    return await readCache();
  } finally {
    if (temporary != null) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {}
    }
    client.close();
  }
}
