import 'dart:convert';

/// A relay candidate must have recent end-to-end tunnel proof. Core-delay or
/// TCP/TLS reachability alone is not sufficient evidence for a usable relay.
bool natIsFreshVerifiedRelay({
  required bool verified,
  required DateTime? verifiedAt,
  required DateTime now,
  required Duration maxAge,
}) {
  if (!verified || verifiedAt == null || maxAge <= Duration.zero) return false;
  final age = now.difference(verifiedAt);
  return !age.isNegative && age < maxAge;
}

const Set<String> _natRelayProxyProtocols = <String>{
  'vmess',
  'vless',
  'trojan',
  'shadowsocks',
};

Map? _natRelayProxyOutbound(Map<String, dynamic> config) {
  final outbounds = config['outbounds'];
  if (outbounds is! List) return null;
  for (final outbound in outbounds) {
    if (outbound is Map &&
        _natRelayProxyProtocols.contains(outbound['protocol'])) {
      return outbound;
    }
  }
  return null;
}

/// Build an Xray outbound chain: the exit proxy dials through the relay proxy.
/// The relay's own dialerProxy is removed to prevent an accidental nested loop.
/// Returns null for malformed or unsupported configurations.
String? natBuildRelayChainConfig(
  String exitConfig,
  String relayConfig, {
  bool keepInbounds = false,
}) {
  try {
    final decodedExit = jsonDecode(exitConfig);
    final decodedRelay = jsonDecode(relayConfig);
    if (decodedExit is! Map<String, dynamic> ||
        decodedRelay is! Map<String, dynamic>) {
      return null;
    }

    final exitOutbounds = decodedExit['outbounds'];
    if (exitOutbounds is! List) return null;
    final exitIndex = exitOutbounds.indexWhere((item) =>
        item is Map &&
        _natRelayProxyProtocols.contains(item['protocol']));
    if (exitIndex < 0) return null;

    final relayOutbound = _natRelayProxyOutbound(decodedRelay);
    if (relayOutbound == null) return null;

    final usedTags = <String>{
      for (final item in exitOutbounds)
        if (item is Map && item['tag'] != null) item['tag'].toString(),
    };
    var relayTag = 'relay-hop';
    var suffix = 2;
    while (usedTags.contains(relayTag)) {
      relayTag = 'relay-hop-$suffix';
      suffix++;
    }

    final relayHop = Map<String, dynamic>.from(relayOutbound)
      ..['tag'] = relayTag;
    final relayStream = relayHop['streamSettings'];
    if (relayStream is Map) {
      final clonedStream = Map<String, dynamic>.from(relayStream);
      final relaySockopt = clonedStream['sockopt'];
      if (relaySockopt is Map) {
        final clonedSockopt = Map<String, dynamic>.from(relaySockopt)
          ..remove('dialerProxy');
        clonedStream['sockopt'] = clonedSockopt;
      }
      relayHop['streamSettings'] = clonedStream;
    }

    final exitProxy = Map<String, dynamic>.from(exitOutbounds[exitIndex] as Map);
    final exitStream = exitProxy['streamSettings'] is Map
        ? Map<String, dynamic>.from(exitProxy['streamSettings'] as Map)
        : <String, dynamic>{};
    final exitSockopt = exitStream['sockopt'] is Map
        ? Map<String, dynamic>.from(exitStream['sockopt'] as Map)
        : <String, dynamic>{};
    exitSockopt['dialerProxy'] = relayTag;
    exitStream['sockopt'] = exitSockopt;
    exitProxy['streamSettings'] = exitStream;

    exitOutbounds[exitIndex] = exitProxy;
    exitOutbounds.add(relayHop);
    decodedExit['outbounds'] = exitOutbounds;
    if (!keepInbounds) decodedExit.remove('inbounds');
    return jsonEncode(decodedExit);
  } catch (_) {
    return null;
  }
}
