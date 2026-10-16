part of 'main.dart';

// NETDIAG ===================================================================
// «تشخیص شبکه»: بدون VPN و مستقیم روی همین اینترنت می‌سنجد چه چیزی باز است
// (TCP / DNS / TLS / سایت‌های ایرانی و خارجی / آینه‌های لیست) و می‌گوید
// کدام روش دور زدن به احتمال زیاد جواب می‌دهد.

// AUTONET: when on, the app measures the network itself before connecting and
// switches the bypass options (Fragment / IP+DoH / clean IP / secure DNS) to
// what this network needs, instead of only suggesting them.
bool autoNetOn = true;

Future<void> autoNetSave() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setBool('autonet_on', autoNetOn);
  } catch (e) {
    logError(e);
  }
}

class _NetVerdict {
  final bool tcp, tls, web, home, dnsPoison, dohOk, srcRaw, srcMir;
  final String op;
  final DateTime at;
  _NetVerdict(this.tcp, this.tls, this.web, this.home, this.dnsPoison,
      this.dohOk, this.srcRaw, this.srcMir, this.op)
      : at = DateTime.now();
}

_NetVerdict? lastNetVerdict;

class _DiagItem {
  final String label;
  final bool ok;
  final int ms;
  const _DiagItem(this.label, this.ok, this.ms);
}

Future<_DiagItem> _diagTcp(String label, String host, int port) async {
  final sw = Stopwatch()..start();
  Socket? s;
  try {
    s = await Socket.connect(host, port,
        timeout: const Duration(seconds: 4));
    return _DiagItem(label, true, sw.elapsedMilliseconds);
  } catch (e) {
    logError(e);
    return _DiagItem(label, false, sw.elapsedMilliseconds);
  } finally {
    s?.destroy();
  }
}

Future<_DiagItem> _diagHttp(String label, String url) async {
  final sw = Stopwatch()..start();
  final c = HttpClient()
    ..findProxy = ((_) => 'DIRECT')
    ..connectionTimeout = const Duration(seconds: 4);
  try {
    final req =
        await c.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 5));
    final res = await req.close().timeout(const Duration(seconds: 5));
    await res.drain<void>().timeout(const Duration(seconds: 5));
    return _DiagItem(label, res.statusCode > 0, sw.elapsedMilliseconds);
  } catch (e) {
    logError(e);
    return _DiagItem(label, false, sw.elapsedMilliseconds);
  } finally {
    c.close(force: true);
  }
}

// plain TLS handshake straight to an IP with an SNI of our choice
Future<_DiagItem> _diagTls(String label, String ip, String sni) async {
  final sw = Stopwatch()..start();
  SecureSocket? k;
  Socket? raw;
  try {
    raw = await Socket.connect(ip, 443, timeout: const Duration(seconds: 4));
    k = await SecureSocket.secure(raw,
            host: sni, onBadCertificate: (_) => true)
        .timeout(const Duration(seconds: 5));
    return _DiagItem(label, true, sw.elapsedMilliseconds);
  } catch (e) {
    logError(e);
    return _DiagItem(label, false, sw.elapsedMilliseconds);
  } finally {
    k?.destroy();
    raw?.destroy();
  }
}

