import 'dart:convert';
import 'dart:io';

// conn_specs.dart
// مشخصات کامل کانفیگ برای گزارش خطا + راهنمای رفع.

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
  String pbk = '-', sid = '-', spx = '-', mode = '-';
  String serviceName = '-', allowInsecure = '-', packetEncoding = '-';
  String resolvedIp = '-';
  String extra = '-';

  /// یک خط فشرده (سازگار با گزارش قدیمی)
  String toLine() {
    final parts = <String, String>{
      'پروتکل': protocol,
      'آدرس': host,
      'IP': resolvedIp,
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
      'pbk': pbk,
      'sid': sid,
      'spx': spx,
      'mode': mode,
      'serviceName': serviceName,
      'allowInsecure': allowInsecure,
      'packetEncoding': packetEncoding,
      'کاربر': user,
      'نام': name,
      'اضافی': extra,
    };
    return parts.entries
        .where((e) => e.value != '-')
        .map((e) => '${e.key}: ${e.value}')
        .join(' • ');
  }

  /// گزارش چندخطی کامل برای عیب‌یابی
  String toFullBlock() {
    final b = StringBuffer();
    void line(String k, String v) {
      if (v != '-') b.writeln('   · $k: $v');
    }

    line('پروتکل', protocol);
    line('نام', name);
    line('آدرس (host)', host);
    line('IP (حل‌شده)', resolvedIp);
    line('پورت', port);
    line('شبکه / transport', network);
    line('امنیت (tls/reality/none)', security);
    line('SNI', sni);
    line('fingerprint', fingerprint);
    line('ALPN', alpn);
    line('flow', flow);
    line('path', path);
    line('Host header', hostHeader);
    line('serviceName (gRPC)', serviceName);
    line('mode', mode);
    line('رمزنگاری', encryption);
    line('publicKey (pbk)', pbk);
    line('shortId (sid)', sid);
    line('spiderX (spx)', spx);
    line('allowInsecure', allowInsecure);
    line('packetEncoding', packetEncoding);
    line('کاربر/UUID (ماسک)', user);
    line('اضافی', extra);
    return b.toString();
  }
}

ConfigSpec describeConfig(String link, {String? ovpnText, String? knownIp}) {
  final c = ConfigSpec();
  if (knownIp != null && knownIp.isNotEmpty) c.resolvedIp = knownIp;
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
      try {
        c.name = Uri.decodeComponent(link.substring(hashAt + 1));
      } catch (_) {
        c.name = link.substring(hashAt + 1);
      }
    }
    final body = hashAt >= 0 ? link.substring(0, hashAt) : link;
    final rest = body.substring(i + 3);

    if (scheme == 'vmess') {
      final q = rest.indexOf('?');
      final j = jsonDecode(_dec(q >= 0 ? rest.substring(0, q) : rest)) as Map;
      c.name = _s(j['ps']).isEmpty || _s(j['ps']) == '-' ? c.name : _s(j['ps']);
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
      final aid = j['aid'];
      if (aid != null) c.extra = 'aid=$aid';
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
    c.path = _s(qp['path']);
    c.serviceName = _s(qp['serviceName']);
    c.hostHeader = _s(qp['host']);
    c.alpn = _s(qp['alpn']);
    c.encryption = _s(qp['encryption']);
    c.pbk = _s(qp['pbk']);
    c.sid = _s(qp['sid']);
    c.spx = _s(qp['spx']);
    c.mode = _s(qp['mode']);
    c.allowInsecure = _s(qp['allowInsecure'] ?? qp['insecure']);
    c.packetEncoding = _s(qp['packetEncoding']);
    final extras = <String>[];
    for (final k in [
      'headerType',
      'authority',
      'seed',
      'eh',
      'ed',
      'encryption',
      'quicSecurity',
      'key'
    ]) {
      final v = qp[k];
      if (v != null && v.isNotEmpty) extras.add('$k=$v');
    }
    if (extras.isNotEmpty) c.extra = extras.join(', ');
  } catch (_) {}
  return c;
}

// try resolve host → IP (best-effort, short timeout)
Future<String> resolveHostIp(String host) async {
  if (host.isEmpty || host == '-') return '-';
  if (InternetAddress.tryParse(host) != null) return host;
  try {
    final r = await InternetAddress.lookup(host)
        .timeout(const Duration(seconds: 3));
    if (r.isEmpty) return '-';
    return r.map((e) => e.address).join(',');
  } catch (_) {
    return '-';
  }
}

