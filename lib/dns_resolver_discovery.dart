import 'dart:io';

import 'package:http/http.dart' as http;

/// Parse plain-text and CSV resolver inventories without imposing an
/// address-count ceiling. Every valid IPv4/IPv6 literal is retained,
/// irrespective of scope; reachability is tested by the DNS scanner.
List<String> kingParsePublicDnsResolvers(String source) {
  final found = <String>{};
  for (final rawLine in source.split(RegExp(r'[\\r\\n]+'))) {
    final line = rawLine.split('#').first.trim();
    if (line.isEmpty) continue;
    for (var token in line.split(RegExp(r'[\\s,;]+'))) {
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

/// Merge independent public resolver catalogues. No source is an allowlist:
/// built-in, saved and user-entered addresses are merged by the caller.
/// Failure of one feed never prevents the others or erases prior inventory.
Future<List<String>> kingDiscoverPublicDnsResolvers() async {
  const sources = <String>[
    'https://public-dns.info/nameservers.txt',
    'https://public-dns.info/nameservers.csv',
    'https://raw.githubusercontent.com/blacklanternsecurity/public-dns-servers/master/nameservers.txt',
  ];
  final client = http.Client();
  try {
    final results = await Future.wait(sources.map((source) async {
      try {
        final response = await client
            .get(Uri.parse(source), headers: const {'Accept': 'text/plain,text/csv'})
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != HttpStatus.ok) return const <String>[];
        return kingParsePublicDnsResolvers(response.body);
      } catch (_) {
        return const <String>[];
      }
    }));
    return results.expand((items) => items).toSet().toList(growable: false);
  } finally {
    client.close();
  }
}
