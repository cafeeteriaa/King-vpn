import 'dart:convert';

// conn_specs.dart
// مشخصات کانفیگ برای گزارش خطا + توضیح کدهای جدید.
// بدون وابستگی به main.dart (برای جلوگیری از import دوری).

String maskSecret(String s) {
  if (s.isEmpty) return '-';
  if (s.length <= 6) return '***';
  return '${s.substring(0, 4)}…${s.substring(s.length - 2)}';
}

String _s(Object? v) {
  final t = v?.toString() ?? '';
  return t.isEmpty || t == 'null' ? '-' : t;
}

String _dec(String s) {
  var t = s.replaceAll('-', '+').replaceAll('_', '/').trim();
  while (t.length % 4 != 0) {
    t += '=';
  }
  return utf8.decode(base64.decode(t));
}

class ConfigSpec {
  String protocol = '-', host = '-', port = '-', network = '-';
  String security = '-', sni = '-', fingerprint = '-', flow = '-';
  String path = '-', hostHeader = '-', alpn = '-', encryption = '-';
  String user = '-', name = '-';

  String toLine() {
    final parts = <String, String>{
      'پروتکل': protocol,
      'آدرس': host,
      'پورت': port,
      'شبکه(network)': network,
      'امنیت': security,
      'SNI': sni,
      'fingerprint': fingerprint,
      'flow': flow,
      'مسیر(path)': path,
      'Host': hostHeader,
      'ALPN': alpn,
      'رمزنگاری': encryption,
      'کاربر': user,
      'نام': name,
    };
    return parts.entries
        .where((e) => e.value != '-')
        .map((e) => '${e.key}: ${e.value}')
        .join(' • ');
  }
}

// لینک (vless/vmess/trojan/ss/hy2/tuic/...) یا متن OpenVPN را می‌خواند
ConfigSpec describeConfig(String link, {String? ovpnText}) {
  final c = ConfigSpec();
  try {
    if (ovpnText != null && ovpnText.trim().isNotEmpty) {
      c.protocol = 'OpenVPN';
      for (final raw in ovpnText.split('\n')) {
        final p = raw.trim().split(RegExp(r'\s+'));
        if (p.isEmpty) continue;
        if (p[0] == 'remote' && p.length >= 2) {
          c.host = p[1];
          if (p.length >= 3) c.port = p[2];
        } else if (p[0] == 'proto' && p.length >= 2) {
          c.network = p[1];
        } else if (p[0] == 'cipher' && p.length >= 2) {
          c.encryption = p[1];
        }
      }
      return c;
    }

    final i = link.indexOf('://');
    if (i <= 0) return c;
    final scheme = link.substring(0, i).toLowerCase();
    c.protocol = scheme == 'hy2' ? 'hysteria2' : scheme;

    final hashAt = link.indexOf('#');
    if (hashAt >= 0) {
      c.name = Uri.decodeComponent(link.substring(hashAt + 1));
    }
    final body = hashAt >= 0 ? link.substring(0, hashAt) : link;
    final rest = body.substring(i + 3);

    if (scheme == 'vmess') {
      final q = rest.indexOf('?');
      final j = jsonDecode(_dec(q >= 0 ? rest.substring(0, q) : rest)) as Map;
      c.name = _s(j['ps']);
      c.host = _s(j['add']);
      c.port = _s(j['port']);
      c.network = _s(j['net']);
      c.security = _s(j['tls']);
      c.sni = _s(j['sni']);
      c.fingerprint = _s(j['fp']);
      c.path = _s(j['path']);
      c.hostHeader = _s(j['host']);
      c.alpn = _s(j['alpn']);
      c.encryption = _s(j['scy']);
      c.user = maskSecret(_s(j['id']));
      return c;
    }

    if (scheme == 'ss') {
      var b = rest;
      final q = b.indexOf('?');
      if (q >= 0) b = b.substring(0, q);
      if (!b.contains('@')) b = _dec(b);
      final at = b.lastIndexOf('@');
      final info = b.substring(0, at);
      final method = info.contains(':') ? info : _dec(info);
      final colon = method.indexOf(':');
      c.encryption = colon > 0 ? method.substring(0, colon) : method;
      c.user = maskSecret(colon > 0 ? method.substring(colon + 1) : '');
      final hp = b.substring(at + 1);
      final pc = hp.lastIndexOf(':');
      c.host = pc > 0 ? hp.substring(0, pc) : hp;
      c.port = pc > 0 ? hp.substring(pc + 1) : '-';
      return c;
    }

    // vless / trojan / hysteria2 / tuic / socks / ...
    final u = Uri.parse(body);
    final qp = u.queryParameters;
    final ui = u.userInfo;
    c.host = _s(u.host);
    c.port = u.hasPort ? '${u.port}' : '-';
    c.user = maskSecret(ui.split(':').first);
    c.network = _s(qp['type'] ??
        (scheme.startsWith('hy') || scheme == 'tuic' ? 'quic' : null));
    c.security =
        _s(qp['security'] ?? (scheme == 'trojan' ? 'tls' : null));
    c.sni = _s(qp['sni'] ?? qp['peer']);
    c.fingerprint = _s(qp['fp']);
    c.flow = _s(qp['flow']);
    c.path = _s(qp['path'] ?? qp['serviceName']);
    c.hostHeader = _s(qp['host']);
    c.alpn = _s(qp['alpn']);
    c.encryption = _s(qp['encryption']);
  } catch (_) {
    // کانفیگ عجیب: هرچه خوانده شد برمی‌گردد
  }
  return c;
}

