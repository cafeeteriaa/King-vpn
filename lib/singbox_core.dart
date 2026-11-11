// SINGBOX: رَپر Dart برای هسته sing-box (Hysteria2 / TUIC) از طریق کانال king/singbox
import 'dart:convert';

import 'package:flutter/services.dart';

const MethodChannel _singboxChannel = MethodChannel('king/singbox');

Future<bool> startSingbox(String config) async {
  try {
    return await _singboxChannel.invokeMethod<bool>('start', {'config': config}) ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> stopSingbox() async {
  try {
    await _singboxChannel.invokeMethod<bool>('stop');
  } catch (_) {}
}

Future<bool> isSingboxAlive() async {
  try {
    return await _singboxChannel.invokeMethod<bool>('alive') ?? false;
  } catch (_) {
    return false;
  }
}

/// کانفیگ JSON مخصوص sing-box را از لینک hysteria2:// / hy2:// / tuic:// می‌سازد.
/// برای هر لینک دیگری null برمی‌گرداند.
String? buildSingboxConfigFromLink(String link) {
  final l = link.trim();
  final lower = l.toLowerCase();
  final isHy2 = lower.startsWith('hysteria2://') || lower.startsWith('hy2://');
  final isTuic = lower.startsWith('tuic://');
  if (!isHy2 && !isTuic) return null;

  try {
    final u = Uri.parse(l);
    if (u.host.isEmpty || !u.hasPort) return null;
    final q = u.queryParameters;
    final sni = q['sni'] ?? q['peer'] ?? q['servername'] ?? '';
    final insecure = q['insecure'] == '1' ||
        q['insecure'] == 'true' ||
        q['allow_insecure'] == '1' ||
        q['allowInsecure'] == '1';
    final userInfo = Uri.decodeComponent(u.userInfo);

    Map<String, dynamic> tls(List<String> alpn) => <String, dynamic>{
          'enabled': true,
          'alpn': alpn,
          if (sni.isNotEmpty) 'server_name': sni,
          if (insecure) 'insecure': true,
        };

    final Map<String, dynamic> out;
    if (isHy2) {
      if (userInfo.isEmpty) return null;
      out = <String, dynamic>{
        'type': 'hysteria2',
        'tag': 'proxy',
        'server': u.host,
        'server_port': u.port,
        'password': userInfo,
        'tls': tls(const ['h3']),
      };
      final obfsPass = q['obfs-password'] ?? '';
      if (q['obfs'] == 'salamander' && obfsPass.isNotEmpty) {
        out['obfs'] = {'type': 'salamander', 'password': obfsPass};
      }
    } else {
      final parts = userInfo.split(':');
      final uuid = parts.first;
      final pass = parts.length > 1 ? parts.sublist(1).join(':') : '';
      if (uuid.isEmpty) return null;
      final alpn = (q['alpn'] ?? 'h3')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      out = <String, dynamic>{
        'type': 'tuic',
        'tag': 'proxy',
        'server': u.host,
        'server_port': u.port,
        'uuid': uuid,
        'password': pass,
        'congestion_control': q['congestion_control'] ?? 'bbr',
        'udp_relay_mode': q['udp_relay_mode'] ?? 'native',
        'tls': tls(alpn),
      };
    }

    final cfg = <String, dynamic>{
      'log': {'level': 'warn', 'timestamp': true},
      'dns': {
        'servers': [
          {'tag': 'remote', 'type': 'https', 'server': '1.1.1.1', 'detour': 'proxy'},
        ],
        'final': 'remote',
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
          'mtu': 1400,
          'auto_route': true,
        },
      ],
      'outbounds': [
        out,
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'auto_detect_interface': true,
        'final': 'proxy',
        'rules': [
          {'action': 'sniff'},
          {'protocol': 'dns', 'action': 'hijack-dns'},
        ],
      },
    };
    return jsonEncode(cfg);
  } catch (_) {
    return null;
  }
}
