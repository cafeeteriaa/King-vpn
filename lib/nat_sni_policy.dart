import 'dart:convert';

const Set<String> _natTlsProxyProtocols = <String>{
  'vmess',
  'vless',
  'trojan',
  'shadowsocks',
};

/// Applies an SNI override only to the first actual proxy outbound.
///
/// Auxiliary TLS outbounds (for example, a separate relay hop) must retain
/// their own hostname. ECH configurations are left untouched, and certificate
/// validation is kept enabled for every rewritten TLS proxy.
String natSetPrimaryProxyTlsServerName(String config, String serverName) {
  final name = serverName.trim();
  if (name.isEmpty) return config;
  try {
    final decoded = jsonDecode(config);
    if (decoded is! Map<String, dynamic>) return config;
    final outbounds = decoded['outbounds'];
    if (outbounds is! List) return config;

    for (final outbound in outbounds) {
      if (outbound is! Map ||
          !_natTlsProxyProtocols.contains(outbound['protocol'])) {
        continue;
      }
      final stream = outbound['streamSettings'];
      if (stream is! Map || stream['security'] != 'tls') return config;
      final tls = stream['tlsSettings'];
      if (tls is! Map) return config;
      if ((tls['echConfigList'] ?? '').toString().isNotEmpty) return config;

      tls['serverName'] = name;
      tls.remove('allowInsecure');
      return jsonEncode(decoded);
    }
    return config;
  } catch (_) {
    return config;
  }
}
