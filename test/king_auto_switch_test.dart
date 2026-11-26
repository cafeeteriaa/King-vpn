import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/king_auto_switch.dart';
import 'package:king_vpn/king_engine_sources.dart';
import 'package:king_vpn/king_network_engines.dart';
import 'package:king_vpn/king_proxy_sources.dart';

class FakeAdapter implements KingConnectionAdapter {
  FakeAdapter(this.id, {this.available = true, this.startOk = true,
    this.trafficOk = true, this.events, this.disconnectError});
  @override
  final String id;
  @override
  final bool available;
  final bool startOk;
  bool trafficOk;
  final List<String>? events;
  Object? disconnectError;
  @override
  Future<KingEngineConnectResult> connect() async {
    events?.add('connect:$id');
    return KingEngineConnectResult(started: startOk, trafficVerified: trafficOk);
  }
  @override
  Future<bool> verifyTraffic() async => trafficOk;
  @override
  Future<void> disconnect() async {
    events?.add('disconnect:$id');
    if (disconnectError != null) throw disconnectError!;
  }
}

class BlockingAdapter implements KingConnectionAdapter {
  BlockingAdapter(this.delegate, this.started);
  final FakeAdapter delegate;
  final Completer<KingEngineConnectResult> started;
  @override
  String get id => delegate.id;
  @override
  bool get available => delegate.available;
  int _connectCalls = 0;
  @override
  Future<KingEngineConnectResult> connect() =>
      _connectCalls++ == 0 ? started.future : delegate.connect();
  @override
  Future<bool> verifyTraffic() => delegate.verifyTraffic();
  @override
  Future<void> disconnect() => delegate.disconnect();
}