String _configFixHint(ConfigSpec s, String stage, String reason) {
  final st = stage.toLowerCase();
  final rs = reason.toLowerCase();
  final hints = <String>[];

  if (st.contains('هسته') || st.contains('_start') || rs.contains('connected')) {
    hints.add(
        'هسته JSON را نپذیرفت یا در CONNECTING ماند: لینک را در کلاینت دیگری تست کن؛ path/SNI/fp را با منبع کانفیگ مقایسه کن.');
  }
  if (rs.contains('پینگ') || st.contains('پینگ')) {
    hints.add(
        'تونل بالا آمد ولی ترافیک رد نشد: SNI/Host با دامنه واقعی یکی باشد؛ روی نت ملی Fragment یا DNS ایرانی را امتحان کن.');
  }
  if (s.path.contains('proxyip=')) {
    hints.add(
        'path شامل proxyip= است — این فرمت بعضی پنل‌هاست و هسته استاندارد ممکن است رد کند؛ لینک تمیز بدون proxyip بگیر.');
  }
  if (s.network == 'ws' && s.security == 'tls' && s.sni == '-') {
    hints.add('WS+TLS بدون SNI ضعیف است؛ SNI را برابر دامنه CDN بگذار.');
  }
  if (s.security == 'reality' && (s.pbk == '-' || s.sid == '-')) {
    hints.add('Reality بدون pbk/sid معمولاً کار نمی‌کند؛ کانفیگ ناقص است.');
  }
  if (s.network == 'grpc' && s.serviceName == '-') {
    hints.add('gRPC بدون serviceName اغلب شکست می‌خورد.');
  }
  if (s.port == '80' && s.security == 'tls') {
    hints.add('پورت ۸۰ با TLS غیرمعمول است؛ منبع کانفیگ را چک کن.');
  }
  if (hints.isEmpty) {
    hints.add(
        'اگر چند کانفیگ هم‌نوع پشت‌سرهم شکست خوردند همان گروه (مثلاً همه ws:443) را موقتاً رد کن؛ اگر همه شکست خوردند مشکل از اینترنت/هسته است نه یک کانفیگ.');
  }
  return hints.join(' ');
}

/// خط گزارش کامل برای یک کانفیگ شکست‌خورده
String configFailMsg(String link, String stage, String reason,
    {String? ovpnText, String? knownIp}) {
  final spec = describeConfig(link, ovpnText: ovpnText, knownIp: knownIp);
  final r = reason.trim().isEmpty ? '-' : reason.trim();
  final fix = _configFixHint(spec, stage, r);
  final b = StringBuffer();
  b.writeln('کانفیگ ناموفق [E-CONFIG-FAIL]');
  b.writeln('• مرحله: $stage');
  b.writeln('• علت: $r');
  b.write(spec.toFullBlock());
  b.writeln('• خلاصه: ${spec.toLine()}');
  b.write('• 🛠 راه حل: $fix');
  return b.toString().trimRight();
}

// توضیح کدهای جدید برای گزارش: [کد, محل, علت, راه‌حل] یا null
List<String>? extraDiagOf(String m) {
  bool has(String x) => m.toLowerCase().contains(x.toLowerCase());
  if (has('E-CONFIG-FAIL') || has('کانفیگ ناموفق')) {
    return [
      'E-CONFIG-FAIL',
      'app_main/main.dart → _connectLoop / _start',
      'این کانفیگ مشخصاً وصل نشد. مرحله و علت و مشخصات کامل (پروتکل/آدرس/IP/پورت/شبکه/SNI/…) در همان پیام آمده.',
      'مشخصات را با منبع کانفیگ مقایسه کن. اگر path شامل proxyip= است لینک استاندارد بگیر. چند شکست هم‌نوع = رد موقت آن گروه.',
    ];
  }
  if (has('هیچ سایتی باز نشد') || has('سایت‌چک')) {
    return [
      'E-SITE-CLOSED',
      'app_main/main.dart → _connectLoop (SITEPRECHECK)',
      'پینگ از تونل آمد ولی چک ترافیک واقعی (204 / سرعت) رد شد یا سایت‌های تست فیلتر بودند.',
      'نسخه جدید اگر سرعت واقعی > 0 باشد سرور را نگه می‌دارد. اگر باز هم رد شد سرور بعدی را امتحان کن؛ روی نت ملی حالت ملی را بزن.',
    ];
  }
  if (has('پینگ از تونل') && (has('رد نشد') || has('بد'))) {
    return [
      'E-TUN-PING',
      'app_main/main.dart → _connectLoop / pingAny',
      'هسته CONNECTED شد ولی پینگ از داخل تونل جواب نداد یا خیلی بد بود.',
      'ماتریس حالت / DNS / Fragment را برای همان سرور بالا ببر؛ یا سرور را موقتاً لیست‌سیاه کن.',
    ];
  }
  return null;
}

