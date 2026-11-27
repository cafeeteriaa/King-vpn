/// Keeps domestic resolvers first in national mode while applying the Secure DNS
/// preference to both Xray's string and DnsServerObject representations.
///
/// Xray evaluates DNS servers sequentially by default. Global Secure DNS must
/// therefore place DoH before plaintext fallback servers; national mode keeps
/// domestic resolvers first for reachability, then uses bounded DoH fallback.
bool _isEncryptedDnsAddress(String address) {
  final normalized = address.trim().toLowerCase();
  return normalized.startsWith('https://') ||
      normalized.startsWith('https+local://') ||
      normalized.startsWith('quic+local://');
}

String _dnsAddress(dynamic item) =>
    item is Map ? item['address']?.toString().trim() ?? '' : item.toString().trim();

List<dynamic> _mergeUniqueDnsEntries(Iterable<dynamic> entries) {
  final merged = <dynamic>[];
  final seenDns = <String>{};
  for (final item in entries) {
    final value = item.toString().trim();
    if (value.isEmpty) continue;
    if (seenDns.add(value.toLowerCase())) merged.add(item);
  }
  return merged;
}

/// Returns true when DNS queries must be serialized to prevent parallel
/// requests from racing plaintext fallback resolvers against encrypted DNS.
bool shouldApplyGlobalSecureDns({
  required bool secureDns,
  required bool ultraMode,
}) =>
    secureDns && !ultraMode;

bool shouldSerializeDnsQueries({
  required bool secureDns,
  required bool nationalMode,
  required bool ultraMode,
}) =>
    secureDns && (nationalMode || !ultraMode);

/// Orders encrypted resolvers before plaintext fallback resolvers.
List<dynamic> mergeGlobalDnsServers({
  required List<dynamic> encryptedFirst,
  required List<dynamic> plaintextFallback,
}) =>
    _mergeUniqueDnsEntries([...encryptedFirst, ...plaintextFallback]);

List<dynamic> mergeNationalDnsServers({
  required List<dynamic> domesticFirst,
  required List<dynamic> existing,
  required bool secureDns,
  List<dynamic> secureFallback = const <dynamic>[],
}) {
  final merged = <dynamic>[];
  final seenDns = <String>{};
  final candidates = <dynamic>[
    ...domesticFirst,
    if (secureDns) ...secureFallback,
    ...existing,
  ];
  for (final item in candidates) {
    final value = item.toString().trim();
    if (value.isEmpty) continue;
    final address = _dnsAddress(item);
    if (!secureDns && _isEncryptedDnsAddress(address)) continue;
    if (seenDns.add(value.toLowerCase())) merged.add(item);
  }
  return merged;
}
