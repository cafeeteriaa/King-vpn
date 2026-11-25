import 'dart:io';

import 'package:http/http.dart' as http;

/// Parse a public resolver inventory without imposing an address-count ceiling.
/// Every syntactically valid IPv4/IPv6 literal is retained, regardless of
/// address scope; reachability and DNS response validation happen in the
/// scanner, not in this discovery parser.
List<String> kingParsePublicDnsResolvers(String source) {
  final found = <String>{};
  for (final rawLine in source.split(RegExp(r'[\r\n]+'))) {
    final line = rawLine.split('#').first.trim();
    if (line.isEmpty) continue;
    for (var token in line.split(RegExp(r'[\s,;]+'))) {
      token = token.trim();
      if (token.startsWith('[') && token.endsWith(']')) {
        token = token.substring(1, token.length - 1);
      }
      final address = InternetAddress.tryParse(token);
      if (address == null) continue;
      if (address.type == InternetAddressType.IPv4 ||
          address.type == InternetAddressType.IPv6) {
        found.add(address.address);
      }
    }
  }
  return found.toList(growable: false);
}

/// Pull the current public recursive-resolver inventory from a live catalogue.
/// The catalogue is a discovery source, not an allowlist: saved, built-in and
/// user-supplied resolvers are merged separately and are never replaced by it.
/// A failed download is non-destructive; existing inventories remain usable.
Future<List<String>> kingDiscoverPublicDnsResolvers() async {
  try {
    final response = await http
        .get(
          Uri.https('public-dns.info', '/nameservers.txt'),
          headers: const {'Accept': 'text/plain'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok) return const <String>[];
    return kingParsePublicDnsResolvers(response.body);
  } catch (_) {
    // Discovery is best-effort; never erase or block previously known sources.
    return const <String>[];
  }
}
