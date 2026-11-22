/// Keeps domestic resolvers first while applying the Secure DNS preference
/// to both Xray's string and DnsServerObject server representations.
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
    final address = item is Map ? item['address']?.toString().trim() ?? '' : value;
    if (!secureDns && address.toLowerCase().startsWith('https://')) continue;
    if (seenDns.add(value.toLowerCase())) merged.add(item);
  }
  return merged;
}
