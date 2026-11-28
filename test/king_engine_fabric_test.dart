import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/king_engine_fabric.dart';

void main() {
  test('fabric executes all thirteen engines and never invents TUN proof', () async {
    final context = KingEngineContext(
      operatorIdentity: 'test-operator',
      networkClass: 'unknown',
      tunnelConnected: true,
      configs: const ['vless://id@example.com:443?security=tls'],
      endpoints: const [],
      networkProbe: () async => 'unknown',
      shouldCancel: () => false,
    );
    final report = await KingEngineFabric.run(context);
    expect(report.results.length, KingEngineFabric.engineCount);
    expect(report.results[KingEngineId.realTrafficValidator]!.status,
        KingEngineStatus.unavailable);
    expect(report.results[KingEngineId.dpiTrafficTransformation]!.status,
        KingEngineStatus.unavailable);
  });

  test('TUN validation requires bidirectional bytes and a response', () async {
    final ok = KingTrafficProof(available: true, bytesIn: 100, bytesOut: 40,
      responseReceived: true, elapsedMs: 120);
    final oneWay = KingTrafficProof(available: true, bytesIn: 100, bytesOut: 0,
      responseReceived: true, elapsedMs: 120);
    expect(ok.passed, isTrue);
    expect(oneWay.passed, isFalse);
  });

  test('scanner checks only supplied endpoints and preserves source inventory', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final context = KingEngineContext(
      operatorIdentity: 'test', networkClass: 'unknown', tunnelConnected: false,
      configs: const [], endpoints: [KingEndpoint('127.0.0.1', server.port)],
      networkProbe: () async => null, shouldCancel: () => false, workerBudget: 1,
    );
    final report = await KingEngineFabric.run(context);
    expect(report.endpointCount, 1);
    expect(context.reachable.length, 1);
    await server.close();
  });

  test('invalid and unsupported config schemes are not admitted', () async {
    final context = KingEngineContext(
      operatorIdentity: 'test', networkClass: 'unknown', tunnelConnected: false,
      configs: const ['file:///tmp/x', 'vless://id@example.com:443'],
      endpoints: const [], networkProbe: () async => true, shouldCancel: () => false,
    );
    final report = await KingEngineFabric.run(context);
    expect(report.results[KingEngineId.compatibility]!.metrics['compatible'], 1);
    expect(report.results[KingEngineId.configIntelligence]!.metrics['valid'], 1);
  });
}