// خط گزارش برای یک کانفیگ شکست‌خورده
String configFailMsg(String link, String stage, String reason,
    {String? ovpnText}) {
  final spec = describeConfig(link, ovpnText: ovpnText);
  final r = reason.trim().isEmpty ? '-' : reason.trim();
  return 'کانفیگ ناموفق [E-CONFIG-FAIL] • مرحله: $stage • علت: $r • '
      '${spec.toLine()}';
}

// توضیح کدهای جدید برای گزارش: [کد, محل, علت, راه‌حل] یا null
List<String>? extraDiagOf(String m) {
  if (m.contains('[E-CONFIG-FAIL]')) {
    return [
      'E-CONFIG-FAIL',
      'app_main/main.dart → _connectLoop (شکست _start یا پینگ از تونل)',
      'این کانفیگ مشخصاً وصل نشد. «مرحله» نشان می‌دهد کجا شکست خورد و «علت» دلیلش است. بقیه‌ی خط (پروتکل، آدرس، پورت، شبکه، امنیت، SNI) مشخصات همان کانفیگ است.',
      'اگر چند کانفیگ با یک پروتکل/شبکه/پورت پشت‌سرهم شکست خوردند، همان گروه را بررسی کن (مثلاً همه ws روی 443). اگر همه‌ی کانفیگ‌ها شکست می‌خورند، مشکل از هسته یا اینترنت است نه کانفیگ.',
    ];
  }
  if (m.contains('تست سریع دوباره')) {
    return [
      'E-NO-HEALTHY-RETRY',
      'app_main/main.dart → _acquire (حلقه‌ی RETRYPATCH)',
      'هیچ سرور سالمی در صف نبود و برنامه دوباره جستجو می‌کند. هر دور با تأخیر بیشتر (تا ۱۵ ثانیه) انجام می‌شود.',
      'اگر «تست سریع X/Y» نزدیک صفر است delayTimeout را بیشتر کن یا fastDelay را خاموش کن و منبع‌های مرده را حذف کن.',
    ];
  }
  if (m.contains('تست پینگ تمام شد')) {
    return [
      'E-INFO-PING-DONE',
      'app_main/main.dart → تست پینگ صف',
      'خبر عادی: تست پینگ تمام شد و اتصال قطع نشد. خطا نیست.',
      'نیازی به اقدام نیست.',
    ];
  }
  return null;
}
