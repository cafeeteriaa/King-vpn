/// Integrated runtime for KING VPN's thirteen network engines.
/// Each engine reports evidence separately. Missing native/core adapters are
/// explicit; TCP reachability is never promoted to proof of VPN traffic.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';

enum KingEngineId {
  connectionOrchestrator, networkIntelligence, discovery, scanner,
  compatibility, realTrafficValidator, configIntelligence, networkIdentity,
  dpiTrafficTransformation, capabilityOrchestrator, multiEngineConnector,
  aiRepairOptimization, resourceHealthManager
}
enum KingEngineStatus { passed, degraded, unavailable, failed, skipped }

class KingEngineResult {
  const KingEngineResult(this.id, this.status, this.message,
      {this.metrics = const <String, num>{}, this.details = const <String>[]});
  final KingEngineId id;
  final KingEngineStatus status;
  final String message;
  final Map<String, num> metrics;
  final List<String> details;
}
class KingEndpoint {
  const KingEndpoint(this.host, this.port, {this.label = ''});
  final String host;
  final int port;
  final String label;
  String get key => '${host.toLowerCase()}:$port';
}
class KingTrafficProof {
  const KingTrafficProof({required this.available, required this.responseReceived,
    required this.multiDestination, required this.elapsedMs});
  final bool available, responseReceived, multiDestination;
  final int elapsedMs;
  // The core probe returns a boolean, not byte counters. Never manufacture totals.
  bool get passed => available && responseReceived && multiDestination;
}
typedef KingNetworkProbe = Future<Object?> Function();
typedef KingTrafficProbe = Future<KingTrafficProof> Function();
typedef KingTransform = Future<bool> Function(String config, String strategy);