Future<String> netDiagnose() async {
  final b = StringBuffer();
  String line(_DiagItem x) =>
      '${x.ok ? '✅' : '❌'} ${x.label}${x.ok ? ' (${x.ms}ms)' : ''}\n';

  final r = await Future.wait<_DiagItem>([
    // 0..4 TCP to well-known foreign IPs
    _diagTcp('TCP 1.1.1.1:443', '1.1.1.1', 443),
    _diagTcp('TCP 8.8.8.8:443', '8.8.8.8', 443),
    _diagTcp('TCP 9.9.9.9:443', '9.9.9.9', 443),
    _diagTcp('TCP تلگرام 149.154.167.50:443', '149.154.167.50', 443),
    _diagTcp('TCP 104.16.0.1:443 (Cloudflare)', '104.16.0.1', 443),
    // 5..8 TLS with different SNI (SNI filtering test)
    _diagTls('TLS 1.1.1.1 با SNI=cloudflare-dns.com', '1.1.1.1',
        'cloudflare-dns.com'),
    _diagTls('TLS 1.1.1.1 با SNI=www.google.com', '1.1.1.1', 'www.google.com'),
    _diagTls('TLS 1.1.1.1 با SNI=www.speedtest.net', '1.1.1.1',
        'www.speedtest.net'),
    _diagTls('TLS 104.16.0.1 با SNI=www.cloudflare.com', '104.16.0.1',
        'www.cloudflare.com'),
    // 9..13 foreign sites
    _diagHttp('gstatic (generate_204)', 'https://www.gstatic.com/generate_204'),
    _diagHttp('Cloudflare', 'https://cp.cloudflare.com/generate_204'),
    _diagHttp('Google', 'https://www.google.com/generate_204'),
    _diagHttp('Apple', 'https://www.apple.com/library/test/success.html'),
    _diagHttp('Telegram', 'https://web.telegram.org/'),
    // 14..17 list sources
    _diagHttp('GitHub raw', 'https://raw.githubusercontent.com/'),
    _diagHttp('jsDelivr', 'https://cdn.jsdelivr.net/'),
    _diagHttp('GitHack', 'https://raw.githack.com/'),
    _diagHttp('ghproxy', 'https://ghproxy.net/'),
    // 18..20 national network
    _diagHttp('آپارات', 'https://www.aparat.com/'),
    _diagHttp('دیجی‌کالا', 'https://www.digikala.com/'),
    _diagHttp('دیوار', 'https://divar.ir/'),
  ]);

  // DNS: system resolver vs DNS-over-HTTPS
  String dnsSys = '';
  bool dnsPoison = false;
  try {
    final l = await InternetAddress.lookup('www.google.com')
        .timeout(const Duration(seconds: 4));
    if (l.isNotEmpty) {
      dnsSys = l.first.address;
      dnsPoison = l.any((a) => _privateIp(a)) || dnsSys.startsWith('10.');
    }
  } catch (e) { logError(e); }
  final dnsDoh = await dohResolve('www.google.com');

  void sec(String t, int a, int z) {
    b.writeln(t);
    for (var i = a; i <= z; i++) {
      b.write(line(r[i]));
    }
    b.writeln();
  }

  b.writeln('نوع شبکه: ${await _natNetType()}  |  اپراتور: $natOpKey\n');
  sec('— اتصال TCP به IP های خارجی —', 0, 4);
  sec('— TLS با SNI های مختلف (تست فیلتر SNI) —', 5, 8);
  sec('— سایت‌های خارجی —', 9, 13);
  sec('— منابع لیست سرور —', 14, 17);
  sec('— شبکه ملی —', 18, 20);
  b.writeln('— DNS —');
  b.writeln(dnsSys.isEmpty
      ? '❌ DNS سیستم جواب نداد'
      : '${dnsPoison ? '⚠️' : '✅'} DNS سیستم: $dnsSys');
  b.writeln(dnsDoh == null
      ? '❌ DNS-over-HTTPS باز نیست'
      : '✅ DNS-over-HTTPS: $dnsDoh');
  if (dnsSys.isNotEmpty && dnsDoh != null && dnsSys != dnsDoh) {
    b.writeln('ℹ️ جواب DNS سیستم با DoH فرق دارد (ممکن است دستکاری شده باشد)');
  }
  b.writeln();

  bool any(int a, int z) {
    for (var i = a; i <= z; i++) {
      if (r[i].ok) return true;
    }
    return false;
  }

  final tcp = any(0, 4);
  final tls = any(5, 8);
  final web = any(9, 13);
  final srcRaw = r[14].ok;
  final srcMir = any(15, 17);
  final home = any(18, 20);

  lastNetVerdict = _NetVerdict(
      tcp, tls, web, home, dnsPoison, dnsDoh != null, srcRaw, srcMir, natOpKey);

  b.writeln('— نتیجه و پیشنهاد —');
  if (!tcp && !web && home) {
    b.writeln('🔴 اینترنت بین‌الملل قطع است و فقط نت ملی کار می‌کند.\n'
        '• «جستجوی سرور با نت ملی» یا «اتصال با سرورهای پوشه» را بزن.\n'
        '• فقط سرورهایی جواب می‌دهند که IP شان داخل ایران یا روی لیست سفید باشد.');
  } else if (!tcp && !web && !home) {
    b.writeln('⚫ هیچ اینترنتی نیست (نه ملی نه جهانی). شبکه یا سیم‌کارت را بررسی کن.');
  } else if (tcp && !tls) {
    b.writeln('🟠 TCP باز است ولی TLS بسته می‌شود: فیلتر SNI / DPI.\n'
        '• حالت‌های Fragment، Reality و fingerprint در جستجوی نت ملی این را دور می‌زنند.');
  } else if (tls && !web) {
    b.writeln('🟠 TLS مستقیم باز است ولی سایت‌ها نه: احتمالاً دامنه‌ها فیلتر شده‌اند.\n'
        '• اتصال با IP (DoH) و IP تمیز Cloudflare کمک می‌کند.');
  } else if (web) {
    b.writeln('🟢 اینترنت بین‌الملل در دسترس است. جستجوی عادی کافی است.');
  }
  if (dnsPoison) {
    b.writeln('⚠️ DNS دستکاری شده است؛ «اتصال با IP (DoH)» را روشن نگه دار.');
  }
  if (!srcRaw && srcMir) {
    b.writeln('ℹ️ GitHub raw بسته است ولی آینه‌ها باز هستند؛ لیست‌ها از آینه گرفته می‌شوند.');
  } else if (!srcRaw && !srcMir) {
    b.writeln('ℹ️ هیچ منبع لیستی باز نیست؛ فقط سرورهای ذخیره‌شده / پوشه کار می‌کنند.');
  }
  return b.toString();
}

