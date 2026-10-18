import 'dart:async';

// Stand-ins for the OpenVPN and WireGuard plugins. Those two plugins are removed
// from the build: they bring extra native VPN code that conflicts with V2Ray on
// the phone. The app keeps compiling and these two engines simply cannot start
// (their rows report "not connected"). V2Ray is the only engine that connects.

class OpenVPN {
  OpenVPN({this.onVpnStageChanged, this.onVpnStatusChanged});

  final void Function(dynamic stage, String raw)? onVpnStageChanged;
  final void Function(dynamic status)? onVpnStatusChanged;

  Future<void> initialize({
    String? localizedDescription,
    String? providerBundleIdentifier,
    String? groupIdentifier,
    List<String>? allowedApps,
    List<String>? notificationIcons,
  }) async {}

  Future<bool> requestPermissionAndroid() async => false;

  Future<void> connect(
    String config,
    String name, {
    bool certIsRequired = false,
    String? username,
    String? password,
    List<String>? bypassPackages,
  }) async {
    throw UnsupportedError('OpenVPN engine removed from this build');
  }

  void disconnect() {
    onVpnStageChanged?.call('disconnected', 'disconnected');
  }
}

class WireGuardFlutter {
  WireGuardFlutter._();

  static final WireGuardFlutter instance = WireGuardFlutter._();

  Future<void> initialize({required String interfaceName}) async {}

  Future<void> startVpn({
    required String serverAddress,
    required String wgQuickConfig,
    required String providerBundleIdentifier,
  }) async {
    throw UnsupportedError('WireGuard engine removed from this build');
  }

  Future<void> stopVpn() async {}
}
