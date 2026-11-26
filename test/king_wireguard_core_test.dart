import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/king_wireguard_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('king/wireguard');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('WireGuard bridge sends native profile to independent core channel', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, Object?>{
        'connected': true,
        'version': 'test-wireguard-go',
        'core': 'wireguard',
      };
    });

    const profile = '[Interface]\nPrivateKey = test\nAddress = 10.0.0.2/32\n'
        '[Peer]\nPublicKey = test\nEndpoint = 192.0.2.1:51820\n';
    final result = await KingWireGuardCore().connect(profile);

    expect(result['core'], 'wireguard');
    expect(calls.single.method, 'connect');
    expect((calls.single.arguments as Map)['config'], profile);
  });

  test('WireGuard bridge rejects non-WireGuard input before native call', () async {
    var invoked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      invoked = true;
      return <String, Object?>{'connected': true};
    });

    expect(
      () => KingWireGuardCore().connect('vless://example'),
      throwsFormatException,
    );
    expect(invoked, isFalse);
  });

  test('WireGuard disconnect and status use their own channel methods', () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'status') return <String, Object?>{'state': 'UP'};
      return true;
    });

    final core = KingWireGuardCore();
    await core.disconnect();
    expect(await core.status(), 'UP');
    expect(methods, <String>['disconnect', 'status']);
  });
}
