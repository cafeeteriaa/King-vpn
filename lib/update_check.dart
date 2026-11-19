part of 'main.dart';

// UPDATE CHECK + Remote heal flags ==========================================
const int appBuild = 3; // Fallback only; PackageInfo supplies the installed build number.
const String updateConfigUrl =
    'https://gist.githubusercontent.com/cafeeteriaa/0e04f5efe29b8101eb554c6e9a41d969/raw/update.json';

const MethodChannel _kingUpdateChannel = MethodChannel('king/update');
bool _updateChecked = false;
String? _pendingUpdateApkPath;
Map<String, dynamic> _remoteHeal = {};

extension UpdateCheck on _HomePageState {
  Future<int> _installedAppBuild() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber) ?? appBuild;
    } catch (_) {
      return appBuild;
    }
  }

  Future<void> checkForUpdate() async {
    if (_updateChecked) return;
    _updateChecked = true;
    try {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      final response = await http
          .get(Uri.parse(updateConfigUrl), headers: const {
            'Accept': 'application/json',
            'User-Agent': 'KingVPN-Updater/1.0',
          })
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        _updateChecked = false;
        return;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);

      final heal = map['heal'];
      if (heal is Map) {
        _remoteHeal = Map<String, dynamic>.from(heal);
        _applyRemoteHeal();
      }

      final latest = (map['latest'] as num?)?.toInt() ?? 0;
      final minBuild = (map['min'] as num?)?.toInt() ?? 0;
      var pageUrl = (map['url'] as String?)?.trim() ?? '';
      final apkUrl = (map['apk'] as String?)?.trim() ?? '';
      final expectedSha256 =
          (map['sha256'] as String?)?.trim().toLowerCase() ?? '';
      if (pageUrl.isEmpty) pageUrl = 'https://t.me/kingvpnn57';
      final message = (map['message'] as String?)?.trim() ?? '';
      final currentBuild = await _installedAppBuild();
      final force = currentBuild < minBuild;
      if (!force && currentBuild >= latest && _pendingUpdateApkPath == null) {
        return;
      }
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: !force,
        builder: (ctx) => PopScope(
          canPop: !force,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('🚀 آپدیت King VPN'),
              content: Text(
                message.isNotEmpty
                    ? message
                    : 'نسخه‌ی جدید آماده است.\n'
                        'Build $currentBuild → $latest\n'
                        'فایل قبل از بازشدن نصب‌کننده با SHA-256 بررسی می‌شود.',
              ),
              actions: [
                if (!force)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('بعداً'),
                  ),
                if (_pendingUpdateApkPath != null)
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _continuePendingUpdateInstall();
                    },
                    child: const Text('ادامه نصب'),
                  )
                else if (apkUrl.isNotEmpty)
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _downloadAndInstallApk(apkUrl, expectedSha256);
                    },
                    child: const Text('دانلود و نصب'),
                  ),
                FilledButton(
                  onPressed: () async {
                    final open = apkUrl.isNotEmpty ? apkUrl : pageUrl;
                    try {
                      await launchUrl(Uri.parse(open),
                          mode: LaunchMode.externalApplication);
                    } catch (error, stack) {
                      logError(error, stack);
                      await Clipboard.setData(ClipboardData(text: open));
                      _set('لینک آپدیت کپی شد');
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(apkUrl.isNotEmpty ? 'لینک APK' : 'دانلود'),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (error, stack) {
      _updateChecked = false;
      logError(error, stack);
    }
  }

  Future<void> _downloadAndInstallApk(
    String apkUrl,
    String sha256Expected,
  ) async {
    final uri = Uri.tryParse(apkUrl);
    if (uri == null || !isAllowedUpdateDownloadUri(uri)) {
      _set('❌ لینک آپدیت امن و معتبر نیست؛ دانلود متوقف شد');
      return;
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256Expected)) {
      _set('❌ هش SHA-256 در منبع آپدیت معتبر نیست؛ نصب لغو شد');
      return;
    }

    http.Client? client;
    File? file;
    try {
      _set('⬇ در حال دانلود نسخه‌ی جدید...');
      kingHealText.value = 'دانلود آپدیت...';
      final temporary = await getTemporaryDirectory();
      final updateDirectory = Directory('${temporary.path}/king_updates');
      await updateDirectory.create(recursive: true);
      file = File('${updateDirectory.path}/king-vpn-update.apk');

      client = http.Client();
      final request = http.Request('GET', uri)
        ..headers.addAll(const {
          'Accept': 'application/vnd.android.package-archive',
          'User-Agent': 'KingVPN-Updater/1.0',
        });
      final streamed = await client.send(request)
          .timeout(const Duration(minutes: 4));
      // The HTTP client follows redirects by default. Validate the final
      // response URI too, otherwise an allowed GitHub URL could redirect to
      // an untrusted host before the APK bytes are received.
      final finalUri = streamed.request?.url;
      if (finalUri == null || !isAllowedUpdateDownloadUri(finalUri)) {
        throw StateError('APK redirect destination is not an allowed HTTPS GitHub host');
      }
      if (streamed.statusCode != 200) {
        throw HttpException('APK download returned HTTP ${streamed.statusCode}');
      }

      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in streamed.stream.timeout(
          const Duration(seconds: 45),
        )) {
          received += chunk.length;
          if (received > 300 * 1024 * 1024) {
            throw StateError('APK exceeds the 300 MB safety limit');
          }
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
        client.close();
        client = null;
      }
      if (received == 0 || !await verifySha256File(file, sha256Expected)) {
        throw StateError('APK SHA-256 mismatch or empty download');
      }

      _pendingUpdateApkPath = file.path;
      _set('✅ فایل دریافت و اصالت آن تأیید شد؛ در حال بازکردن نصب‌کننده اندروید...');
      kingHealText.value = 'APK تأیید شد — نصب‌کننده اندروید';
      await _continuePendingUpdateInstall();
    } catch (error, stack) {
      logError(error, stack);
      _set('❌ دریافت یا بررسی آپدیت ناموفق بود؛ نصب انجام نشد');
      kingHealText.value = 'خطا در دریافت یا بررسی آپدیت';
      if (file != null) {
        try {
          if (await file.exists()) await file.delete();
        } catch (cleanupError, cleanupStack) {
          logError(cleanupError, cleanupStack);
        }
      }
    } finally {
      client?.close();
    }
  }

  Future<void> _continuePendingUpdateInstall() async {
    final path = _pendingUpdateApkPath;
    if (path == null) return;
    try {
      final result = await _kingUpdateChannel.invokeMethod<String>(
        'installApk',
        {'path': path},
      );
      if (result == 'permission_required') {
        _updateChecked = false;
        _set('برای نصب، اجازه «نصب برنامه‌های ناشناس» را برای King VPN فعال کن؛ بعد از برگشت، گزینه ادامه نصب را بزن.');
      } else if (result == 'installer_opened') {
        _set('نصب‌کننده اندروید باز شد؛ نصب نسخه جدید را تأیید کن.');
      } else {
        _set('وضعیت نصب آپدیت مشخص نیست؛ دوباره تلاش کن.');
      }
    } catch (error, stack) {
      logError(error, stack);
      _set('بازکردن نصب‌کننده اندروید ناموفق بود؛ فایل تأییدشده در حافظه موقت باقی ماند.');
    }
  }

  void _applyRemoteHeal() {
    try {
      if (_remoteHeal['turboForce'] == true) {
        turboSpeed = true;
        muxEnabled = true;
      }
      final muxConcurrency = (_remoteHeal['muxConc'] as num?)?.toInt();
      if (muxConcurrency != null && muxConcurrency >= 8) {
        muxConc = muxConcurrency.clamp(8, 32);
      }
      dbg('ترمیم از راه دور اعمال شد: $_remoteHeal');
    } catch (error, stack) {
      logError(error, stack);
    }
  }
}