extension NetDiagExt on _HomePageState {
  // applies what the measurement says this network needs; returns the list
  // of changes (empty = nothing to change). Options are only turned ON when
  // the network needs them; Fragment is also turned off when it is not needed.
  List<String> autoNetApply(_NetVerdict v) {
    final ch = <String>[];
    if (v.tcp) {
      final wantFrag = !v.tls;
      if (fragEnabled != wantFrag) {
        fragEnabled = wantFrag;
        ch.add(wantFrag
            ? 'Fragment روشن شد (فیلتر SNI/DPI)'
            : 'Fragment خاموش شد (لازم نیست)');
      }
    }
    final needDns = v.dnsPoison || (v.tcp && !v.tls) || (v.tls && !v.web);
    if (needDns && !ipMode) {
      ipMode = true;
      ch.add('اتصال با IP (DoH) روشن شد');
    }
    if (needDns && !secureDns) {
      secureDns = true;
      ch.add('DNS امن روشن شد');
    }
    final needClean = (v.tcp && !v.tls) || (v.tls && !v.web);
    if (needClean && !cleanIpMode) {
      cleanIpMode = true;
      ch.add('IP تمیز روشن شد');
    }
    return ch;
  }

  // called before every connect: measures the network (at most once per 10
  // minutes per operator) and sets the best modes by itself
  Future<void> autoNetPrep() async {
    if (!autoNetOn || connected) return;
    final old = lastNetVerdict;
    if (old != null &&
        old.op == natOpKey &&
        DateTime.now().difference(old.at) < const Duration(minutes: 10)) {
      return;
    }
    _set('تشخیص خودکار شبکه...');
    try {
      await netDiagnose().timeout(const Duration(seconds: 20));
    } catch (e) {
      logError(e);
      return;
    }
    final v = lastNetVerdict;
    if (v == null) return;
    final ch = autoNetApply(v);
    if (ch.isNotEmpty) {
      await _saveSettings();
      if (mounted) setState(() {});
      _set('حالت شبکه خودکار: ${ch.join('، ')}');
    }
  }

  Future<void> netDiagDialog() async {
    if (!mounted) return;
    if (connected) {
      _set('برای تشخیص درست، اول VPN را قطع کن');
      return;
    }
    final out = ValueNotifier<String>('در حال تست... (حدود ۱۰ ثانیه)');
    unawaited(netDiagnose().then((t) async {
      var res = t;
      final v = lastNetVerdict;
      if (autoNetOn && v != null) {
        final ch = autoNetApply(v);
        if (ch.isNotEmpty) {
          final lines = ch.map((e) => '• $e').join('\n');
          res = '$t\n🤖 تنظیم خودکار انجام شد:\n$lines';
          await _saveSettings();
          if (mounted) setState(() {});
        } else {
          res = '$t\n🤖 حالت شبکه خودکار است و تنظیمات فعلی با این شبکه جور است؛ چیزی عوض نشد.';
        }
      }
      out.value = res;
    }).catchError((e) {
      out.value = 'خطا: $e';
    }));
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تشخیص شبکه'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: ValueListenableBuilder<String>(
                valueListenable: out,
                builder: (_, v, __) => SelectableText(v),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: out.value));
                },
                child: const Text('کپی')),
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
          ],
        ),
      ),
    );
  }
}