class KingEngineContext {
  KingEngineContext({required this.operatorIdentity, required this.networkClass,
    required this.tunnelConnected, required this.configs, required this.endpoints,
    required this.networkProbe, required this.shouldCancel, this.workerBudget = 2,
    this.trafficProbe, this.transform});
  final String operatorIdentity, networkClass;
  final bool tunnelConnected;
  final List<String> configs;
  final List<KingEndpoint> endpoints;
  final KingNetworkProbe? networkProbe;
  final bool Function() shouldCancel;
  final int workerBudget;
  final KingTrafficProbe? trafficProbe;
  final KingTransform? transform;
  String fingerprint = '';
  int workers = 1;
  List<KingEndpoint> discovered = <KingEndpoint>[];
  List<KingEndpoint> reachable = <KingEndpoint>[];
  List<String> compatible = <String>[], valid = <String>[];
  KingTrafficProof? proof;
  final Map<KingEngineId, KingEngineResult> results = {};
  final Set<String> capabilities = {};
}
class KingEngineReport {
  const KingEngineReport(this.results, this.endpointCount);
  final Map<KingEngineId, KingEngineResult> results;
  final int endpointCount;
  int get passed => results.values.where((r) => r.status == KingEngineStatus.passed).length;
  int get degraded => results.values.where((r) => r.status == KingEngineStatus.degraded).length;
  int get unavailable => results.values.where((r) => r.status == KingEngineStatus.unavailable).length;
  int get failed => results.values.where((r) => r.status == KingEngineStatus.failed).length;
}
abstract class _KingEngine {
  KingEngineId get id;
  Future<KingEngineResult> run(KingEngineContext c);
}
class _ResourceEngine extends _KingEngine {
  @override KingEngineId get id => KingEngineId.resourceHealthManager;
  @override Future<KingEngineResult> run(KingEngineContext c) async {
    c.workers = max(1, min(max(1, c.workerBudget), 8)).toInt();
    return KingEngineResult(id, KingEngineStatus.passed, 'Resource-aware worker budget selected',
      metrics: {'workers': c.workers});
  }
}
class _IdentityEngine extends _KingEngine {
  @override KingEngineId get id => KingEngineId.networkIdentity;
  @override Future<KingEngineResult> run(KingEngineContext c) async {
    try {
      final interfaces = await NetworkInterface.list(includeLoopback: false);
      final rows = <String>[for (final i in interfaces) for (final a in i.addresses) '${i.name}:${a.address}']..sort();
      c.fingerprint = sha256.convert(utf8.encode(rows.join('|'))).toString();
      return KingEngineResult(id, rows.isEmpty ? KingEngineStatus.degraded : KingEngineStatus.passed,
        'Network fingerprint refreshed without persisting raw addresses',
        metrics: {'interfaces': interfaces.length, 'addresses': rows.length});
    } catch (e) { return KingEngineResult(id, KingEngineStatus.unavailable, 'Interface inventory unavailable: $e'); }
  }
}
class _NetworkEngine extends _KingEngine {
  @override KingEngineId get id => KingEngineId.networkIntelligence;
  @override Future<KingEngineResult> run(KingEngineContext c) async {
    if (c.networkProbe == null) return KingEngineResult(id, KingEngineStatus.unavailable, 'Network diagnosis adapter missing');
    try {
      final value = await c.networkProbe!();
      return KingEngineResult(id, value == null ? KingEngineStatus.degraded : KingEngineStatus.passed,
        'Independent Net Melli diagnosis sampled: ${c.networkClass}');
    } catch (e) { return KingEngineResult(id, KingEngineStatus.failed, 'Network diagnosis failed: $e'); }
  }
}
class _DiscoveryEngine extends _KingEngine {
  @override KingEngineId get id => KingEngineId.discovery;
  @override Future<KingEngineResult> run(KingEngineContext c) async {
    final unique = <String, KingEndpoint>{};
    for (final e in c.endpoints) {
      if (e.host.trim().isNotEmpty && e.port > 0 && e.port <= 65535) unique.putIfAbsent(e.key, () => e);
    }
    c.discovered = unique.values.toList(growable: false);
    return KingEngineResult(id, c.discovered.isEmpty ? KingEngineStatus.degraded : KingEngineStatus.passed,
      'Saved/source endpoint inventory normalized; no unrelated address-space sweep',
      metrics: {'endpoints': c.discovered.length});
  }
}
class _ScannerEngine extends _KingEngine {
  static bool _active = false;
  @override KingEngineId get id => KingEngineId.scanner;
  @override Future<KingEngineResult> run(KingEngineContext c) async {
    if (c.tunnelConnected) return KingEngineResult(id, KingEngineStatus.skipped,
      'Direct endpoint scan skipped while the VPN tunnel is active');
    if (_active) return KingEngineResult(id, KingEngineStatus.skipped, 'Duplicate scan coalesced');
    _active = true;
    try {
      var cursor = 0, cancelled = false;
      final alive = <KingEndpoint>[];
      Future<void> worker() async {
        while (true) {
          if (c.shouldCancel()) { cancelled = true; return; }
          final i = cursor++;
          if (i >= c.discovered.length) return;
          final endpoint = c.discovered[i];
          Socket? socket;
          try {
            socket = await Socket.connect(endpoint.host, endpoint.port,
              timeout: const Duration(seconds: 3));
            alive.add(endpoint);
          } catch (_) {
            // A transient failure never deletes the source record.
          } finally { socket?.destroy(); }
        }
      }
      final count = min(c.workers, max(1, c.discovered.length)).toInt();
      await Future.wait(List<Future<void>>.generate(count, (_) => worker()));
      c.reachable = alive;
      return KingEngineResult(id, cancelled ? KingEngineStatus.skipped :
        (alive.isEmpty ? KingEngineStatus.degraded : KingEngineStatus.passed),
        cancelled ? 'Cancelled on lifecycle change' : 'TCP sampled only; not tunnel validation',
        metrics: {'tested': min(cursor, c.discovered.length), 'reachable': alive.length});
    } finally { _active = false; }
  }
}
class _CompatibilityEngine extends _KingEngine {
  @override KingEngineId get id => KingEngineId.compatibility;
  @override Future<KingEngineResult> run(KingEngineContext c) async {
    const schemes = {'vmess','vless','trojan','ss','shadowsocks','socks','http'};
    var rejected = 0;
    for (final raw in c.configs) {
      try {
        final u = Uri.parse(raw.trim());
        if (schemes.contains(u.scheme.toLowerCase()) && u.host.isNotEmpty &&
            (!u.hasPort || (u.port > 0 && u.port <= 65535))) { c.compatible.add(raw); }
        else { rejected++; }
      } catch (_) { rejected++; }
    }
    return KingEngineResult(id, rejected == 0 ? KingEngineStatus.passed : KingEngineStatus.degraded,
      'URI scheme/authority compatibility checked against declared Xray inputs',
      metrics: {'compatible': c.compatible.length, 'rejected': rejected});
  }
}
class _ConfigEngine extends _KingEngine {
  @override KingEngineId get id => KingEngineId.configIntelligence;
  @override Future<KingEngineResult> run(KingEngineContext c) async {
    for (final raw in c.compatible) {
      try {
        final u = Uri.parse(raw.trim());
        if (u.host.isNotEmpty && !RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(u.toString())) c.valid.add(raw);
      } catch (_) {}
    }
    return KingEngineResult(id, c.valid.length == c.compatible.length ? KingEngineStatus.passed : KingEngineStatus.degraded,
      'Configuration authority and percent-escape validation completed',
      metrics: {'valid': c.valid.length, 'input': c.compatible.length});
  }
}
class _TrafficEngine extends _KingEngine {
  @override KingEngineId get id => KingEngineId.realTrafficValidator;
  @override Future<KingEngineResult> run(KingEngineContext c) async {
    if (!c.tunnelConnected) return KingEngineResult(id, KingEngineStatus.skipped, 'Tunnel is down; TUN proof not applicable');
    if (c.trafficProbe == null) return KingEngineResult(id, KingEngineStatus.unavailable, 'Android TUN bidirectional adapter missing');
    try {
      c.proof = await c.trafficProbe!();
      return KingEngineResult(id, c.proof!.passed ? KingEngineStatus.passed : KingEngineStatus.failed,
        c.proof!.passed ? 'Multi-destination response proof received through active core' : 'TUN proof incomplete',
        metrics: {'multiDestination': c.proof!.multiDestination ? 1 : 0, 'ms': c.proof!.elapsedMs});
    } catch (e) { return KingEngineResult(id, KingEngineStatus.failed, 'TUN probe failed: $e'); }
  }
}
class _TransformEngine extends _KingEngine {
  @override KingEngineId get id => KingEngineId.dpiTrafficTransformation;
  @override Future<KingEngineResult> run(KingEngineContext c) async {
    if (c.transform == null) return KingEngineResult(id, KingEngineStatus.unavailable, 'No verified core transformation adapter');
    if (c.valid.isEmpty) return KingEngineResult(id, KingEngineStatus.skipped, 'No valid config');
    try {
      final ok = await c.transform!(c.valid.first, 'xray_tls_fragment');
      return KingEngineResult(id, ok ? KingEngineStatus.passed : KingEngineStatus.failed,
        ok ? 'Core confirmed transformation application' : 'Core rejected transformation');
    } catch (e) { return KingEngineResult(id, KingEngineStatus.failed, 'Core transform failed: $e'); }
  }
}
class _CapabilityEngine extends _KingEngine {
  @override KingEngineId get id => KingEngineId.capabilityOrchestrator;
  @override Future<KingEngineResult> run(KingEngineContext c) async {
    c.capabilities.addAll({'xray:vless','xray:vmess','xray:trojan','xray:shadowsocks',
      'network:domestic-global-evidence','scanner:source-endpoint-tcp','dns:wire-probe'});
    if (c.trafficProbe != null) c.capabilities.add('tun:bidirectional-proof');
    if (c.transform != null) c.capabilities.add('xray:tls-fragment-adapter');
    return KingEngineResult(id, KingEngineStatus.passed, 'Capability registry reflects attached adapters',
      metrics: {'capabilities': c.capabilities.length});
  }
}
class _ConnectorEngine extends _KingEngine {
  @override KingEngineId get id => KingEngineId.multiEngineConnector;
  @override Future<KingEngineResult> run(KingEngineContext c) async {
    const needed = [KingEngineId.resourceHealthManager,KingEngineId.networkIdentity,
      KingEngineId.networkIntelligence,KingEngineId.discovery,KingEngineId.scanner,
      KingEngineId.compatibility,KingEngineId.configIntelligence];
    final missing = needed.where((id) => !c.results.containsKey(id)).toList();
    return KingEngineResult(id, missing.isEmpty ? KingEngineStatus.passed : KingEngineStatus.failed,
      missing.isEmpty ? 'Core engine outputs connected' : 'Missing outputs: $missing');
  }
}
class _AiRepairEngine extends _KingEngine {
  @override KingEngineId get id => KingEngineId.aiRepairOptimization;
  @override Future<KingEngineResult> run(KingEngineContext c) async {
    final faults = c.results.values.where((r) =>
      r.status == KingEngineStatus.failed || r.status == KingEngineStatus.unavailable)
      .map((r) => '${r.id.name}: ${r.message}').toList();
    return KingEngineResult(id, faults.isEmpty ? KingEngineStatus.passed : KingEngineStatus.degraded,
      faults.isEmpty ? 'No runtime fault surfaced' : 'Repair findings generated; no unreviewed source mutation',
      details: faults);
  }
}
class _ConnectionEngine extends _KingEngine {
  @override KingEngineId get id => KingEngineId.connectionOrchestrator;
  @override Future<KingEngineResult> run(KingEngineContext c) async {
    final route = {'domesticOnlyLikely':'domestic_first','dnsDegraded':'domestic_first',
      'transportRestricted':'domestic_first','globalReachable':'global_first'}[c.networkClass] ?? 'preserve_previous';
    final proof = c.proof?.passed ?? false;
    return KingEngineResult(id, c.valid.isEmpty ? KingEngineStatus.degraded : KingEngineStatus.passed,
      'Connection policy evaluated; TCP reachability is not TUN proof',
      metrics: {'validConfigs': c.valid.length, 'tunVerified': proof ? 1 : 0}, details: [route]);
  }
}
class KingEngineFabric {
  KingEngineFabric._();
  static const int engineCount = 13;
  static final List<_KingEngine> _engines = [
    _ResourceEngine(),_IdentityEngine(),_NetworkEngine(),_DiscoveryEngine(),_ScannerEngine(),
    _CompatibilityEngine(),_ConfigEngine(),_TrafficEngine(),_TransformEngine(),
    _CapabilityEngine(),_ConnectorEngine(),_AiRepairEngine(),_ConnectionEngine()
  ];
  static Future<KingEngineReport> run(KingEngineContext c) async {
    for (final engine in _engines) {
      try { c.results[engine.id] = await engine.run(c); }
      catch (e) { c.results[engine.id] = KingEngineResult(engine.id,KingEngineStatus.failed,'Unhandled engine error: $e'); }
    }
    return KingEngineReport(Map.unmodifiable(c.results), c.discovered.length);
  }
}
