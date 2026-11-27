/// Validates the complete versioned Android background-channel contract.
///
/// A successful method-channel round trip alone is insufficient: the channel
/// must belong to this package, its Flutter engine must still be attached, and
/// every capability consumed by Dart must be advertised by the native handler.
bool bgBridgeInfoMatches(
  Map<String, dynamic>? info, {
  required int expectedProtocolVersion,
  required String expectedPackageName,
}) {
  if (info == null || expectedPackageName.trim().isEmpty) return false;
  final sdk = info['androidSdk'];
  return info['protocolVersion'] == expectedProtocolVersion &&
      info['channel'] == 'vpn/bg' &&
      info['packageName'] == expectedPackageName &&
      info['engineAttached'] == true &&
      info['vpnSettings'] == true &&
      info['back'] == true &&
      info['alive'] == true &&
      sdk is int &&
      sdk > 0;
}