void main() {
  group('KING multi-engine coordinator', () {
    test('Xray stays primary and falls back only after data-plane failure', () async {
      final events = <String>[];
      final result = await KingAutoSwitchCoordinator(adapters: [
        FakeAdapter(KingEngineId.amneziaWg, events: events),
        FakeAdapter(KingEngineId.xray, trafficOk: false, events: events),
      ]).connect();
      expect(result.connected, isTrue);
      expect(result.engine, KingEngineId.amneziaWg);
      expect(events, [
        'connect:xray', 'disconnect:xray', 'connect:amneziawg',
      ]);
    });

    test('does not start unavailable engines', () async {
      final events = <String>[];
      final result = await KingAutoSwitchCoordinator(adapters: [
        FakeAdapter(KingEngineId.xray, available: false, events: events),
        FakeAdapter(KingEngineId.wireGuard, events: events),
      ]).connect();
      expect(result.engine, KingEngineId.wireGuard);
      expect(events, ['connect:wireguard']);
    });

    test('user disconnect cancels a late engine startup', () async {
      final started = Completer<KingEngineConnectResult>();
      final events = <String>[];
      final blocking = BlockingAdapter(FakeAdapter(KingEngineId.xray, events: events), started);
      final coordinator = KingAutoSwitchCoordinator(adapters: [blocking]);
      final pending = coordinator.connect();
      await Future<void>.delayed(Duration.zero);
      await coordinator.disconnect();
      expect(events, ['disconnect:xray']);
      started.complete(const KingEngineConnectResult(started: true, trafficVerified: true));
      final result = await pending;
      expect(result.connected, isFalse);
      expect(result.engine, isNull);
      expect(events, ['disconnect:xray', 'disconnect:xray']);
    });

    test('waits for cancelled startup teardown before reconnecting', () async {
      final started = Completer<KingEngineConnectResult>();
      final events = <String>[];
      final coordinator = KingAutoSwitchCoordinator(adapters: [
        BlockingAdapter(FakeAdapter(KingEngineId.xray, events: events), started),
      ]);
      final first = coordinator.connect();
      await Future<void>.delayed(Duration.zero);
      await coordinator.disconnect();
      final second = coordinator.connect();
      started.complete(const KingEngineConnectResult(started: true, trafficVerified: true));
      expect((await first).connected, isFalse);
      final reconnected = await second;
      expect(reconnected.engine, KingEngineId.xray);
      expect(events, ['disconnect:xray', 'disconnect:xray', 'connect:xray']);
    });

    test('rejects duplicate adapter identifiers', () {
      expect(() => KingAutoSwitchCoordinator(adapters: [
        FakeAdapter(KingEngineId.xray), FakeAdapter(KingEngineId.xray),
      ]), throwsArgumentError);
    });


    test('never treats local DPI modules as independent VPN owners', () async {
      final events = <String>[];
      final result = await KingAutoSwitchCoordinator(adapters: [
        FakeAdapter(KingEngineId.shroudly, events: events),
        FakeAdapter(KingEngineId.byeDpi, events: events),
        FakeAdapter(KingEngineId.powerTunnel, events: events),
        FakeAdapter(KingEngineId.xray, events: events),
      ]).connect();
      expect(result.engine, KingEngineId.xray);
      expect(events, ['connect:xray']);
    });

    test('halts failover when previous engine cannot confirm TUN teardown', () async {
      final events = <String>[];
      final result = await KingAutoSwitchCoordinator(adapters: [
        FakeAdapter(KingEngineId.xray, trafficOk: false,
            events: events, disconnectError: StateError('TUN still owned')),
        FakeAdapter(KingEngineId.wireGuard, events: events),
      ]).connect();
      expect(result.connected, isFalse);
      expect(result.engine, isNull);
      expect(result.detail, contains('teardown failed'));
      expect(events, ['connect:xray', 'disconnect:xray']);
    });

    test('does not accept CONNECTED without data-plane proof', () async {
      final result = await KingAutoSwitchCoordinator(adapters: [
        FakeAdapter(KingEngineId.xray, trafficOk: false),
      ]).connect();
      expect(result.connected, isFalse);
      expect(result.engine, isNull);
    });


    test('recovery halts if active VPN owner cannot release TUN', () async {
      final events = <String>[];
      final xray = FakeAdapter(KingEngineId.xray, events: events);
      final wireGuard = FakeAdapter(KingEngineId.wireGuard, events: events);
      final coordinator = KingAutoSwitchCoordinator(adapters: [xray, wireGuard]);
      expect((await coordinator.connect()).engine, KingEngineId.xray);
      xray.trafficOk = false;
      xray.disconnectError = StateError('release not confirmed');
      final result = await coordinator.recoverFromTrafficFailure();
      expect(result.connected, isFalse);
      expect(result.engine, isNull);
      expect(result.detail, contains('recovery halted'));
      expect(events, ['connect:xray', 'disconnect:xray']);
    });

    test('recovers from failed active engine to next healthy engine', () async {
      final xray = FakeAdapter(KingEngineId.xray, trafficOk: false);
      final wg = FakeAdapter(KingEngineId.wireGuard);
      final coordinator = KingAutoSwitchCoordinator(adapters: [xray, wg]);
      final initial = await coordinator.connect();
      expect(initial.engine, KingEngineId.wireGuard);
      xray.trafficOk = true;
      wg.trafficOk = false;
      final recovered = await coordinator.recoverFromTrafficFailure();
      expect(recovered.engine, KingEngineId.xray);
      expect(recovered.connected, isTrue);
    });
  });

  group('Selected engine catalog', () {
    test('contains the baseline engines and all requested technologies', () {
      final catalog = KingNetworkEngineCatalog();
      expect(catalog.all.map((e) => e.id), containsAll({
        KingEngineId.xray, KingEngineId.hysteria2, KingEngineId.singBox,
        KingEngineId.nthLink, KingEngineId.shroudly, KingEngineId.byeDpi,
        KingEngineId.powerTunnel, KingEngineId.amneziaWg, KingEngineId.openVpn,
        KingEngineId.shadowsocks, KingEngineId.openConnect, KingEngineId.wireGuard,
      }));
      expect(catalog[KingEngineId.xray]?.state, KingIntegrationState.integrated);
      expect(catalog[KingEngineId.wireGuard]?.state,
          KingIntegrationState.integrationPathVerified);
      expect(catalog.all.where((e) => e.state == KingIntegrationState.integrated)
          .map((e) => e.id), [KingEngineId.xray]);
    });

    test('keeps local DPI tools separate from full-device VPN engines', () {
      final catalog = KingNetworkEngineCatalog();
      for (final id in [KingEngineId.shroudly, KingEngineId.byeDpi, KingEngineId.powerTunnel]) {
        expect(catalog[id]?.role, KingEngineRole.localTransport);
      }
      for (final id in [KingEngineId.hysteria2, KingEngineId.singBox,
        KingEngineId.amneziaWg, KingEngineId.openVpn, KingEngineId.shadowsocks,
        KingEngineId.openConnect, KingEngineId.wireGuard]) {
        expect(catalog[id]?.requiresSeparateVpnOwner, isTrue);
      }
    });

    test('allows future engines without an inventory ceiling', () {
      final catalog = KingNetworkEngineCatalog();
      catalog.register(const KingEngineDescriptor(
        id: 'future_engine', name: 'Future Engine',
        role: KingEngineRole.fullDeviceVpn,
        state: KingIntegrationState.sourceAndLicenseReviewRequired,
        priority: 200, summary: 'Dynamically registered adapter.',
      ));
      expect(catalog['future_engine']?.name, 'Future Engine');
    });
  });

  group('Protocol-aware server sources', () {
    test('retains fifty legacy feeds for Xray only', () {
      expect(KingEngineServerSourceCatalog.xrayFeeds(), hasLength(50));
      expect(KingProxySourceCatalog.forXray(), hasLength(50));
      expect(KingProxySourceCatalog.online.map((s) => s.url).toSet(), hasLength(50));
    });

    test('uses only sources that declare compatible formats for each engine', () {
      expect(KingEngineServerSourceCatalog.forEngine(KingEngineId.hysteria2), hasLength(4));
      expect(KingEngineServerSourceCatalog.forEngine(KingEngineId.singBox), hasLength(10));
      expect(KingEngineServerSourceCatalog.forEngine(KingEngineId.shadowsocks), hasLength(4));
      expect(KingEngineServerSourceCatalog.forEngine(KingEngineId.openVpn), isEmpty);
      expect(KingEngineServerSourceCatalog.forEngine(KingEngineId.amneziaWg), isEmpty);
      expect(KingEngineServerSourceCatalog.forEngine(KingEngineId.wireGuard), hasLength(1));
      expect(KingEngineServerSourceCatalog.forEngine(KingEngineId.openConnect), isEmpty);
    });

    test('exposes offline imports without limiting the number of imported profiles', () {
      expect(KingEngineServerSourceCatalog.offline, containsAll([
        KingOfflineImportKind.androidDocumentPicker,
        KingOfflineImportKind.localFile,
        KingOfflineImportKind.clipboardText,
        KingOfflineImportKind.qrCode,
        KingOfflineImportKind.amneziaWgConf,
        KingOfflineImportKind.openVpnOvpn,
        KingOfflineImportKind.wireGuardConf,
        KingOfflineImportKind.openConnectUrl,
        KingOfflineImportKind.shadowsocksUri,
      ]));
    });

    test('identifies provider-managed and local-only engines', () {
      expect(KingEngineServerSourceCatalog.needsUserOrProviderServer(KingEngineId.nthLink), isTrue);
      expect(KingEngineServerSourceCatalog.isLocalOnly(KingEngineId.shroudly), isTrue);
      expect(KingEngineServerSourceCatalog.isLocalOnly(KingEngineId.byeDpi), isTrue);
      expect(KingEngineServerSourceCatalog.isLocalOnly(KingEngineId.powerTunnel), isTrue);
    });
  });

  group('Adaptive batches', () {
    test('processes the complete supplied iterable while changing batch size', () async {
      final seen = <int>[];
      final result = await KingAdaptiveBatchRunner.run<int, int>(
        items: List<int>.generate(75, (i) => i),
        initialBatchSize: 20,
        probe: (item) async { seen.add(item); return item * 2; },
        nextBatchSize: (previous, completed) => completed == 20 ? 30 : 25,
      );
      expect(seen, List<int>.generate(75, (i) => i));
      expect(result.map((item) => item.value).toList(), List<int>.generate(75, (i) => i * 2));
    });

    test('records failures and continues through the entire inventory', () async {
      final result = await KingAdaptiveBatchRunner.run<int, int>(
        items: List<int>.generate(45, (i) => i),
        initialBatchSize: 20,
        probe: (item) async { if (item == 7) throw StateError('probe failed'); return item; },
      );
      expect(result, hasLength(45));
      expect(result[7].succeeded, isFalse);
      expect(result.where((item) => item.succeeded), hasLength(44));
    });

    test('rejects an invalid batch size', () async {
      await expectLater(KingAdaptiveBatchRunner.run<int, int>(
        items: const [1], initialBatchSize: 0, probe: (item) async => item,
      ), throwsArgumentError);
    });
  });

  group('Server payload parser and refresh', () {
    final parser = KingServerPayloadParser();

    test('filters protocol-specific links and decodes Base64 feeds', () {
      final plain = parser.parse(
        engineId: KingEngineId.hysteria2,
        payload: 'hy2://token@example.org:443\\nvless://uuid@example.net:443',
      );
      expect(plain, hasLength(1));
      expect(plain.single.format, KingServerConfigFormat.hysteria2Uri);
      expect(parser.parse(engineId: KingEngineId.hysteria2,
          payload: '{"outbounds":[{"type":"hysteria2"}]}'), isEmpty);
      final encoded = base64Encode(utf8.encode('hysteria2://token@example.org:443'));
      expect(parser.parse(engineId: KingEngineId.hysteria2, payload: encoded), hasLength(1));
    });

    test('validates sing-box outbound endpoint fields instead of accepting type-only JSON', () {
      const invalid = '{"outbounds":[{"type":"hysteria2"}]}';
      const valid = '{"outbounds":[{"type":"hysteria2","server":"vpn.example.org","server_port":443}]}';
      expect(parser.parse(engineId: KingEngineId.singBox, payload: invalid), isEmpty);
      final parsed = parser.parse(engineId: KingEngineId.singBox, payload: valid);
      expect(parsed, hasLength(1));
      expect(parsed.single.format, KingServerConfigFormat.singBoxJson);
    });

    test('recognizes OpenVPN, WireGuard and AmneziaWG profile files', () {
      const ovpn = 'client\nproto udp\nremote vpn.example.org 1194\n';
      final privateKey = base64Encode(List<int>.filled(32, 7));
      final publicKey = base64Encode(List<int>.filled(32, 9));
      final wg = '[Interface]\nPrivateKey = $privateKey\n[Peer]\nPublicKey = $publicKey\nAllowedIPs = 0.0.0.0/0, ::/0\nEndpoint = vpn.example.org:51820\n';
      final awg = '[Interface]\nPrivateKey = $privateKey\nS4 = 20\n[Peer]\nPublicKey = $publicKey\nAllowedIPs = 0.0.0.0/0\nEndpoint = vpn.example.org:51820\n';
      expect(parser.parse(engineId: KingEngineId.openVpn, payload: ovpn).single.format,
          KingServerConfigFormat.openVpnProfile);
      expect(parser.parse(engineId: KingEngineId.wireGuard, payload: wg).single.format,
          KingServerConfigFormat.wireGuardConfig);
      expect(parser.parse(engineId: KingEngineId.amneziaWg, payload: awg).single.format,
          KingServerConfigFormat.amneziaWgConfig);
      expect(parser.parse(engineId: KingEngineId.wireGuard,
          payload: 'wireguard://private-key@example.org:51820').single.format,
          KingServerConfigFormat.wireGuardConfig);
      final reorderedIpv6 = '[Peer]\r\nEndpoint = [2001:db8::1]:51820\r\nAllowedIPs = ::/0, 192.0.2.0/24\r\nPublicKey = $publicKey\r\n[Interface]\r\nAddress = 10.0.0.2/32\r\nPrivateKey = $privateKey\r\n';
      expect(parser.parse(engineId: KingEngineId.wireGuard, payload: reorderedIpv6),
          hasLength(1));
    });

    test('rejects malformed WireGuard key material and invalid AllowedIPs', () {
      const invalidKey = '[Interface]\nPrivateKey = key\n[Peer]\nPublicKey = key\nAllowedIPs = 0.0.0.0/0\nEndpoint = vpn.example.org:51820\n';
      final privateKey = base64Encode(List<int>.filled(32, 7));
      final publicKey = base64Encode(List<int>.filled(32, 9));
      final invalidNetwork = '[Interface]\nPrivateKey = $privateKey\n[Peer]\nPublicKey = $publicKey\nAllowedIPs = 0.0.0.0/99\nEndpoint = vpn.example.org:51820\n';
      expect(parser.parse(engineId: KingEngineId.wireGuard, payload: invalidKey), isEmpty);
      expect(parser.parse(engineId: KingEngineId.wireGuard, payload: invalidNetwork), isEmpty);
    });

    test('recognizes OpenConnect endpoints and Shroudly upstream proxies', () {
      expect(parser.parse(engineId: KingEngineId.openConnect,
          payload: 'https://vpn.example.org').single.format,
          KingServerConfigFormat.openConnectEndpoint);
      expect(parser.parse(engineId: KingEngineId.shroudly,
          payload: 'socks5://user:pass@127.0.0.1:1080').single.format,
          KingServerConfigFormat.socksOrHttpProxy);
    });

    test('parses Hysteria 2 share links with auth, host and port', () {
      final profiles = parser.parse(
        engineId: KingEngineId.hysteria2,
        payload: 'hy2://token@example.org:443?sni=example.org',
        sourceId: 'fixture',
      );
      expect(profiles, hasLength(1));
      expect(profiles.single.format, KingServerConfigFormat.hysteria2Uri);
      expect(profiles.single.raw, 'hy2://token@example.org:443?sni=example.org');
      expect(
        parser.parse(engineId: KingEngineId.hysteria2,
            payload: 'hy2://token@example.org:443'),
        hasLength(1),
      );
      expect(
        KingEngineServerSourceCatalog.forEngine(KingEngineId.hysteria2),
        isNotEmpty,
      );
    });

    test('isolates failed sources and retains healthy Hysteria2 profiles', () async {
      final sync = KingServerSourceSync(fetchText: (url) async {
        if (url.toLowerCase().contains('10dream')) throw StateError('temporary outage');
        return 'hy2://token@example.org:443';
      });
      final result = await sync.refresh(KingEngineId.hysteria2);
      expect(result.profiles, hasLength(1), reason: result.failures.map((failure) => '${failure.sourceId}: ${failure.message}').join('\\n'));
      expect(result.failures, hasLength(1));
    });

    test('honors sub-hour publisher cadence without inventing unknown schedules', () {
      const fast = KingEngineServerSource(
        id: 'fast', name: 'Fast feed', url: 'https://example.org/feed',
        kind: KingServerSourceKind.publicSubscription,
        formats: {KingServerConfigFormat.hysteria2Uri},
        engineIds: {'hysteria2'}, updateCadence: '15m',
      );
      const hourly = KingEngineServerSource(
        id: 'hourly', name: 'Hourly feed', url: 'https://example.org/hourly',
        kind: KingServerSourceKind.publicSubscription,
        formats: {KingServerConfigFormat.hysteria2Uri},
        engineIds: {'hysteria2'}, updateCadence: 'hourly',
      );
      const unknown = KingEngineServerSource(
        id: 'unknown', name: 'Unknown feed', url: 'https://example.org/unknown',
        kind: KingServerSourceKind.publicSubscription,
        formats: {KingServerConfigFormat.hysteria2Uri},
        engineIds: {'hysteria2'},
      );
      expect(KingServerSourceRefreshScheduler.intervalForSource(fast),
          const Duration(minutes: 15));
      expect(KingServerSourceRefreshScheduler.intervalForSource(hourly),
          const Duration(hours: 1));
      expect(KingServerSourceRefreshScheduler.intervalForSource(unknown), isNull);
    });

    test('rejects cleartext feed URLs before making a network request', () async {
      final fetcher = KingHttpSourceFetcher();
      await expectLater(fetcher.fetch('http://example.org/feed'),
          throwsFormatException);
      fetcher.close(force: true);
    });

    test('coalesces concurrent refreshes for the same engine', () async {
      final gate = Completer<String>();
      var calls = 0;
      final sync = KingServerSourceSync(fetchText: (url) {
        calls++;
        return gate.future;
      });
      final scheduler = KingServerSourceRefreshScheduler(
        sync: sync,
        onResult: (_) async {},
      );
      final first = scheduler.refreshNow(KingEngineId.hysteria2);
      final second = scheduler.refreshNow(KingEngineId.hysteria2);
      expect(identical(first, second), isTrue);
      gate.complete('hy2://token@example.org:443');
      await first;
      expect(
        calls,
        KingEngineServerSourceCatalog.forEngine(KingEngineId.hysteria2).length,
      );
      scheduler.dispose();
    });
  });

}
