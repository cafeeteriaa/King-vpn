/// Keeps domestic resolvers first while applying the Secure DNS preference
/// to both Xray's string and DnsServerObject server representations.
///
/// Xray supports routed DoH (https://), local-mode DoH (https+local://),
/// and local-mode DoQ (quic+local://). All three are encrypted transports
/// and must respect the same opt-out.
bool _isEncryptedDnsAddress(String address) {
  final normalized = address.trim().toLowerCase();
  return normalized.startsWith('https://') ||
      normalized.startsWith('https+local://') ||
      normalized.startsWith('quic+local://');
}

List<dynamic> mergeNationalDnsServers({
  required List<dynamic> domesticFirst,
  required List<dynamic> existing,
  required bool secureDns,
}) {
  final merged = <dynamic>[];
  final seenDns = <String>{};
  for (final item in [...domesticFirst, ...existing]) {
    final value = item.toString().trim();
    if (value.isEmpty) continue;
    final address =
        item is Map ? item['address']?.toString().trim() ?? '' : value;
    if (!secureDns && _isEncryptedDnsAddress(address)) continue;
    if (seenDns.add(value.toLowerCase())) merged.add(item);
  }
  return merged;
}
