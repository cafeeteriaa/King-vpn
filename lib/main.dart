import 'dart:async';
import 'package:flutter/foundation.dart' show compute;
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:http/http.dart' as http;
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'tg_proxy.dart';
import 'vpn_sources.dart';
import 'help_page.dart';
import 'conn_specs.dart';
part 'iran_ai_extras.dart';
part 'npv_am_extras.dart';
part 'nat_ultra.dart';
part 'net_diag.dart';
part 'extras_plus.dart';
part 'donate.dart';
part 'ads_remote.dart';
part 'king_heal.dart';
part 'update_check.dart';
part 'online.dart';
part 'server_shop.dart';
part 'telegram_channels.dart';
part 'ultimate_extras.dart';
part 'auto_test.dart';

// One rewarded ad = one 4 hour session. When the 4 hours end the VPN is cut
// and the next connect shows the ad again. Automatic server switches (bad
// ping / low speed / dead server) never show an ad and never end the session.
// Ad gate = the in-app AdPage (no AdMob). Set requireRewardedAd to false to remove it.
bool requireRewardedAd = true;
const sessionLength = Duration(hours: 4);

// package name of this app (org com.kingvpn + project king_vpn). It is never
// excluded from the VPN, because the app tests the tunnel itself.
const ownPkg = 'com.kingvpn.king_vpn';
// native channel: the back button only minimizes the app while the VPN is on
// (so the standby search keeps running). Needs the MainActivity patch from
// the workflow file.
const bgChannel = MethodChannel('vpn/bg');
// parallel ping tests while connected (settings 1..6).
int bgWorkers = 2; // low data while connected; AI may raise freely
// FAST SEARCH: parallel ping tests (core delay test, no VPN toggling) used
// when looking for the first healthy server (settings 1..8).
int fastWorkers = 50; // fixed default — do not change without user request
// a healthy server not checked for this long is pinged again (occasional
// re-check, the server stays in the list until it really fails)
Duration recheckAfter = const Duration(minutes: 3);
// servers that failed are not tested again for this long (also kept on disk)
Duration failWindow = const Duration(minutes: 30);
// a healthy server is only deleted after this many failed re-checks in a row
int missLimit = 3;

// OpenVPN: public volunteer servers, the list is refreshed every few minutes
const vpngateUrl = 'https://www.vpngate.net/api/iphone/';
const maxOvpn = 80; // OpenVPN servers kept from each download
const ovpnConnectTimeout = Duration(seconds: 25);

const _gh = 'https://raw.githubusercontent.com/';
// Only lists that are refreshed often. HOT ones come first and are tested
// first; dead links are skipped automatically and ranked by health at runtime.
final List<String> _paths = [
  // ---- HOT: updated every few minutes / hours
  for (var i = 1; i <= 10; i++)
    'V2RAYCONFIGSPOOL/V2RAY_SUB/main/v2ray_configs_no$i.txt',
  for (final p in ['mix', 'vless', 'vmess', 'shadowsocks', 'trojan'])
    'iboxz/free-v2ray-collector/main/main/$p.txt',
  'ebrasha/free-v2ray-public-list/main/V2Ray-Config-By-EbraSha.txt',
  'MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/all_sub.txt',
  for (final p in ['vless', 'vmess', 'trojan'])
    '0xRadikal/Free-v2ray-Configs/main/protocols/$p.txt',
  for (final p in ['vless', 'vmess', 'trojan'])
    'Idolvpn/Automate-V2ray-Config-Collector/main/configs/$p.txt',
  'barry-far/V2ray-Config/main/All_Configs_Sub.txt',
  for (var i = 1; i <= 8; i++) 'barry-far/V2ray-Config/main/Sub$i.txt',
  for (final p in ['vmess', 'vless'])
    'barry-far/V2ray-Config/main/Splitted-By-Protocol/$p.txt',
  'Epodonios/v2ray-configs/refs/heads/main/All_Configs_Sub.txt',
  for (var i = 1; i <= 10; i++)
    'Epodonios/v2ray-configs/refs/heads/main/Sub$i.txt',
  for (final p in ['mixed', 'vmess', 'vless', 'trojan', 'shadowsocks'])
    'soroushmirzaei/telegram-configs-collector/main/splitted/$p',
  for (final p in ['mix', 'vmess', 'vless', 'trojan', 'ss'])
    'itsyebekhe/PSG/main/subscriptions/xray/normal/$p',
  for (var i = 1; i <= 8; i++)
    'AvenCores/goida-vpn-configs/main/githubmirror/$i.txt',
  // ---- HOT 2026: verified frequent updaters (every 5–30 min / 4h)
  'ebrasha/free-v2ray-public-list/refs/heads/main/V2Ray-Config-By-EbraSha-All-Type.txt',
  'ebrasha/free-v2ray-public-list/refs/heads/main/all_extracted_configs.txt',
  'MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/super-sub.txt',
  '0xRadikal/Free-v2ray-Configs/main/top100.txt',
  '0xRadikal/Free-v2ray-Configs/main/verified/configs.txt',
  '0xRadikal/Free-v2ray-Configs/main/fast/configs.txt',
  '0xRadikal/Free-v2ray-Configs/main/all/configs.txt',
  'Alirewa/V2ray-Configs/main/config.txt',
  'Alirewa/V2ray-Configs/main/sub1.txt',
  'Alirewa/V2ray-Configs/main/sub2.txt',
  'Alirewa/V2ray-Configs/main/sub3.txt',
  for (final p in ['vless', 'vmess', 'trojan', 'ss'])
    'hamedcode/port-based-v2ray-configs/main/sub/$p.txt',
  'hamedcode/port-based-v2ray-configs/main/sub/top100.txt',
  'hamedcode/port-based-v2ray-configs/main/sub/port_443.txt',
  'hamedcode/port-based-v2ray-configs/main/sub/port_80.txt',
  'morpheusadam/v2ray-config/main/subs/bundles/best.txt',
  'morpheusadam/v2ray-config/main/subs/bundles/iran.txt',
  'morpheusadam/v2ray-config/main/subs/bundles/lite.txt',
  'morpheusadam/v2ray-config/main/subs/bundles/reality.txt',
  'lagzian/SS-Collector/main/configs/mixed/vless.txt',
  'lagzian/SS-Collector/main/configs/mixed/trojan.txt',
  'lagzian/SS-Collector/main/configs/mixed/ss.txt',
  'lagzian/SS-Collector/main/configs/psg/reality.txt',
  'lagzian/SS-Collector/main/configs/psg/vmess.txt',
  // verified live 2026-10-16
  '3inker/v2ray-subscription/main/subs/all_not_ru.txt',
  '3inker/v2ray-subscription/main/subs/all_ru.txt',
  'free-nodes/v2rayfree/main/sub',
  'ermaozi/get_subscribe/main/subscribe/v2ray.txt',
  'Au1rxx/free-vpn-subscriptions/main/output/v2ray-base64.txt',
  // ---- the rest
  'SoliSpirit/v2ray-configs/refs/heads/main/all_configs.txt',
  'nyeinkokoaung404/V2ray-Configs/main/All_Configs_Sub.txt',
  for (final p in ['vmess', 'vless', 'trojan', 'ss'])
    'nyeinkokoaung404/V2ray-Configs/main/Splitted-By-Protocol/$p.txt',
  'mahdibland/V2RayAggregator/master/sub/sub_merge.txt',
  for (final p in ['vmess', 'vless', 'trojan', 'ss'])
    'mahdibland/V2RayAggregator/master/sub/splitted/$p.txt',
  for (final p in ['mix', 'vmess', 'vless', 'trojan', 'ss'])
    'yebekhe/TelegramV2rayCollector/main/sub/normal/$p',
  'Danialsamadi/v2go/main/AllConfigsSub.txt',
  'roosterkid/openproxylist/main/V2RAY_RAW.txt',
  'Leon406/SubCrawler/main/sub/share/v2',
  for (final p in ['mixed', 'vmess', 'vless', 'trojan', 'shadowsocks'])
    'Surfboardv2ray/TGParse/main/splitted/$p',
  for (final p in ['vless', 'vmess', 'trojan', 'shadowsocks'])
    'V2RayRoot/V2RayConfig/main/Config/$p.txt',
  for (final p in ['vless', 'vmess', 'trojan', 'ss'])
    'mohamadfg-dev/telegram-v2ray-configs-collector/main/category/$p.txt',
  for (final p in ['vmess', 'vless', 'trojan', 'ss'])
    'Bardiafa/Free-V2ray-Config/main/Splitted-By-Protocol/$p.txt',
  for (final p in ['vmess', 'vless', 'trojan', 'ss'])
    'F0rc3Run/F0rc3Run/main/splitted-by-protocol/$p.txt',
  for (final p in ['vl', 'vm', 'tr', 'ss'])
    'sevcator/5ubscrpt10n/main/protocols/$p.txt',
  'MahsaNetConfigTopic/config/main/xray_final.txt',
  'peasoft/NoMoreWalls/master/list.txt',
  'chengaopan/AutoMergePublicNodes/master/list.txt',
  'NiREvil/vless/main/sub/SSTime',
  for (final p in ['mix', 'vmess', 'vless', 'trojan', 'ss'])
    'MhdiTaheri/V2rayCollector/main/sub/$p',
  for (final p in ['mixed', 'vmess', 'vless', 'trojan', 'shadowsocks'])
    'Kwinshadow/TelegramV2rayCollector/main/sub/$p',
  'Mahdi0024/ProxyCollector/master/sub/proxies.txt',
  'ShatakVPN/ConfigForge/main/configs/all.txt',
  'MrMohebi/xray-proxy-grabber-telegram/master/collected-proxies/row-url/all.txt',
  'Argh94/Proxy-List/main/All_Config.txt',
  'mehran1404/Sub_Link/main/V2RAY-Sub.txt',
  'sakha1370/OpenRay/main/output/all_valid_proxies.txt',
  'wuqb2i4f/xray-config-toolkit/main/output/base64/mix-uri',
];
final List<String> listUrls = [...([..._paths, ..._morePaths].map((p) => '$_gh$p').toList()), ..._extraUrls, ..._npvUrls];
// repos that publish fresh servers every few minutes / hours: tested first
const hotOwners = {
  'V2RAYCONFIGSPOOL',
  'iboxz',
  'ebrasha',
  'MatinGhanbari',
  '0xRadikal',
  'Idolvpn',
  'barry-far',
  'Epodonios',
  'soroushmirzaei',
  'itsyebekhe',
  'AvenCores',
  'Alirewa',
  'hamedcode',
  'morpheusadam',
  'lagzian',
  'ZendanTeam',
  'miladtahanian',
  'mmbateni',
  'liketolivefree',
  'Delta-Kronecker',
  '3inker',
  'free-nodes',
  'ermaozi',
  'Au1rxx',
  'HosseinKoofi',
  'youfoundamin',
};

// منابع با لیست verified/fast — در اتصال عادی اول تست می‌شوند
const speedOwners = {
  '0xRadikal', // top100 + verified + fast
  'Alirewa', // sub تازه و اولویت‌دار
  'ZendanTeam', // SS44 gold — تست ترافیک واقعی
  'MatinGhanbari', // super-sub
  'ebrasha',
  'Epodonios',
  'liketolivefree', // kobabi تست‌شده
  'iboxz',
  'V2RAYCONFIGSPOOL',
  'mmbateni',
  'miladtahanian',
  'Delta-Kronecker',
};
// below this download speed (KB/s) the connected server is replaced (0 = off)
int minSpeedKB = 0; // LOWDATA: speed-based switching off (no download tests)

// ---- settings ----
// user-adjustable (saved in settings)
int batchSize = 100; // دسته ۱۰۰ سرور در هر دور
int delayWorkers = 20; // (kept for settings compatibility)
Duration delayTimeout = const Duration(seconds: 6);
int goodWant = 10; // حداقل سرور سالم هدف
bool autoSpeed = true; // تست سرعت چند سرور برتر قبل از اتصال
int speedTopN = 3; // تست سرعت ۳ برتر — سریع‌تر وصل می‌شود
bool autoUpgrade = false; // LOWDATA // keep searching for new servers while connected
// real pings below this are fake -> server counts as bad / hidden.
// 0 = off: the real speed test decides (done right after connecting).
int minPingMs = 0;
// connected server has a terrible ping -> jump at once to the best-ping server
bool badPingSwitch = false; // LOWDATA
int badPingMs = 3000;
// BADPINGLOOP: when every server a quick test finds has a bad ping (> badPingMs),
// the next quick parallel test starts at once, and so on. After
// [badPingMaxRounds] such rounds in a row the loop gives up being picky (so a
// slow network can still connect).
int badPingRounds = 0;
const int badPingMaxRounds = 6;
// the healthy servers of the last session are tested first
bool savedFirst = false; // never prefer folder/saved — test new servers
// learn what works on this network (protocol / transport / port / source) and
// test the most likely servers first; skip lists that never give a server
bool smartOrder = true;
// when every server was tested: download a new list and go on, forever
bool autoCycle = false; // LOWDATA: no endless list re-downloads
// ULTRA: multi-variant matrix (Fragment/fp/ALPN/DNS/port/cleanIP/Mux/Noise...)
// default OFF so normal search only tests the plain config (much faster).
// Turn on from Settings → «حالت فوق‌العاده» when a hard network needs variants.
bool ultraMode = false;
// INDESTRUCTIBLE: endless search — default OFF to save data; national mode
// and AI pilot can still turn it on when needed.
bool indestructibleMode = false;
// TURBO: after a working tunnel is up, try the same server without Fragment/
// Noise (the biggest speed killers) and with Mux, then keep it if traffic
// still flows. Ping does not matter — throughput does.
bool turboSpeed = true;
// minutes before the downloaded list is refreshed. Big value on purpose: the
// list is replaced when ALL servers were tested (autoCycle), not by the clock.
int listRefreshMin = 240;
int failMin = 120; // minutes a failed server is not tested again
int recheckMin = 30; // minutes before a healthy server is pinged again
int maxBatches = 5; // safety limit per search
const standbyBatches = 10; // batches per standby search cycle
const bgSearchOff = false; // RETRYPATCH // SPEEDSWITCHPATCH: no search while connected
// while connected the tunnel is shared with the tests, so the batch is bigger
// and the timeout longer (fewer false "dead" results). The healthy servers
// are re-checked inside the batch every 25 tests, so a big batch is safe.
int standbyBatchSize = 30;
const bgTimeoutSecs = 8;
int firstBatchSize = 40; // موازی کافی برای پیدا کردن سریع اولین سالم
int fetchWorkers = 4;
Duration fetchDeadline = const Duration(seconds: 20);
int tcpWorkers = 50;
int maxPerSource = 100;
Duration tcpTimeout = const Duration(milliseconds: 3000);
// TLS handshakes in the prefilter leaked sockets (crash, instant failures)
const probeTls = false;
const speedUrl = 'https://speed.cloudflare.com/__down?bytes=300000';
const smallSpeedUrl = 'https://speed.cloudflare.com/__down?bytes=100000';
const httpProxyPort = 10809;
// anti-flapping / watchdog
// A dead / broken server is replaced right away: 2 failed checks (~10 s),
// no waiting for the 10 minute speed-trial timer.
Duration watchEvery = const Duration(seconds: 45); // متعادل
int watchFailLimit = 3;
int badPingLimit = 3;
const minHold = Duration(seconds: 6);
// FASTPATCH ----------------------------------------------------
int fastPickN = 2; // سریع وصل شو با ۲ سرور سالم؛ بقیه در پس‌زمینه
int fastPickMs = 8000; // حداکثر ۸ثانیه بعد از اولین سالم
bool betterSwitch = true; // فقط وقتی سرور خیلی بهتر باشد
const betterGain = 0.50; // باید حداقل ۵۰٪ بهتر باشد (پینگ نصف یا کمتر)
const betterMinGapMs = 50; // حداقل ۵۰ms اختلاف
const betterEvery = Duration(minutes: 6); // هر ۶ دقیقه حداکثر یک‌بار
int? connBaseDelay; // test ping of the connected server
int betterRun = 0;
bool aiFastOn = true; // parallel Gemini test (off = old one-by-one)
int aiTried = 0;
int aiHit = 0;
int aiGen = 0; // FASTPATCH-AI: one analysis loop per connection
int aiEveryMin = 30; // minutes between two analyses
const badFor = Duration(minutes: 10);
// continuous real-speed search: every new healthy server is speed-tested;
// if it is faster than the connected one it takes over, if it is only faster
// than a standby it moves up in the standby ranking (failover uses the order)
const upgradeEvery = Duration(seconds: 30); // min gap between two trials
const upgradeGain = 1.5; // باید حداقل ۵۰٪ سریع‌تر باشد (هماهنگ با قانون تعویض)
const manualSpeedMax = 1000; // no real limit: all healthy servers are tested
const speedBatch = 1; // servers speed-tested per trial
const speedFresh = Duration(minutes: 15); // older than this -> test again
const delayTestUrl = 'https://www.gstatic.com/generate_204';
// internet check through the tunnel.
// اول URLهای بدون نیاز به DNS سخت (IP/cloudflare)، بعد gstatic/google.
// خطای «Failed host lookup: www.gstatic.com» وقتی DNS تونل خراب است می‌آید.
const _pingUrls = [
  'http://cp.cloudflare.com/generate_204',
  'http://1.1.1.1/',
  'http://9.9.9.9/',
  'https://www.cloudflare.com/cdn-cgi/trace',
  delayTestUrl,
  'https://www.google.com/generate_204',
  'https://telegram.org/',
];

// PROXY MODE: no VPN tunnel / no key icon. Only a local proxy is started:
// SOCKS 127.0.0.1:10808 and HTTP 127.0.0.1:10809 (set it in the other app or
// in the Wi-Fi proxy settings). Saved in settings ('px').
bool proxyMode = false;
// the reason of the last failed start (shown to the user)
String _lastFailV = '';
String get lastFail => _lastFailV;
set lastFail(String v) {
  _lastFailV = v;
  if (v.isNotEmpty) dbg('اتصال: $v');
}

// links pasted with extra text around them ("@channel vless://...") are
// cleaned: the first vmess/vless/trojan/ss link inside the text is used
final _schemeRe =
    RegExp(r'^(vmess|vless|trojan|ss|ovpn)://', caseSensitive: false);
final _linkRe = RegExp(r'(vmess|vless|trojan|ss|ovpn)://[^\s<>"]+',
    caseSensitive: false);

// fast search state: if the parallel delay test never finds anything on this
// phone, the app falls back to the old (slow) test through the VPN tunnel
bool fastDelay = true;
int fastTested = 0, fastOk = 0;

// AUTOTUNEPATCH: real network measurement + automatic profile
bool autoTune = false;
String tuneInfo = '';
DateTime _tuneAt = DateTime.fromMillisecondsSinceEpoch(0);
bool _tuneBusy = false;
int _tuneLevel = -1; // 0 weak, 1 normal, 2 fast
int _tuneVote = -1, _tuneVoteN = 0;

void _tuneLog(String m) {
  try {
    dbg(m);
  } catch (_) {}
}

// latency of one URL, straight over the phone's own internet (no proxy)
Future<int?> _tuneLatency(String url) async {
  final c = HttpClient()
    ..findProxy = ((_) => 'DIRECT')
    ..connectionTimeout = const Duration(seconds: 5);
  final sw = Stopwatch()..start();
  try {
    final req =
        await c.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 5));
    final res = await req.close().timeout(const Duration(seconds: 5));
    await res.drain<void>();
    return sw.elapsedMilliseconds;
  } catch (_) {
    return null;
  } finally {
    c.close(force: true);
  }
}

// download speed in KB/s (1 MB file, 3 s window), straight, no proxy
Future<double?> _tuneSpeedKB() async {
  final c = HttpClient()
    ..findProxy = ((_) => 'DIRECT')
    ..connectionTimeout = const Duration(seconds: 6);
  try {
    return await () async {
      final req = await c.getUrl(Uri.parse(smallSpeedUrl));
      final res = await req.close();
      var bytes = 0;
      final sw = Stopwatch()..start();
      await for (final chunk in res) {
        bytes += chunk.length;
        if (sw.elapsed >= const Duration(seconds: 3)) break;
      }
      final secs = sw.elapsedMilliseconds / 1000;
      if (secs <= 0 || bytes == 0) return null;
      return bytes / 1024 / secs;
    }()
        .timeout(const Duration(seconds: 9));
  } catch (_) {
    return null;
  } finally {
    c.close(force: true);
  }
}

// -1 = no answer at all, 0 weak, 1 normal, 2 fast
int _tuneRate(int? lat, double? kb) {
  if (lat == null && kb == null) return -1;
  if ((kb != null && kb < 150) || (lat != null && lat > 1500)) return 0;
  if (kb != null && kb >= 1200 && (lat == null || lat < 600)) return 2;
  return 1;
}

// the values stay inside the real slider ranges of the settings page
void _tuneApply(int lv) {
  if (lv == 0) {
    // weak / filtered network: fewer parallel tests, longer waits, and do not
    // switch servers for every small glitch
    // fastWorkers stays 50 (FASTSET)
    bgWorkers = 1;
    delayTimeout = const Duration(seconds: 8);
    batchSize = 100;
    minSpeedKB = 0;
    badPingMs = 5000;
    badPingLimit = 3;
    watchFailLimit = 4;
  } else if (lv == 2) {
    // fast network: more parallel tests, strict about slow servers
    // fastWorkers stays 50 (FASTSET)
    bgWorkers = 1;
    delayTimeout = const Duration(seconds: 5);
    batchSize = 100;
    minSpeedKB = 0;
    badPingMs = 3000;
    badPingLimit = 3;
    watchFailLimit = 3;
  } else {
    // normal = the app's own defaults
    // fastWorkers stays 50 (FASTSET)
    bgWorkers = 1;
    delayTimeout = const Duration(seconds: 6);
    batchSize = 100;
    minSpeedKB = 0;
    badPingMs = 3000;
    badPingLimit = 3;
    watchFailLimit = 3;
  }
}

Future<void> autoTuneLoad() async {
  try {
    final p = await SharedPreferences.getInstance();
    autoTune = p.getBool('autotune_on2') ?? false;
  } catch (_swE) { _swl('autoTuneLoad#1', _swE);}
}

Future<void> autoTuneSave() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setBool('autotune_on2', autoTune);
  } catch (_swE) { _swl('autoTuneSave#1', _swE);}
}

// call it only while the VPN is NOT connected (else it measures the tunnel)
Future<void> autoTuneNow({bool force = false}) async {
  if (!autoTune || _tuneBusy) return;
  if (!force &&
      DateTime.now().difference(_tuneAt) < const Duration(minutes: 4)) {
    return;
  }
  _tuneBusy = true;
  try {
    if (force) _tuneLevel = -1;
    final lats = await Future.wait(_pingUrls.take(3).map(_tuneLatency));
    final ok = lats.whereType<int>().toList()..sort();
    final lat = ok.isEmpty ? null : ok[ok.length ~/ 2];
    final kb = await _tuneSpeedKB();
    _tuneAt = DateTime.now();
    final want = _tuneRate(lat, kb);
    if (want < 0) {
      tuneInfo = 'تنظیم خودکار: اینترنت جواب نداد؛ تنظیمات عوض نشد';
      _tuneLog('[AutoTune] no answer, settings unchanged');
      return;
    }
    if (_tuneLevel < 0) {
      _tuneLevel = want;
      _tuneVote = -1;
      _tuneVoteN = 0;
      _tuneApply(want);
    } else if (want == _tuneLevel) {
      _tuneVote = -1;
      _tuneVoteN = 0;
    } else {
      if (_tuneVote == want) {
        _tuneVoteN++;
      } else {
        _tuneVote = want;
        _tuneVoteN = 1;
      }
      if (_tuneVoteN >= 2) {
        _tuneLevel = want;
        _tuneVote = -1;
        _tuneVoteN = 0;
        _tuneApply(want);
      }
    }
    const names = ['ضعیف', 'معمولی', 'سریع'];
    tuneInfo = 'تنظیم خودکار: اینترنت ${names[_tuneLevel]} • '
        'پینگ ${lat ?? '-'}ms • ${kb == null ? '-' : kb.round()} KB/s';
    _tuneLog('[AutoTune] $tuneInfo | fw=$fastWorkers bw=$bgWorkers '
        'to=${delayTimeout.inSeconds}s minKB=$minSpeedKB '
        'badPing=${badPingMs}ms limits=$badPingLimit/$watchFailLimit');
  } catch (e) {
    _tuneLog('[AutoTuneError] $e');
  } finally {
    _tuneBusy = false;
  }
}

int _ci(dynamic v, int d, int lo, int hi) =>
    ((v as num?)?.toInt() ?? d).clamp(lo, hi).toInt();

final errorLog = ValueNotifier<String>('');
// network noise (timeouts of dead lists / servers) is not an error for the
// user: it is never shown
// ERRLOGPATCH: in-app error report (menu -> گزارش خطاها)
final List<String> dbgLines = [];
List<String> dbgPrev = []; // lines saved by the previous run
int dbgNet = 0;
DateTime? _lastNoHealthyLog; // harmless network errors (counted, not listed)
bool _dbgLoaded = false;
String _dbgLastSt = '';
Timer? _dbgSaveT;

Future<void> _dbgLoadPrev() async {
  try {
    final p = await SharedPreferences.getInstance();
    dbgPrev = p.getStringList('dbgLines') ?? <String>[];
    await _dbgProbLoad(p); // DIAGPATCH
    dbgProbPrev = p.getStringList('dbgProbs') ?? <String>[];
  } catch (_) {}
}

// INSPECTORPATCH: persistent list of problems found
class DbgProb {
  String msg;
  DateTime first, last;
  int n = 1;
  DbgProb(this.msg, this.first) : last = first;
}

final Map<String, DbgProb> dbgProbs = {};
List<String> dbgProbPrev = []; // problems saved by the previous run
Timer? _dbgProbT;

String _dbgHms(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

// tiny problems: any log line with one of these words is kept too
bool _dbgMicro(String m) {
  const keys = [
    'ناموفق', 'نشد', 'نیامد', 'خطا', 'شکست', 'خراب', 'گیر', 'رد شد',
    'قطع', 'ضعیف', 'کند', 'خالی', 'صفر', 'blacklist', 'لیست سیاه',
    'Exception', 'xception', 'imeout', 'timeout', 'Error', 'error',
    'failed', 'Failed', 'warn', 'Warn', 'assert', 'null', 'Null',
    'Stack', 'overflow', 'denied', 'permission', 'Permission',
    'E-CONFIG', 'E-SITE', 'E-TUN', 'E-START', 'E-SWALLOW', 'E-CORE',
    'E-APP', 'E-ORPHAN', 'E-NO-', 'E-PING', 'E-STATUS',
    'کانفیگ ناموفق', 'سایت‌چک', 'پینگ داشت', 'خودترمیمی',
    'خلبان', 'switch_best', 'تعویض', 'توربو', 'سالم پیدا نشد',
    'پاک شد', 'DISCONNECT', 'CONNECTED', 'failover', 'orphan',
    'تونل', 'tun', 'DNS', 'dns', 'مجوز', 'باتری', 'battery',
    'Mux', 'Fragment', 'core', 'هسته', 'جستجو', 'صف خالی',
    'ندارد', 'نیست', 'نمی', 'نمی‌', 'abort', 'لغو', 'busy',
    'switching', 'در حال', 'یتیم', 'مردود', 'blacklist',
  ];
  for (final k in keys) {
    if (m.contains(k)) return true;
  }
  return false;
}

String _dbgLineKey(String x) {
  final i = x.indexOf(' • اولین');
  return (i < 0 ? x : x.substring(0, i)).replaceAll(RegExp(r'\d+'), '#');
}

String _dbgProbLine(DbgProb p) =>
    '${p.msg} • اولین ${_dbgHms(p.first)} • آخرین ${_dbgHms(p.last)} • ${p.n} بار';

void _dbgProb(String msg) {
  try {
    if (msg.startsWith('شمارنده:') ||
        msg.startsWith('♥') ||
        msg.startsWith('اتصال ≈') ||
        msg.startsWith('حالت:')) {
      return;
    }
    if (!(msg.startsWith('⚠') ||
        msg.startsWith('خطا:') ||
        msg.startsWith('اتصال:') ||
        msg.startsWith('علت تعویض:') ||
        msg.startsWith('بازرس:') ||
        _dbgMicro(msg))) {
      return;
    }
    final key = msg.replaceAll(RegExp(r'\d+'), '#');
    final now = DateTime.now();
    final old = dbgProbs[key];
    if (old == null) {
      dbgProbs[key] = DbgProb(msg, now);
      if (dbgProbs.length > 300) {
        String? oldKey;
        DateTime? oldT;
        dbgProbs.forEach((k, v) {
          if (oldT == null || v.last.isBefore(oldT!)) {
            oldKey = k;
            oldT = v.last;
          }
        });
        if (oldKey != null) dbgProbs.remove(oldKey);
      }
    } else {
      old.msg = msg;
      old.last = now;
      old.n++;
    }
    _dbgProbT?.cancel();
    _dbgProbT = Timer(const Duration(seconds: 3), () async {
      try {
        await _dbgProbSave();
      } catch (_) {}
    });
  } catch (_) {}
}

String _dbgProbTextOld() {
  final l = dbgProbs.values.toList()
    ..sort((a, b) => b.last.compareTo(a.last));
  final b = StringBuffer('== مشکل‌های پیدا شده (${l.length}) ==\n');
  if (l.isEmpty) b.write('هیچ مشکلی ثبت نشده\n');
  for (final p in l) {
    b.write('${_dbgProbLine(p)}\n');
  }
  if (dbgProbPrev.isNotEmpty) {
    b.write('--- مشکل‌های اجرای قبلی ---\n');
    for (final x in dbgProbPrev) {
      b.write('$x\n');
    }
  }
  b.write('====================');
  return b.toString();
}

// DIAGPATCH: persistent problems + where / cause / fix for every problem
bool _dbgProbLoaded = false;

String _dbgStamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  final n = DateTime.now();
  final hms = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  if (t.year == n.year && t.month == n.month && t.day == n.day) return hms;
  return '${t.month}/${t.day} $hms';
}

// merge the problems saved by the earlier runs into the current map
Future<void> _dbgProbLoad(SharedPreferences p) async {
  if (_dbgProbLoaded) return;
  _dbgProbLoaded = true;
  try {
    for (final x in p.getStringList('dbgProbs3') ?? <String>[]) {
      final f = x.split('\u0001');
      if (f.length < 5) continue;
      final first = DateTime.fromMillisecondsSinceEpoch(int.tryParse(f[2]) ?? 0);
      final last = DateTime.fromMillisecondsSinceEpoch(int.tryParse(f[3]) ?? 0);
      final n0 = int.tryParse(f[4]) ?? 1;
      final cur = dbgProbs[f[0]];
      if (cur == null) {
        final d = DbgProb(f[1], first);
        d.last = last;
        d.n = n0;
        dbgProbs[f[0]] = d;
      } else {
        if (first.isBefore(cur.first)) cur.first = first;
        cur.n += n0;
      }
    }
  } catch (_) {}
}

Future<void> _dbgProbSave() async {
  try {
    final pr = await SharedPreferences.getInstance();
    await _dbgProbLoad(pr);
    final l = dbgProbs.entries.toList()
      ..sort((a, b) => b.value.last.compareTo(a.value.last));
    final out = <String>[];
    for (final e in l.take(400)) {
      out.add([
        e.key,
        e.value.msg,
        e.value.first.millisecondsSinceEpoch,
        e.value.last.millisecondsSinceEpoch,
        e.value.n
      ].join('\u0001'));
    }
    await pr.setStringList('dbgProbs3', out);
  } catch (_) {}
}

// "پاک کردن": everything goes, memory and disk
Future<void> _dbgClearAll() async {
  try {
    dbgPrev = [];
    dbgProbPrev = [];
    _dbgProbT?.cancel();
    _dbgSaveT?.cancel();
    final p = await SharedPreferences.getInstance();
    await p.remove('dbgLines');
    await p.remove('dbgProbs');
    await p.remove('dbgProbs3');
  } catch (_) {}
}

// where an error was logged from: function names + line numbers of the stack
String _dbgWhere() {
  try {
    final out = <String>[];
    final re = RegExp(r'#\d+\s+(.+?)\s+\(.*?(\w+\.dart):(\d+)');
    for (final ln in StackTrace.current.toString().split('\n')) {
      final mm = re.firstMatch(ln);
      if (mm == null) continue;
      final fn = mm.group(1) ?? '';
      final file = mm.group(2) ?? '';
      if (fn.contains('_dbgWhere') || fn.contains('logError')) continue;
      if (file != 'main.dart' &&
          file != 'iran_ai_extras.dart' &&
          file != 'tg_proxy.dart') {
        continue;
      }
      out.add('${fn.replaceAll('<anonymous closure>', 'fn')}:${mm.group(3)}');
      if (out.length >= 3) break;
    }
    return out.isEmpty ? '' : ' @ ${out.join(' ← ')}';
  } catch (_) {
    return '';
  }
}

// [code, where, cause, fix] for a problem line, or null when unknown
List<String> _dbgHelpOf(String m) {
  List<String> h(String c, String w, String a, String f) => [c, w, a, f];
  bool has(String k) => m.contains(k);
  final extra = extraDiagOf(m);
  if (extra != null) return extra;
  if (has('Activity')) {
    return h('E-NO-ACTIVITY',
        'app_main/main.dart → _start (شرط inForeground / vpnPermOk) و _connectLoop',
        'اپ در پس‌زمینه بود و برای گرفتن مجوز VPN به Activity نیاز داشت. در نسخه‌های قبل هر تعویض در پس‌زمینه (مثلاً «پینگ کمتر») همین‌جا شکست می‌خورد، VPN وصل قطع می‌شد و برنامه چرخه‌ی بی‌پایان سرور عوض می‌کرد.',
        'اصلاح شد: وقتی مجوز VPN قبلاً یک بار داده شده باشد (vpnPermOk) در پس‌زمینه دیگر درخواست مجوز نمی‌شود و اتصال ادامه پیدا می‌کند. اگر بعد از این نسخه هنوز ثبت می‌شود یعنی اپ از اول در پس‌زمینه وصل شده؛ یک بار اپ را باز کن و اتصال را بزن.');
  }
  if (m.startsWith('وضعیت: قطع شد')) {
    return h('E-STATUS-DISCONNECT',
        'app_main/main.dart → _swapTo / _stableSwap / disconnect (_set(قطع شد))',
        'فقط ثبت قطع شدن اتصال است؛ خطا نیست. هنگام تعویض سرور هم برای چند ثانیه ثبت می‌شود.',
        'نیازی به اصلاح نیست. فقط اگر بعدش اتصال برنگشت، خطوط «اتصال:» و کد E-NO-ACTIVITY را ببین.');
  }
  if (has('ردیف همه')) {
    return h('E-STATUS-INFO',
        'app_main/main.dart → _findGood (وضعیت تست موازی)',
        'این فقط پیام پیشرفت جستجوست؛ مشکل نیست و به‌خاطر کلمه‌ی «ردیف» اشتباهی در لیست مشکل‌ها آمده بود.',
        'اصلاح شد: دیگر ثبت نمی‌شود. با «پاک کردن» از لیست برود.');
  }
  if (has('پیش‌پرواز: شبکه خیلی ضعیف')) {
    return h('E-PREFLIGHT-WEAK',
        'app_main/main.dart → پیش‌پرواز قبل از جستجو (DNS و HTTP)',
        'تست DNS/HTTP قبل از جستجو خیلی ضعیف بود (اینترنت موبایل ناپایدار). برنامه عمداً با تلاش دوباره ادامه می‌دهد.',
        'نیازی به اصلاح نیست. اگر همیشه رخ می‌دهد اینترنت یا اپراتور مشکل دارد، نه کد.');
  }
  if (has('کیفیت: 0')) {
    return h('E-QUALITY-ZERO',
        'app_main/main.dart → _connStatus (کیفیت اتصال)',
        'در لحظه‌ی اول اتصال هنوز هیچ پینگ یا سرور سالمی اندازه‌گیری نشده بود؛ عدد صفر موقتی است.',
        'نیازی به اصلاح نیست؛ چند ثانیه بعد کیفیت به‌روز می‌شود.');
  }
  // SWALLOWPATCH: errors that a catch (_) used to throw away
  if (m.startsWith('🕳')) {
    var code = 'E-SWALLOW-OTHER';
    var cause = 'یک try/catch این خطا را گرفت و بی‌صدا رد کرد؛ برنامه ادامه داد ولی کاری که داخل try بود نیمه‌کاره ماند.';
    var fix = 'نوع خطا و تابع:خط را برای Claude بفرست تا همان‌جا شرط یا اصلاح درست شود.';
    if (has('TimeoutException')) {
      code = 'E-SWALLOW-TIMEOUT';
      cause = 'یک عملیات (تست سرور، دانلود، گرفتن لیست) از مهلتش بیشتر طول کشید.';
      fix = 'اگر زیاد و روی همه‌ی سرورها تکرار می‌شود مهلت همان تابع را بیشتر کن؛ اگر فقط گاهی است اینترنت کند است و مشکل کد نیست.';
    } else if (has('SocketException') ||
        has('HttpException') ||
        has('HandshakeException') ||
        has('ClientException')) {
      code = 'E-SWALLOW-NET';
      cause = 'خطای شبکه: اتصال برقرار نشد، قطع شد یا DNS جواب نداد (معمولاً فیلتر یا اینترنت ضعیف).';
      fix = 'اطلاعاتی است. اگر در تابع حساسی مثل _delayOf / _standbyRun / _startWatch زیاد می‌بینی، آدرس تست یا مسیر (از داخل یا بیرون VPN) را چک کن.';
    } else if (has('FormatException')) {
      code = 'E-SWALLOW-FORMAT';
      cause = 'داده‌ی ناقص یا نامعتبر (کانفیگ، JSON، عدد) خوانده نشد.';
      fix = 'اگر فقط گاهی است یعنی یک کانفیگ خراب بود؛ اگر برای همه است منبع لیست یا قالب ذخیره‌شده را چک کن.';
    } else if (has('PlatformException') || has('MissingPluginException')) {
      code = 'E-SWALLOW-PLATFORM';
      cause = 'خطای بخش native اندروید (هسته، مجوز، کانال vpn/bg یا بهینه‌سازی باتری).';
      fix = 'تابع:خط را برای Claude بفرست؛ معمولاً به نسخه‌ی پلاگین یا مجوز اندروید مربوط است.';
    } else if (has('FileSystemException')) {
      code = 'E-SWALLOW-FILE';
      cause = 'خواندن یا نوشتن فایل شکست خورد (فضای کم یا مجوز).';
      fix = 'فضای گوشی و مجوز ذخیره‌سازی را چک کن.';
    } else if (has('NoSuchMethodError') ||
        has('RangeError') ||
        has('StateError') ||
        has('Null check') ||
        has('type ')) {
      code = 'E-SWALLOW-BUG';
      cause = 'باگ کد: مقدار null، اندیس بیرون از لیست یا نوع اشتباه، و try/catch آن را پنهان کرده بود.';
      fix = 'تابع:خط را برای Claude بفرست تا شرط null/اندیس همان‌جا درست شود.';
    }
    return h(code,
        'محل: تابع:شماره‌ی خط بعد از «در» همین پیام (main.dart پیوست همین Release)',
        cause, fix);
  }

  // ---- the counters of the watchdog that went up ----
  if (has('ریز:')) {
    final nm = RegExp(r'(\S+) بالا رفت').firstMatch(m)?.group(1) ?? '';
    if (nm.contains('ناموفق')) {
      return h('E-CNT-FAILS',
          'app_main/main.dart → _startWatch (fails++ وقتی pingAny با ۶ ثانیه مهلت جواب نداد)',
          'تست اینترنت از داخل تونل جواب نداد. اطلاعاتی است، خطا نیست؛ فقط وقتی به watchFailLimit برسد سرور عوض می‌شود.',
          'اگر روی سرور سالم هم زیاد بالا می‌رود: watchFailLimit را بیشتر کن یا آدرس تست در pingAny را عوض کن.');
    }
    if (nm.contains('تعمیر')) {
      return h('E-CNT-TUNFIX',
          'app_main/main.dart → _startWatch (tunFixes++) و _restartTunnel',
          'برنامه تونل را روی همان سرور دوباره ساخت چون tun دو بار پشت‌سرهم دیده نشد.',
          'به کد E-NO-TUN نگاه کن؛ ریشه‌ی این همان است.');
    }
    if (nm.contains('tun')) {
      return h('E-CNT-TUNBAD',
          'app_main/main.dart → _startWatch (tunBad++) و tunUp()',
          'در یک بررسی tun پیدا نشد. اطلاعاتی است؛ بعد از ۲ بار پشت‌سرهم تونل دوباره ساخته می‌شود.',
          'به کد E-NO-TUN نگاه کن.');
    }
    if (nm.contains('پینگ')) {
      return h('E-CNT-BADPING',
          'app_main/main.dart → _startWatch (badPingRun++ وقتی پینگ از badPingMs بیشتر است)',
          'پینگ سرور فعلی بالاتر از حد تنظیمات بود. اطلاعاتی است.',
          'اگر زیاد تعویض می‌شود badPingMs را بیشتر کن یا «تعویض سریع وقتی پینگ بد شد» را خاموش کن.');
    }
    if (nm.contains('داده')) {
      return h('E-CNT-NODATA',
          'app_main/main.dart → _startWatch (noData++ هر ~۳۰ ثانیه وقتی دانلود کوچک داده نیاورد)',
          'پینگ رد می‌شود ولی دانلود کوچک (smallSpeedUrl) داده‌ای نیاورد. با ۳ بار پشت‌سرهم سرور عوض می‌شود (E-DOWNLOAD-ZERO).',
          'اگر روی چند سرور مختلف تکرار شد، آدرس smallSpeedUrl را عوض کن یا آدرس دوم بگذار.');
    }
    if (nm.contains('کندی')) {
      return h('E-CNT-SLOW',
          'app_main/main.dart → _startWatch (lowSpeed++ وقتی سرعت از minSpeedKB کمتر بود)',
          'سرعت اندازه‌گیری‌شده زیر حداقل تنظیمات بود. اطلاعاتی است؛ با ۲ بار پشت‌سرهم و وجود سرور آماده، سرور عوض می‌شود.',
          'اگر زیاد تعویض می‌شود «تعویض اگر سرعت کمتر از ...» (minSpeedKB) را کم کن.');
    }
    return h('E-CNT-OTHER', 'app_main/main.dart → _inspect (شمارنده‌های واچ‌داگ)',
        'یکی از شمارنده‌های واچ‌داگ بالا رفت.',
        'نام شمارنده را برای Claude بفرست.');
  }

  // ---- stuck flags / frozen loop (patch_inspector.py) ----
  if (has('حلقه')) {
    return h('E-LOOP-FREEZE',
        'تشخیص: app_main/main.dart → _inspect (تایمر ۳ ثانیه‌ای). مظنون‌ها: _standbyRun ← _findGood(bg:true) / _recheckStandby / _loadPending / _saveCache',
        'ترد اصلی برنامه بیش از ۸ ثانیه کار نکرد، در حالی که اپ در پیش‌زمینه بود (فریزهای پس‌زمینه دیگر ثبت نمی‌شوند چون کار اندروید است، نه خطای کد). یعنی کار سنگین روی ترد اصلی انجام شده (مرتب‌سازی/ذخیره‌ی لیست هزاران سرور).',
        'اصلاح شد: پردازش لیست سرورها (fetchServers / _loadPending) حالا تکه‌تکه انجام می‌شود و ownerOf کش دارد. اگر بعد از این نسخه هنوز ثبت می‌شود، ساعت دقیق و کار قبل از آن در لاگ را بفرست.');
  }
  if (has('اجرا نشده')) {
    return h('E-STANDBY-STALE',
        'تشخیص: patch_inspector.py → _insWarn(standby). زمان از lastStandby در app_main/main.dart → _standbyRun می‌آید (فقط در پایان هر دور نوشته می‌شود)',
        'اغلب هشدار کاذب است: وقتی جستجوی پس‌زمینه هنوز در جریان است (_findGood با explore:true) lastStandby به‌روز نمی‌شود. واقعی فقط وقتی searching خاموش است و _standbyRun به‌خاطر یکی از گاردها برمی‌گردد (bgDisabled / upBusy / switching / abort / appGone).',
        'در patch_inspector.py به شرط standby عبارت «&& !searching» اضافه شود، یا داخل _findGood بعد از هر batch lastStandby = DateTime.now() گذاشته شود.');
  }
  if (has('مشغول»')) {
    return h('E-BUSY-STUCK',
        'app_main/main.dart → _runBusy (busy=true تا پایان f). صدازننده‌ها: _doConnect / _failover / _swapTo / _restartTunnel',
        'اغلب خطای واقعی نیست: busy تا پایان کل تعویض (شامل _acquire = جستجو و تست سرورها) روشن می‌ماند و بیش از ۹۰ ثانیه عادی است. گیر واقعی یعنی یک await بی‌پایان (_stopCore، startV2Ray، _ensureBattery، _ensureSession یا تبلیغ).',
        'اصلاح شد: هشدار حالا فقط وقتی داده می‌شود که جستجو، تعویض و _acquire همه خاموش باشند (۵ دقیقه)، و _runBusy از قبل timeout پنج‌دقیقه‌ای دارد. اگر دوباره ثبت شد ساعت و خطوط قبلش را بفرست.');
  }
  if (has('تعویض»')) {
    return h('E-SWITCH-STUCK',
        'app_main/main.dart → switching=true در _doConnect / _failover / _swapTo / _restartTunnel / _upgradeRun / disconnect؛ آزادسازی با _unlockLater (۳ ثانیه بعد)',
        'تا پایان تعویض روشن می‌ماند (۶۰+ ثانیه وقتی _acquire طول بکشد). گیر واقعی فقط وقتی busy و searching هر دو خاموش‌اند (مسیری که _unlockLater را صدا نزده).',
        'شرط هشدار: switching && !busy && !searching. هر مسیر با switching=true باید در finally خودش _unlockLater داشته باشد.');
  }
  if (has('واچ') && has('گیر')) {
    return h('E-WATCH-BUSY',
        'app_main/main.dart → _startWatch (watchBusy=true تا finally؛ داخلش await _failover / _swapTo / _restartTunnel)',
        'معمولاً هشدار کاذب: watchBusy در تمام مدت تعویض سرور (تا ۶۰+ ثانیه) روشن است. یک بررسی عادی حداکثر ~۲۰ ثانیه است (pingAny ۶s + measure ۸s).',
        'اصلاح شد: هشدار فقط وقتی watchBusy بیش از ۹۰s، بدون busy/switching/searching و در پیش‌زمینه روشن بماند ثبت می‌شود، و patch_selfheal.py بعد از ۹۰s آن را خودکار آزاد می‌کند.');
  }
  if (has('ارتقا گیر')) {
    return h('E-UPBUSY',
        'app_main/main.dart → _upgradeRun (upBusy=true ... false در finally)',
        'آزمایش سرعت سرورهای جایگزین (وصل شدن + دانلود برای هر سرور) طولانی شد یا یک await گیر کرد.',
        'برای هر سرور در _upgradeRun timeout سخت بگذار و مطمئن شو upBusy=false در finally است.');
  }
  if (has('بازبینی')) {
    return h('E-RECHECK',
        'app_main/main.dart → _recheckStandby (rechecking=true؛ pool روی ۱۲ سرور با _delayOf)',
        'بازبینی سرورهای سالم با شبکه‌ی کند از ۱۵۰ ثانیه بیشتر شد.',
        'تعداد (list.take(12)) یا _bgTimeout را کم کن.');
  }
  if (has('CONNECTED است')) {
    return h('E-CORE-UP-APP-DOWN',
        'app_main/main.dart → شنونده‌ی FlutterV2ray(onStatusChanged:) در initState، خط «if (!mounted || busy || switching) return;»',
        'رویداد CONNECTED وقتی busy/switching روشن بود نادیده گرفته شد و connected هرگز true نشد؛ بعد از آزاد شدن busy رویداد تازه‌ای نمی‌آید. یا هسته بالا آمده ولی _onConnected صدا زده نشده (هسته‌ی بی‌صاحب).',
        'اصلاح شد: اگر اپ اتصال نمی‌خواهد (میخواهم=0) و هسته هنوز CONNECTED است، بعد از حدود ۶ ثانیه هسته‌ی بی‌صاحب خودکار خاموش می‌شود؛ دکمه‌ی «قطع» هم تا ۳ بار توقف را تکرار می‌کند. اگر اپ اتصال می‌خواهد، _syncCore آن را همگام می‌کند. اگر بعد از این نسخه هنوز ثبت می‌شود، خطوط «حالت:» همان ساعت را بفرست.');
  }
  if (has('ولی هسته')) {
    return h('E-APP-UP-CORE-DOWN',
        'app_main/main.dart → شنونده‌ی FlutterV2ray(onStatusChanged:) در initState',
        'رویداد DISCONNECTED وقتی busy/switching روشن بود نادیده گرفته شد، پس connected=true مانده و dropTimer/_failover فعال نشد؛ یا اندروید سرویس VPN را بسته.',
        'خودکار اصلاح می‌شود (patch_selfheal.py → _syncCore: بعد از دو بار دیدن پشت‌سرهم و حداقل ۸ ثانیه بعد از آخرین تعویض → connected=false و _failover). اگر مکرر است به خطوط «هسته:» و E-CORE-DROP نگاه کن (بستن سرویس VPN توسط اندروید / کم‌حافظه).');
  }
  if (has('جایگزین نیست')) {
    return h('E-NO-STANDBY',
        'تشخیص: patch_inspector.py → _insWarn(noready). شمارنده: _ready() در app_main/main.dart',
        'وصل هستی ولی هیچ سرور سالم جایگزینی در لیست good نیست و جستجویی هم در کار نیست.',
        'مطمئن شو autoUpgrade روشن و bgDisabled خاموش است؛ اگر bgDisabled شده به E-BG-DISABLED نگاه کن.');
  }
  if (has('خواسته شده')) {
    return h('E-ORPHAN',
        'app_main/main.dart → _startWatch (شاخه‌ی !connected) و dropTimer در شنونده‌ی هسته',
        'برنامه می‌خواهد وصل باشد ولی نه وصل است، نه تعویضی در جریان است، نه تایمر قطع فعال است. واچ‌داگ منتظر شرط lastSwitch>10s یا مسیری که فقط یک بار اجرا می‌شود.',
        'خودترمیمی: اگر این حالت بیش از ۲۰ ثانیه ماند و watch فعال بود → _failover() صدا زده شود.');
  }
  if (has('واچ') && has('خاموش است')) {
    return h('E-WATCH-OFF',
        'app_main/main.dart → _startWatch / watch?.cancel در disconnect و _failover (حالت abort)',
        'واچ‌داگ کنار رفته ولی wantVpn هنوز true است.',
        'اصلاح شد: اگر واچ‌داگ وسط اتصال (connected و بدون busy/switching) بیش از ۱۰s خاموش بماند، بازرس خودکار _startWatch() را صدا می‌زند.');
  }
  if (has('بالاست')) {
    return h('E-HIGH-PING',
        'تشخیص: patch_inspector.py → _insWarn(pingHigh) (current.ping > 1500)',
        'پینگ سرور فعلی بیش از ۱۵۰۰ms است. اطلاعاتی است.',
        'اگر تعویض نمی‌شود badPingSwitch و badPingMs را در تنظیمات چک کن.');
  }
  if (has('تست سریع خاموش')) {
    return h('E-FAST-OFF',
        'app_main/main.dart → _testBatchFast (fastDelay=false وقتی تست سریع جواب نداد)',
        'تست سریع (تأخیر هسته) نتیجه نداد و برنامه به تست کندتر برگشت.',
        'اگر هر بار رخ می‌دهد تست سریع با نسخه‌ی هسته‌ی فعلی سازگار نیست (patch_v2ray_core.py را ببین).');
  }
  if (has('غیرفعال شد')) {
    return h('E-BG-DISABLED',
        'app_main/main.dart → _testBatchDelay (bgDisabled=true وقتی bgOk==0 و bgTested>=30)',
        '۳۰ تست پس‌زمینه بدون یک موفقیت؛ جستجوی پس‌زمینه برای صرفه‌جویی کامل خاموش شد.',
        'با «اتصال» دوباره روشن می‌شود (_doConnect bgDisabled=false). اگر مکرر است تایم‌اوت تست پس‌زمینه (_bgTimeout) را بیشتر کن.');
  }
  if (has('تونل نساخته')) {
    return h('E-TUN-FAIL-RUN',
        'app_main/main.dart → _start / _startOvpn (tunFailRun)',
        'اندروید پشت‌سرهم ۶ بار تونل نساخت.',
        'به کد E-NO-TUN نگاه کن؛ مجوز VPN و اپ‌های VPN دیگر را چک کن.');
  }
  if (has('زود قطع')) {
    return h('E-SHORT-CONN',
        'تشخیص: patch_inspector.py → _inspect (اتصال کمتر از ۳۰۰ ثانیه)',
        'اتصال زود قطع شد و wantVpn روشن بود. علت داخل خود پیام (بعد از «علت») است.',
        'کد علت را پیدا کن: پینگ ناموفق = E-PING-FAIL، دانلود صفر = E-DOWNLOAD-ZERO، سرعت پایین = E-LOW-SPEED-SWITCH، هسته قطع کرد = E-CORE-DROP.');
  }

  // ---- why the server was switched (lastWhy) ----
  if (has('سرور صفر')) {
    return h('E-DOWNLOAD-ZERO',
        'app_main/main.dart → _startWatch (noData >= 3؛ هر ~۳۰ ثانیه measure(smallSpeedUrl))',
        'پینگ رد می‌شود ولی ۳ بار پشت‌سرهم دانلود کوچک داده نیاورد: سرور بی‌داده/فیلتر، یا خود smallSpeedUrl بسته است.',
        'اگر چند سرور پشت‌سرهم با همین علت رد شدند آدرس smallSpeedUrl را عوض کن یا آدرس دوم fallback بگذار.');
  }
  if (has('داده‌ای نیامد')) {
    return h('E-REAL-SPEED-ZERO',
        'app_main/main.dart → _measureCurrent (تست سرعت واقعی بلافاصله بعد از اتصال)',
        'بعد از اتصال دانلود تست هیچ داده‌ای نیاورد؛ سرور «پینگ دارد ولی داده ندارد».',
        'عادی و مفید است (سرور رد می‌شود). اگر برای همه‌ی سرورها رخ داد آدرس تست سرعت را چک کن.');
  }
  if (has('پینگ کمتر')) {
    return h('E-LOWER-PING-SWITCH',
        'app_main/main.dart → _startWatch / _swapTo (lastWhy = \'پینگ کمتر\')',
        'اتصال سالم بود ولی سرور آماده‌ای با پینگ خیلی کمتر پیدا شد و برنامه عمداً به آن رفت. خطا نیست؛ فقط ثبت علت تعویض است.',
        'نیازی به اصلاح نیست. اگر تعویض زیاد است حداقل اختلاف پینگ لازم برای تعویض را بیشتر کن.');
  }
  if (has('سرعت واقعی صفر')) {
    return h('E-REAL-SPEED-ZERO-SWITCH',
        'app_main/main.dart → _measureCurrent (lastWhy = \'سرعت واقعی صفر بود\' → _failover)',
        'بعد از اتصال دانلود تست هیچ داده‌ای نیاورد، یعنی سرور پینگ داشت ولی داده نمی‌داد و عوض شد.',
        'رفتار درست است. اگر برای همه‌ی سرورها رخ داد آدرس تست سرعت را چک کن.');
  }
  if (has('شمارنده‌ی')) {
    return h('E-COUNTER-UP',
        'تشخیص: app_main/main.dart → _inspect (شمارنده‌های واچ‌داگ)',
        'یکی از شمارنده‌های واچ‌داگ (پینگ‌ناموفق، کندی، بدون‌داده...) به ۲ یا بیشتر رسید. اطلاعاتی است؛ اگر به حد مجاز برسد تعویض سرور خودکار انجام می‌شود.',
        'نیازی به اقدام نیست. فقط اگر همراه قطع‌های زیاد بود watchFailLimit را بیشتر کن.');
  }
  if (has('پینگ ناموفق')) {
    return h('E-PING-FAIL',
        'app_main/main.dart → _startWatch (انتها: fails >= watchFailLimit → _failover)',
        'تست اینترنت از تونل چند بار پشت‌سرهم جواب نداد؛ متن خطا داخل پرانتز همین پیام است (lastPingErr).',
        'اگر روی سرورهای سالم هم تکرار می‌شود watchFailLimit را بیشتر کن یا آدرس تست در pingAny را عوض کن.');
  }
  if (has('سرور بهتر')) {
    return h('E-BETTER-SERVER',
        'app_main/main.dart → _startWatch / _swapTo (تعویض به سرور آماده با پینگ کمتر؛ patch_fast.py → lastWhy = \'سرور بهتر\')',
        'اتصال سالم بود ولی در صف آماده سروری با پینگ خیلی کمتر پیدا شد و برنامه عمداً به آن رفت. خطا نیست؛ فقط ثبت علت تعویض است.',
        'نیازی به اصلاح نیست. اگر تعویض زیاد است حداقل اختلاف پینگ لازم برای «سرور بهتر» را بیشتر کن.');
  }
  if (has('قطع جریان')) {
    return h('E-DATA-STALL',
        'app_main/main.dart → _startWatch (stallRun >= 2؛ patch_speedswitch.py → lastWhy = \'قطع جریان داده\')',
        'دو بار پشت‌سرهم دانلود کوچک از تونل زیر ۱۰۰ KB/s بود (تقریباً قطع)، با وجود اینکه پینگ جواب می‌داد؛ سرور آماده‌ای وجود داشت و سرور عوض شد.',
        'رفتار درست است. اگر روی سرورهای خوب هم زیاد رخ می‌دهد smallSpeedUrl را عوض کن یا آستانه‌ی ۱۰۰ KB/s و stallRun >= 2 را در patch_speedswitch.py بیشتر کن.');
  }
  if (has('سایت‌ها باز نمی')) {
    return h('E-SITES-DEAD',
        'app_main/main.dart → _startWatch (siteFail >= 2؛ patch_speedswitch.py → _sitesOpen)',
        'قبلاً یوتیوب/اینستاگرام/تلگرام از این سرور باز می‌شدند و حالا دو بار پشت‌سرهم هیچ‌کدام باز نشد.',
        'رفتار درست است؛ اگر همه‌ی سرورها همین‌طورند شبکه‌ی گوشی مشکل دارد.');
  }
  if (has('همگام‌سازی خودکار')) {
    return h('E-SELFHEAL',
        'app_main/main.dart → _syncCore / _inspect (خودترمیمی)',
        'برنامه یک حالت گیرکرده را خودش اصلاح کرد (واچ‌داگ آزاد/روشن شد یا هسته و اپ هماهنگ شدند).',
        'نیازی به اقدام نیست؛ فقط اگر عدد «بار» خیلی بالاست متن و ساعت‌ها را برای Claude بفرست.');
  }
  if (has('سرعت پایین')) {
    return h('E-LOW-SPEED-SWITCH',
        'app_main/main.dart → _startWatch (lowSpeed >= 2 و _ready() > 0 → _failover)',
        'سرعت چهار بار پشت‌سرهم (≈۶۰ ثانیه) زیر minSpeedKB بود و سرور آماده وجود داشت.',
        'اگر باز هم زیاد تعویض می‌شود minSpeedKB را کم کن (autotune آن را از سرعت واقعی شبکه تنظیم می‌کند).');
  }
  if (has('پینگ بد')) {
    return h('E-BAD-PING-SWITCH',
        'app_main/main.dart → _startWatch (badPingRun >= badPingLimit → _bestPingStandby → _swapTo)',
        'پینگ سرور فعلی بد بود و سرور آماده‌ای با پینگ بهتر وجود داشت.',
        'اگر زیاد تعویض می‌شود badPingMs یا badPingLimit را بیشتر کن.');
  }
  if (has('هسته/اندروید')) {
    return h('E-CORE-DROP',
        'app_main/main.dart → شنونده‌ی هسته در initState (dropTimer ۲ ثانیه → _failover)',
        'هسته یا اندروید خودش اتصال را قطع کرد (بسته شدن سرویس VPN، قطع شبکه، کم‌حافظه).',
        'بهینه‌سازی باتری برای اپ خاموش باشد. اگر مکرر است لاگ «هسته: ...» همین گزارش را ببین.');
  }

  // ---- start / connect failures (lastFail, patch_pinglog.py) ----
  if (has('رد نشد')) {
    return h('E-PING-THROUGH',
        'app_main/main.dart → _connectLoop (بعد از _start موفق)؛ خط را patch_pinglog.py می‌نویسد',
        'هسته CONNECTED شد ولی ping از داخل تونل (۷ثانیه، دو بار) جواب نگرفت: سرور فیلتر، یا مسیر/DNS، یا برنامه‌های ردشده از VPN.',
        'متن «خطا:» همین خط را ببین: timeout = سرور خراب. اگر همه‌ی سرورها همین‌طورند آدرس pingAny و iranRoute را بررسی کن.');
  }
  if (has('تونل VPN')) {
    return h('E-NO-TUN',
        'app_main/main.dart → tunUp() و شاخه‌ی Tunnel guard در _startWatch؛ شکست شروع در _start (lastFail)',
        'NetworkInterface.list() اینترفیسی با نام tun/ppp ندید (نام‌های دیده‌شده در خط «tun:» بالا آمده). یعنی اندروید تونل نساخت یا با نام دیگری ساخته، یا مجوز VPN دست اپ دیگری است. آیکن کلید نمی‌آید.',
        'نام اینترفیس‌های خط «tun:» را ببین؛ اگر نام دیگری دارد شرط startsWith در tunUp() را گسترش بده. اگر هیچ نیست: _restartTunnel (خودکار تا ۲ بار) و بعد درخواست مجوز VPN.');
  }
  if (has('CONNECTED نرسید')) {
    return h('E-START-CORE',
        'app_main/main.dart → _start (connSig با ۱۰ ثانیه timeout؛ lastFail)',
        'هسته CONNECTED نشد: کانفیگ را هسته نپذیرفت یا در CONNECTING گیر کرد.',
        'اگر برای همه‌ی سرورها رخ می‌دهد نسخه‌ی flutter_v2ray و patch_v2ray_core.py را چک کن؛ وگرنه فقط کانفیگ آن سرور خراب است.');
  }
  if (has('پورت پروکسی')) {
    return h('E-START-PORT',
        'app_main/main.dart → _start (waitProxyPort ۸ ثانیه در حالت پروکسی)',
        'هسته بالا نیامد و پورت پروکسی محلی باز نشد.',
        'در حالت پروکسی مهلت waitProxyPort را بیشتر کن یا به E-START-CORE نگاه کن.');
  }
  if (has('مجوز VPN')) {
    return h('E-START-PERM',
        'app_main/main.dart → _start (v2ray.requestPermission)',
        'کاربر مجوز VPN اندروید را نداد یا پنجره‌ی مجوز بسته شد.',
        'عادی است؛ دوباره «اتصال» را بزن و روی «OK» بزن.');
  }
  if (has('OpenVPN')) {
    return h('E-START-OVPN',
        'app_main/main.dart → _startOvpn',
        'OpenVPN به حالت connected نرسید.',
        'OpenVPN در این برنامه حذف‌شدنی است؛ اگر استفاده نمی‌شود نادیده بگیر.');
  }

  // ---- search / connect results ----
  if (has('سرور سالمی پیدا نشد')) {
    return h('E-NO-HEALTHY',
        'app_main/main.dart → _findGood (انتها: logError وقتی هیچ سرور سالمی پیدا نشد) و _doConnect (پیام ردیف)',
        'کل صف تست شد ولی هیچ سروری رد نشد: منبع‌های مرده/فیلتر، تست سریع خیلی سخت، delayTimeout کم، یا اینترنت ضعیف گوشی.',
        'در خلاصه‌ی گزارش «تست سریع X/Y موفق» را ببین؛ اگر نزدیک صفر است delayTimeout را بیشتر کن یا fastDelay را خاموش کن؛ منبع‌های مرده را از لیست منبع‌ها حذف کن.');
  }
  if (has('هیچ سروری')) {
    return h('E-NO-CONNECT',
        'app_main/main.dart → _doConnect (else بعد از _acquire / _connectLoop)',
        'همه‌ی سرورها در _start یا پینگ از تونل رد شدند. دلیل دقیق در خطوط «اتصال:» همین گزارش است.',
        'اول کدهای E-NO-TUN / E-PING-THROUGH / E-START-CORE را درست کن؛ این فقط نتیجه‌ی آنهاست.');
  }
  if (has('جایگزین پیدا نشد')) {
    return h('E-NO-REPLACEMENT',
        'app_main/main.dart → _failover / _swapTo (_acquire برگرداند false)',
        'هنگام تعویض هیچ سرور آماده‌ای نبود و جستجوی فوری هم چیزی پیدا نکرد.',
        'جستجوی پس‌زمینه را روشن نگه دار تا همیشه سرور آماده باشد (E-NO-STANDBY).');
  }

  // ---- real exceptions: logError(e) ----
  if (m.startsWith('خطا:')) {
    if (has('FormatException')) {
      return h('E-ERR-FORMAT',
          'محل ثبت: بعد از «@» همین خط (تابع:شماره‌ی خط در main.dart پیوست Release)',
          'کانفیگ/JSON ناقص یا نامعتبر (Server.parse، parseFromURL، jsonDecode).',
          'آن سرور را نادیده بگیر؛ اگر برای همه رخ می‌دهد منبع لیست را عوض کن یا پاک کردن لیست سیاه + اتصال دوباره.');
    }
    if (has('PlatformException') || has('MissingPluginException')) {
      return h('E-ERR-PLATFORM',
          'محل ثبت: بعد از «@» همین خط',
          'خطای بخش native (هسته v2ray، OpenVPN یا کانال vpn/bg).',
          'اپ را کامل ببند و باز کن؛ مجوز VPN را یک‌بار از تنظیمات اندروید بده؛ اگر تکرار شد نسخه‌ی flutter_v2ray را بررسی کن.');
    }
    if (has('NoSuchMethodError') ||
        has('RangeError') ||
        has('type ') ||
        has('Null check')) {
      return h('E-ERR-BUG',
          'محل ثبت: بعد از «@» همین خط (تابع:شماره‌ی خط در main.dart پیوست Release)',
          'باگ کد (مقدار null، اندیس بیرون از لیست یا نوع اشتباه).',
          'اپ را ری‌استارت کن؛ اگر تکرار شد همان خط «@ تابع:شماره» را نگه دار تا در آپدیت بعدی همان نقطه فیکس شود.');
    }
    if (has('سرور سالمی پیدا نشد') || has('سرور سالم پیدا نشد')) {
      return h('E-NO-HEALTHY',
          'app_main/main.dart → _findGood / _search / _acquireInner',
          'کل صف تست شد ولی هیچ سروری سالم نبود (منبع مرده، تایم‌اوت کم، یا اینترنت ضعیف).',
          'چند ثانیه صبر کن و دوباره «اتصال» بزن؛ در تنظیمات تایم‌اوت را ۸–۱۲ث بگذار؛ لیست سیاه را پاک کن؛ وای‌فای/دیتا را یک‌بار قطع‌وصل کن.');
    }
    return h('E-ERR-OTHER',
        'محل ثبت: بعد از «@» همین خط (تابع:شماره‌ی خط در main.dart پیوست Release)',
        'استثنای غیرمنتظره در یکی از try/catch ها.',
        'اپ را ببند و باز کن؛ اگر همان خطا تکرار شد متن کامل خط را نگه دار. معمولاً با ری‌استارت یا تعویض سرور برطرف می‌شود.');
  }

  // ---- خلبان محلی ----
  if (has('خلبان محلی: switch_best') || has('خلبان') && has('switch_best')) {
    return h('E-PILOT-SWITCH',
        'lib/iran_ai_extras.dart → _localDecide / _localApply (switch_best)',
        'خلبان محلی تصمیم گرفت سرور را عوض کند (قبلاً با پروب اشتباه تلگرام هم این کار را می‌کرد).',
        'نسخه‌ی جدید: حداقل ۳ دقیقه بعد از وصل تعویض نمی‌کند اگر سرعت ≥۰.۲۵ MB/s باشد. اگر هنوز زود عوض می‌کند خلبان را خاموش کن یا صبر کن تا hold تمام شود.');
  }
  if (has('خلبان محلی: connect') || (has('خلبان') && has('connect'))) {
    return h('E-PILOT-CONNECT',
        'lib/iran_ai_extras.dart → _localApply (connect)',
        'خلبان محلی دستور اتصال زد چون قطع بودی یا wantVpn روشن بود.',
        'طبیعی است. اگر حلقه شد، خلبان را خاموش کن، لیست سیاه را پاک کن، دوباره اتصال بزن.');
  }
  if (has('خلبان محلی') || has('خلبان Pro') || has('King Pro')) {
    return h('E-PILOT-OTHER',
        'lib/iran_ai_extras.dart → localPilotTick / startLocalPilot',
        'رویداد مربوط به خلبان محلی (تحلیل/اقدام).',
        'اگر تعویض زیاد است خلبان را موقتاً خاموش کن؛ نسخه‌ی جدید روی اتصال پایدار تعویض نمی‌کند.');
  }

  // ---- پاک شدن لیست / جستجو ----
  if (has('پاک شد') || has('همه‌ی سرورهای پیداشده')) {
    return h('E-LIST-CLEARED',
        'app_main/main.dart → پاک‌کردن دستی یا ریست لیست توسط کاربر/خلبان',
        'لیست سرورهای پیدا‌شده خالی شد؛ باید دوباره جستجو شود.',
        'دکمه «اتصال» را بزن تا از نو لیست بگیرد و تست کند. اگر خودکار پاک می‌شود، خلبان/حالت شکست‌ناپذیر را چک کن.');
  }
  if (has('سرور سالم پیدا نشد') || has('تست سریع دوباره')) {
    return h('E-NO-HEALTHY-RETRY',
        'app_main/main.dart → _acquireInner (emptyRounds) / _findGood',
        'در آن دور هیچ سرور سالمی نبود؛ برنامه دوباره تست می‌کند.',
        'صبر کن تا دور بعدی تمام شود؛ اینترنت را چک کن؛ تایم‌اوت را بیشتر کن؛ لیست سیاه را پاک کن.');
  }
  if (has('توربو')) {
    return h('E-TURBO-INFO',
        'app_main/main.dart → _turboAfterConnect',
        'رویداد توربو سرعت بعد از اتصال (فعال‌سازی Mux / حذف Fragment).',
        'اگر پیام «توربو سرعت فعال • Mux» آمد یعنی موفق بوده. اگر بعدش قطع شد، به E-CORE-DROP نگاه کن نه توربو.');
  }
  if (has('خودترمیمی') || has('یتیم') || has('ORPHAN') || has('orphan')) {
    return h('E-ORPHAN',
        'app_main/main.dart → _startWatch / dropTimer',
        'میخواهم وصل باشم ولی چند ثانیه هیچ کار اتصال/تعویضی در جریان نبود؛ واچ‌داگ failover کرد.',
        'معمولاً خودش درست می‌شود. اگر تکرار شد یک‌بار قطع کن و دوباره وصل کن؛ بهینه‌سازی باتری اپ را خاموش کن.');
  }
  if (has('هسته/اندروید') || has('CORE-DROP') || has('هسته قطع')) {
    return h('E-CORE-DROP',
        'app_main/main.dart → شنونده‌ی onStatusChanged / dropTimer → _failover',
        'هسته یا اندروید سرویس VPN را بست (باتری، حافظه، یا تداخل VPN دیگر).',
        'بهینه‌سازی باتری این اپ را «بدون محدودیت» کن؛ VPNهای دیگر را ببند؛ اگر مکرر است گوشی را یک‌بار ری‌استارت کن.');
  }
  if (has('اپ وصل است ولی هسته') || has('APP-UP-CORE')) {
    return h('E-APP-UP-CORE-DOWN',
        'app_main/main.dart → _syncCore / onStatusChanged',
        'UI فکر می‌کرد وصل است ولی هسته DISCONNECTED بود؛ همگام‌سازی خودکار تعویض کرد.',
        'خودکار اصلاح می‌شود. اگر زیاد تکرار شد بهینه‌سازی باتری را خاموش کن و از تداخل VPN دیگر جلوگیری کن.');
  }
  if (has('CONNECTED نرسید') || has('START-CORE') || has('کانفیگ را هسته نپذیرفت')) {
    return h('E-START-CORE',
        'app_main/main.dart → _start (timeout وضعیت CONNECTED)',
        'هسته برای این کانفیگ به CONNECTED نرسید (کانفیگ بد یا بلاک).',
        'آن سرور رد می‌شود. اگر برای همه‌ی سرورهاست مجوز VPN و نسخه‌ی هسته را چک کن؛ وگرنه فقط آن کانفیگ خراب است.');
  }
  if (has('کانفیگ ناموفق') || has('CONFIG-FAIL')) {
    return h('E-CONFIG-FAIL',
        'app_main/main.dart → _connectLoop / _start',
        'این کانفیگ مشخصاً وصل نشد (پروتکل/آدرس/پورت/transport).',
        'سرور بعدی را امتحان کن؛ اگر path شامل proxyip است لینک استاندارد بگیر؛ شکست‌های هم‌نوع موقتاً در لیست سیاه می‌مانند.');
  }
  if (has('پورت هسته') || has('سایت‌چک') || has('چک سایت')) {
    return h('E-SITE-CHECK',
        'app_main/main.dart → چک سایت‌ها / ping از تونل',
        'تست سایت از داخل تونل کامل نشد (گاهی پورت HTTP هسته در حالت VPN بسته است).',
        'اگر سرعت واقعی و پینگ تونل OK است نادیده بگیر. نسخه‌ی جدید خلبان با سرعت واقعی تعویض نمی‌کند.');
  }
  if (has('علت تعویض:')) {
    return h('E-SWAP-REASON',
        'app_main/main.dart → _swapTo / _failover (ثبت علت)',
        'ثبت دلیل تعویض سرور (خلبان، هسته، پینگ، و غیره).',
        'متن بعد از «علت تعویض:» را بخوان؛ همان کد متناظر (E-PILOT / E-CORE-DROP / …) را اعمال کن. اگر علت خلبان بود و اتصال خوب بود، نسخه‌ی جدید hold سه‌دقیقه‌ای دارد.');
  }
  if (has('وضعیت:')) {
    return h('E-STATUS-INFO',
        'app_main/main.dart → dbgStatus / _set',
        'پیام وضعیت پیشرفت (جستجو، اتصال، توربو، …)؛ لزوماً خطا نیست.',
        'اگر فقط اطلاع‌رسانی است نادیده بگیر. اگر همراه قطعی مکرر است، کدهای E-CORE-DROP و E-PILOT-SWITCH را در همین گزارش ببین.');
  }

  // ---- fallback هوشمند: هرگز null برنگردان ----
  final where = has('@')
      ? 'محل ثبت: بعد از «@» در همین خط'
      : 'app_main/main.dart یا lib/iran_ai_extras.dart (لاگ عمومی)';
  var cause = 'رویداد ثبت‌شده در گزارش؛ الگوی از‌پیش‌تعریف‌شده نداشت.';
  var fix = 'اپ را یک‌بار قطع و وصل کن؛ اگر تکرار شد لیست سیاه را پاک کن و دوباره اتصال بزن.';
  if (has('قطع') || has('DISCONNECT')) {
    cause = 'قطع اتصال یا وضعیت DISCONNECTED ثبت شده.';
    fix = 'اگر عمدی نبوده: بهینه‌سازی باتری را خاموش کن و دوباره وصل شو. اگر هنگام تعویض است طبیعی است.';
  } else if (has('timeout') || has('Timeout') || has('تایم')) {
    cause = 'عملیات در زمان مشخص تمام نشد (شبکه کند یا سرور بی‌پاسخ).';
    fix = 'تایم‌اوت را در تنظیمات کمی بیشتر کن (۸–۱۲ث)؛ اینترنت پایدارتر امتحان کن.';
  } else if (has('DNS') || has('dns')) {
    cause = 'مشکل یا تأخیر در DNS.';
    fix = 'DNS امن (DoH) را در تنظیمات روشن نگه دار؛ یک‌بار حالت هواپیما را بزن و خاموش کن.';
  } else if (has('مجوز') || has('permission') || has('VPN')) {
    cause = 'مجوز VPN یا دسترسی سیستم.';
    fix = 'در تنظیمات اندروید → برنامه‌ها → این اپ → VPN/مجوزها را اجازه بده؛ یک‌بار دستی وصل کن.';
  } else if (has('باتری') || has('battery')) {
    cause = 'محدودیت باتری اندروید ممکن است سرویس VPN را بکشد.';
    fix = 'بهینه‌سازی باتری این اپ را «بدون محدودیت» یا «عدم بهینه‌سازی» بگذار.';
  } else if (has('جستجو') || has('صف') || has('لیست')) {
    cause = 'مربوط به جستجو یا صف سرورها.';
    fix = 'صبر کن تا جستجو تمام شود؛ اگر صف خالی است اتصال دوباره بزن تا لیست تازه بگیرد.';
  } else if (has('پینگ') || has('ping')) {
    cause = 'پینگ ناموفق یا بد.';
    fix = 'سرور دیگری انتخاب کن؛ اگر همه پینگ بد دارند اینترنت/اپراتور را چک کن.';
  } else if (has('Mux') || has('Fragment') || has('توربو')) {
    cause = 'تنظیمات throughput (Mux/Fragment/توربو).';
    fix = 'توربو را روشن و Fragment را خاموش نگه دار؛ بعد از پیام «توربو فعال» سرعت را بسنج.';
  }
  return h('E-GENERIC', where, cause, fix);
}

// the report section: every problem with where / cause / fix
String _dbgProbText() {
  final l = dbgProbs.values.toList()
    ..sort((a, b) => b.last.compareTo(a.last));
  var total = 0;
  for (final p in l) {
    total += p.n;
  }
  final b = StringBuffer(
      '== مشکل‌های پیدا شده (${l.length} نوع • $total بار) ==\n');
  b.write('تا «پاک کردن» نزنی همه می‌مانند؛ عدد جلوی هر مورد = تعداد کل بار (همه‌ی اجراها)\n');
  b.write('هر مورد کد + علت + راه حل دارد — نیازی به فرستادن برای AI نیست مگر باگ کد (E-ERR-BUG)\n');
  b.write('شماره‌ی خط‌ها: main.dart پیوست همین Release\n');
  if (l.isEmpty) b.write('هیچ مشکلی ثبت نشده\n');
  final shown = <String>{};
  var i = 0;
  for (final p in l) {
    i++;
    b.write('$i) ${p.msg} • اولین ${_dbgStamp(p.first)} • '
        'آخرین ${_dbgStamp(p.last)} • ${p.n} بار\n');
    final h = _dbgHelpOf(p.msg);
    // همیشه کد + محل + علت + راه حل کامل
    b.write('   کد: ${h[0]}\n');
    b.write('   📍 کجا: ${h[1]}\n');
    b.write('   🔎 علت: ${h[2]}\n');
    b.write('   🛠 راه حل: ${h[3]}\n');
    shown.add(h[0]);
  }
  b.write('====================');
  return b.toString();
}

// SELFHEALPATCH: problem list entry (code / where / cause / fix in the report)
void _shProb(String key, String msg) {
  try {
    final now = DateTime.now();
    final d = dbgProbs[key];
    if (d == null) {
      final x = DbgProb(msg, now);
      x.last = now;
      x.n = 1;
      dbgProbs[key] = x;
    } else {
      d.n++;
      d.last = now;
    }
    _dbgProbSave();
  } catch (_) {}
}

// SELFHEALPATCH: heavy json work in a separate isolate (no UI freeze)
String _shJsonIso(Object o) => jsonEncode(o);

Future<String> _shJson(Object o) async {
  try {
    return await compute(_shJsonIso, o);
  } catch (_) {
    return jsonEncode(o);
  }
}

// SWALLOWPATCH: every catch (_) is logged now (nothing is swallowed silently)
int _swCount = 0, _swSites = 0;
bool _swBusy = false;
final Map<String, DateTime> _swLogAt = <String, DateTime>{};

// function:line of the code that caught the error (real stack)
String _swSite() {
  try {
    final re = RegExp(r'#\d+\s+(.+?)\s+\(.*?(\w+\.dart):(\d+)');
    for (final ln in StackTrace.current.toString().split('\n')) {
      final mm = re.firstMatch(ln);
      if (mm == null) continue;
      final fn = mm.group(1) ?? '';
      final file = mm.group(2) ?? '';
      if (fn.contains('_swl') || fn.contains('_swSite')) continue;
      if (file != 'main.dart') continue;
      return '${fn.replaceAll('<anonymous closure>', 'fn')}:${mm.group(3)}';
    }
  } catch (_) {}
  return '';
}

void _swl(String site, Object e) {
  if (_swBusy) return;
  // QUIETPATCH: harmless errors are not listed
  if (e is SocketException ||
      e is TimeoutException ||
      e is HandshakeException ||
      e is TlsException ||
      e is HttpException) {
    dbgNet++;
    return;
  }
  if (e is FormatException) {
    final t = e.toString();
    if (t.contains('Invalid character') ||
        t.contains('extension byte') ||
        t.contains('UTF-8') ||
        t.contains('percent') ||
        t.contains('Invalid length')) {
      return;
    }
  }
  _swBusy = true;
  try {
    _swCount++;
    final key = 'swallow:$site:${e.runtimeType}';
    final now = DateTime.now();
    final last = _swLogAt[key];
    final first = last == null;
    final quiet =
        last != null && now.difference(last) < const Duration(seconds: 30);
    var msg = '';
    if (!quiet) {
      final raw = e.toString().replaceAll('\n', ' ');
      final txt = raw.length > 90 ? raw.substring(0, 90) : raw;
      final at = _swSite();
      msg = '🕳 خطای بلعیده‌شده در ${at.isEmpty ? site : at} • '
          '${e.runtimeType} • $txt';
    }
    if (msg.isNotEmpty || dbgProbs.containsKey(key)) {
      final d = dbgProbs[key];
      if (d == null) {
        final x = DbgProb(msg, now);
        x.last = now;
        x.n = 1;
        dbgProbs[key] = x;
      } else {
        d.n++;
        d.last = now;
      }
    }
    if (!quiet) {
      if (first) _swSites++;
      _swLogAt[key] = now;
      dbg(msg);
      _dbgProbSave();
    }
  } catch (_) {
  } finally {
    _swBusy = false;
  }
}

void dbg(String m) {
  try {
    if (!_dbgLoaded) {
      _dbgLoaded = true;
      _dbgLoadPrev();
    }
    final msg = m.length > 300 ? m.substring(0, 300) : m;
    _dbgProb(msg); // INSPECTORPATCH
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    if (dbgLines.isNotEmpty && dbgLines.last.endsWith('  $msg')) return;
    dbgLines.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $msg');
    if (dbgLines.length > 1500) {
      dbgLines.removeRange(0, dbgLines.length - 1500);
    }
    _dbgSaveT?.cancel();
    _dbgSaveT = Timer(const Duration(seconds: 2), () async {
      try {
        final p = await SharedPreferences.getInstance();
        final keep = dbgLines.length > 400
            ? dbgLines.sublist(dbgLines.length - 400)
            : List<String>.of(dbgLines);
        await p.setStringList('dbgLines', keep);
      } catch (_) {}
    });
  } catch (_) {}
}

// status texts: progress counters like "12/300" are kept at most once per
// 10 seconds (they show how fast the search goes)
DateTime _dbgProg = DateTime.fromMillisecondsSinceEpoch(0);
void dbgStatus(String s) {
  if (RegExp(r'\d+/\d+').hasMatch(s)) {
    final n = DateTime.now();
    if (n.difference(_dbgProg).inSeconds < 10) return;
    _dbgProg = n;
  }
  dbg('وضعیت: $s');
}

void dbgState(String st) {
  if (st == _dbgLastSt) return;
  _dbgLastSt = st;
  dbg('هسته: $st');
}

bool _isNoActivity(Object e) {
  final s = e.toString();
  return s.contains('NO_ACTIVITY') ||
      s.contains('Activity is not available');
}

void logError(Object e) {
  // NO_ACTIVITY is a transient Android race (no Activity for VPN dialog):
  // never paint it red on the home screen — just log quietly.
  if (_isNoActivity(e)) {
    dbg('مجوز VPN: Activity نبود (نادیده گرفته شد)${_dbgWhere()}');
    return;
  }
  if (e is TimeoutException ||
      e is SocketException ||
      e is HandshakeException ||
      e is HttpException ||
      e is http.ClientException) {
    dbgNet++;
  } else {
    dbg('خطا: ${e.runtimeType}: $e${_dbgWhere()}');
  }
  if (e is TimeoutException ||
      e is SocketException ||
      e is HandshakeException ||
      e is HttpException ||
      e is http.ClientException) {
    return;
  }
  errorLog.value = e.toString();
}

// Real-VPN config: keep the delay-test config as close as possible.
// Only ensure DNS + sniffing are sane. Under national mode we MUST preserve
// Iranian / operator DNS that the matrix found (overwriting with 1.1.1.1/8.8.8.8
// made many servers "CONNECTED" while no traffic passed on filtered networks).
String _reliableVpnCfg(String cfg) {
  try {
    final j = jsonDecode(cfg);
    if (j is! Map<String, dynamic>) return cfg;
    final d = j['dns'] is Map
        ? Map<String, dynamic>.from(j['dns'] as Map)
        : <String, dynamic>{};
    final existing = d['servers'];
    final hasServers = existing is List && existing.isNotEmpty;
    // National / ultra / indestructible: keep matrix DNS (often Iranian).
    // Normal mode: force a known-good global set so free servers resolve.
    if (!nationalMode && !ultraMode && !indestructibleMode) {
      d['servers'] = <dynamic>[
        '1.1.1.1',
        '8.8.8.8',
        '9.9.9.9',
        '1.0.0.1',
        'https://1.1.1.1/dns-query',
        'https://8.8.8.8/dns-query',
      ];
    } else if (!hasServers) {
      // National but config had no DNS: use Iranian-first fallback
      d['servers'] = <dynamic>[
        '178.22.122.100',
        '185.51.200.2',
        '78.157.42.100',
        '10.202.10.10',
        '1.1.1.1',
        '8.8.8.8',
        'https://1.1.1.1/dns-query',
      ];
    }
    // else: keep the matrix DNS untouched
    d['queryStrategy'] = 'UseIPv4';
    j['dns'] = d;
    final rt = j['routing'] is Map
        ? Map<String, dynamic>.from(j['routing'] as Map)
        : <String, dynamic>{};
    rt['domainStrategy'] = 'AsIs';
    j['routing'] = rt;
    // Keep local SOCKS/HTTP so post-connect social checks (TG/IG/YT) go through
    // the REAL core path — not the app's direct network (often bypasses VPN).
    var inbounds = j['inbounds'];
    if (inbounds is! List) {
      inbounds = <dynamic>[];
      j['inbounds'] = inbounds;
    }
    var hasHttp = false, hasSocks = false;
    for (final ib in inbounds) {
      if (ib is! Map) continue;
      final p = ib['port'];
      final proto = '${ib['protocol'] ?? ''}'.toLowerCase();
      if (p == httpProxyPort || p == 10809) hasHttp = true;
      if (p == 10808 || proto.contains('socks')) hasSocks = true;
      final sn = ib['sniffing'];
      if (sn is! Map || sn['enabled'] != true) {
        ib['sniffing'] = {
          'enabled': true,
          'destOverride': ['http', 'tls'],
          'routeOnly': true,
        };
      }
    }
    if (!hasSocks) {
      inbounds.add({
        'tag': 'socks-in',
        'listen': '127.0.0.1',
        'port': 10808,
        'protocol': 'socks',
        'settings': {'udp': true},
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls'],
          'routeOnly': true,
        },
      });
    }
    if (!hasHttp) {
      inbounds.add({
        'tag': 'http-in',
        'listen': '127.0.0.1',
        'port': httpProxyPort,
        'protocol': 'http',
        'settings': <String, dynamic>{},
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls'],
          'routeOnly': true,
        },
      });
    }
    return jsonEncode(j);
  } catch (e) {
    logError(e);
    return cfg;
  }
}

// completes when the VPN tunnel reports CONNECTED
Completer<bool>? connSig;
// جدید: completes when the V2Ray core really reports DISCONNECTED
Completer<bool>? downSig;
// completes when the OpenVPN engine reports connected
Completer<bool>? ovpnSig;

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (d) => logError(d.exception);
    // errors coming from native code / platform channels must never kill
    // the app
    WidgetsBinding.instance.platformDispatcher.onError = (e, st) {
      logError(e);
      return true;
    };
    runApp(MaterialApp(
      theme: uiTheme(),
      debugShowCheckedModeBanner: false,
      home:
          Directionality(textDirection: TextDirection.rtl, child: HomePage()),
    ));
    initBackground();
  }, (e, st) => logError(e));
}

// The old 15-minute background scan is gone: while the VPN is off nothing
// runs and no data is used. The dispatcher stays only so Workmanager can be
// initialised and the periodic task of old installs can be cancelled.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async => true);
}

Future<void> initBackground() async {
  try {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().cancelAll();
  } catch (e) {
    logError(e);
  }
}

const countryFa = {
  'US': 'آمریکا', 'DE': 'آلمان', 'NL': 'هلند', 'GB': 'انگلیس', 'FR': 'فرانسه',
  'CA': 'کانادا', 'SG': 'سنگاپور', 'JP': 'ژاپن', 'TR': 'ترکیه', 'FI': 'فنلاند',
  'SE': 'سوئد', 'CH': 'سوئیس', 'IT': 'ایتالیا', 'ES': 'اسپانیا', 'PL': 'لهستان',
  'RU': 'روسیه', 'UA': 'اوکراین', 'HK': 'هنگ‌کنگ', 'TW': 'تایوان',
  'KR': 'کره جنوبی', 'IN': 'هند', 'AE': 'امارات', 'AU': 'استرالیا',
  'BR': 'برزیل', 'RO': 'رومانی', 'BG': 'بلغارستان', 'CZ': 'چک', 'AT': 'اتریش',
  'NO': 'نروژ', 'DK': 'دانمارک', 'IE': 'ایرلند', 'IL': 'اسرائیل', 'LT': 'لیتوانی',
  'LV': 'لتونی', 'EE': 'استونی', 'HU': 'مجارستان', 'PT': 'پرتغال', 'GR': 'یونان',
  'CN': 'چین', 'KZ': 'قزاقستان', 'AM': 'ارمنستان', 'GE': 'گرجستان',
  'MD': 'مولداوی', 'RS': 'صربستان', 'BE': 'بلژیک', 'IR': 'ایران', 'MY': 'مالزی',
  'TH': 'تایلند', 'VN': 'ویتنام', 'ID': 'اندونزی', 'MX': 'مکزیک', 'AR': 'آرژانتین',
  'ZA': 'آفریقای جنوبی', 'IS': 'ایسلند', 'LU': 'لوکزامبورگ',
  'PH': 'فیلیپین', 'NZ': 'نیوزیلند', 'CL': 'شیلی', 'CO': 'کلمبیا',
  'PK': 'پاکستان', 'SA': 'عربستان', 'IQ': 'عراق', 'AZ': 'آذربایجان',
  'BY': 'بلاروس', 'SK': 'اسلواکی', 'SI': 'اسلوونی', 'HR': 'کرواسی',
  'BA': 'بوسنی', 'MK': 'مقدونیه', 'AL': 'آلبانی', 'CY': 'قبرس',
  'MT': 'مالت', 'EG': 'مصر', 'NG': 'نیجریه', 'KE': 'کنیا',
};

// Longer / more specific phrases preferred by length when matching
const countryWords = {
  'united states': 'US', 'united kingdom': 'GB', 'hong kong': 'HK',
  'south korea': 'KR', 'new zealand': 'NZ', 'saudi arabia': 'SA',
  'south africa': 'ZA', 'czech republic': 'CZ', 'united arab': 'AE',
  'germany': 'DE', 'deutschland': 'DE', 'netherlands': 'NL', 'holland': 'NL',
  'france': 'FR', 'finland': 'FI', 'singapore': 'SG', 'japan': 'JP',
  'turkey': 'TR', 'canada': 'CA', 'sweden': 'SE', 'russia': 'RU',
  'poland': 'PL', 'italy': 'IT', 'spain': 'ES', 'switzerland': 'CH',
  'austria': 'AT', 'australia': 'AU', 'brazil': 'BR', 'romania': 'RO',
  'bulgaria': 'BG', 'norway': 'NO', 'denmark': 'DK', 'ireland': 'IE',
  'israel': 'IL', 'lithuania': 'LT', 'latvia': 'LV', 'estonia': 'EE',
  'hungary': 'HU', 'portugal': 'PT', 'greece': 'GR', 'china': 'CN',
  'kazakhstan': 'KZ', 'armenia': 'AM', 'georgia': 'GE', 'moldova': 'MD',
  'serbia': 'RS', 'belgium': 'BE', 'iran': 'IR', 'malaysia': 'MY',
  'thailand': 'TH', 'vietnam': 'VN', 'indonesia': 'ID', 'mexico': 'MX',
  'argentina': 'AR', 'iceland': 'IS', 'luxembourg': 'LU', 'taiwan': 'TW',
  'ukraine': 'UA', 'india': 'IN', 'emirates': 'AE', 'philippines': 'PH',
  'pakistan': 'PK', 'azerbaijan': 'AZ', 'iraq': 'IQ', 'belarus': 'BY',
  'slovakia': 'SK', 'slovenia': 'SI', 'croatia': 'HR', 'cyprus': 'CY',
  'egypt': 'EG', 'america': 'US', 'england': 'GB', 'britain': 'GB',
  'korea': 'KR',
};

String flagOf(String c) {
  if (c.length != 2) return '🌐';
  final a = c.codeUnitAt(0), b = c.codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) return '🌐';
  return String.fromCharCodes([a - 65 + 0x1F1E6, b - 65 + 0x1F1E6]);
}

// country from the config name: flag emoji, ISO code, or country word
final RegExp _ccRe = RegExp(r'(?:^|[^\w])([A-Z]{2})(?:\s*[|\-_:.]|\s|$)');
String? detectCountry(String name) {
  // 1) flag emoji anywhere
  final r = name.runes.toList();
  for (var i = 0; i + 1 < r.length; i++) {
    if (r[i] >= 0x1F1E6 &&
        r[i] <= 0x1F1FF &&
        r[i + 1] >= 0x1F1E6 &&
        r[i + 1] <= 0x1F1FF) {
      final cc = String.fromCharCodes(
          [r[i] - 0x1F1E6 + 65, r[i + 1] - 0x1F1E6 + 65]);
      if (countryFa.containsKey(cc)) return cc;
    }
  }
  // 2) ISO codes like "DE |" / "US-" / " NL "
  for (final m in _ccRe.allMatches(name.toUpperCase())) {
    final cc = m.group(1);
    if (cc != null && countryFa.containsKey(cc)) return cc;
  }
  // 3) English names — longest match wins (avoids "korea" beating "south korea")
  final l = name.toLowerCase();
  String? best;
  var bestLen = 0;
  for (final e in countryWords.entries) {
    if (e.key.length > bestLen && l.contains(e.key)) {
      best = e.value;
      bestLen = e.key.length;
    }
  }
  return best;
}

// a broken %XX / UTF-8 sequence in a name must never throw
String _safeDecodeComp(String t) {
  try {
    return Uri.decodeComponent(t);
  } catch (_) {
    try {
      final out = <int>[];
      final u = utf8.encode(t);
      for (var i = 0; i < u.length; i++) {
        if (u[i] == 0x25 && i + 2 < u.length) {
          final v = int.tryParse(String.fromCharCodes([u[i + 1], u[i + 2]]),
              radix: 16);
          if (v != null) {
            out.add(v);
            i += 2;
            continue;
          }
        }
        out.add(u[i]);
      }
      return utf8.decode(out, allowMalformed: true);
    } catch (_) {
      return t;
    }
  }
}

class Server {
  final String link, name, host;
  final int port;
  int? ping;
  int svc = -1; // MULTICHK
  double? speed;
  DateTime? speedAt; // time of the last real speed test
  DateTime? badAt;
  int score = 0;
  int miss = 0; // consecutive failed re-checks (missLimit in a row -> removed)
  bool tls = false;
  String sni = '', net = 'tcp';
  String? country;
  String? src; // which list (URL) this server came from
  String? ipLink; // same config but connecting to a resolved IP
  bool ipTried = false;
  // OpenVPN: the full .ovpn text (null for every other protocol)
  String? ovpnConf;
  bool udp = false; // OpenVPN over UDP cannot be TCP-probed
  bool get ovpn => ovpnConf != null;
  String get useLink => ipLink ?? link;
  bool get isIp => InternetAddress.tryParse(host) != null;
  bool get reality => link.contains('security=reality');
  bool get cdn {
    if (ovpn) return false;
    final h = host.toLowerCase();
    if (h.endsWith('workers.dev') ||
        h.endsWith('pages.dev') ||
        h.contains('cloudflare')) {
      return true;
    }
    final p = h.split('.');
    if (p.length != 4) return false;
    final a = int.tryParse(p[0]) ?? 0, b = int.tryParse(p[1]) ?? 0;
    return (a == 104 && b >= 16 && b <= 31) ||
        (a == 172 && b >= 64 && b <= 71) ||
        (a == 162 && (b == 158 || b == 159)) ||
        (a == 188 && b == 114) ||
        (a == 141 && b == 101) ||
        (a == 108 && b == 162) ||
        (a == 103 && (b == 21 || b == 22));
  }

  bool geoTried = false;
  bool personal = false; // the user's own Cloudflare server
  bool? ai; // true = Gemini opens through this server, false = it does not
  DateTime? checkedAt; // last real test (standby re-check)
  Server(this.link, this.name, this.host, this.port) {
    country = detectCountry(name);
  }

  String get key => ovpn ? 'ovpn:$host:$port' : '$host:$port';

  static Server? parse(String link) {
    try {
      link = npvClean(link.trim());
      // pasted with extra text around it ("@channel vless://...")
      if (!_schemeRe.hasMatch(link)) {
        final m = _linkRe.firstMatch(link);
        if (m != null) {
          link = m.group(0)!;
        } else {
          final alt = npvNormalizeLink(link);
          if (alt == null) return null;
          link = alt;
        }
      }
      final l = link.toLowerCase();
      // OpenVPN: ovpn://<base64 of the .ovpn text>#<name>
      if (l.startsWith('ovpn://')) {
        final h = link.indexOf('#');
        final b = h < 0 ? link.substring(7) : link.substring(7, h);
        final nm = h < 0 ? '' : _safeDecodeComp(link.substring(h + 1));
        final cfg = utf8.decode(base64.decode(base64.normalize(b)),
            allowMalformed: true);
        final rm = RegExp(r'^\s*remote\s+(\S+)\s+(\d+)', multiLine: true)
            .firstMatch(cfg);
        if (rm == null) return null;
        final host = rm.group(1) ?? '';
        final port = int.tryParse(rm.group(2) ?? '') ?? 0;
        if (host.isEmpty || port <= 0 || port > 65535) return null;
        final pm =
            RegExp(r'^\s*proto\s+(\w+)', multiLine: true).firstMatch(cfg);
        final sv = Server(link, nm.isEmpty ? host : nm, host, port);
        sv.ovpnConf = cfg;
        sv.udp = (pm?.group(1) ?? 'udp').toLowerCase().startsWith('udp');
        sv.tls = true;
        sv.net = 'ovpn';
        return sv;
      }
      if (!(l.startsWith('vmess://') ||
          l.startsWith('vless://') ||
          l.startsWith('trojan://') ||
          l.startsWith('ss://'))) {
        return null;
      }
      if (l.startsWith('vmess://')) {
        var b = link.substring(8);
        b = b.padRight(b.length + (4 - b.length % 4) % 4, '=');
        dynamic j; // CLEANERR
        try {
          j = jsonDecode(utf8.decode(base64.decode(b)));
        } on FormatException {
          return null;
        }
        if (j is! Map) return null;
        final add = j['add']?.toString() ?? '';
        if (add.isEmpty) return null;
        final port = int.tryParse('${j['port']}') ?? 0;
        if (port <= 0 || port > 65535) return null;
        final sv = Server(
            link, j['ps']?.toString() ?? add, add, port);
        if (sv.port == 443) sv.score += 2;
        sv.tls = j['tls']?.toString() == 'tls';
        sv.sni = (j['sni'] ?? j['host'] ?? '').toString();
        sv.net = (j['net'] ?? 'tcp').toString();
        if (sv.tls) sv.score += 2;
        if (!sv.tls && sv.net == 'tcp') sv.score -= 4;
        return sv;
      }
      Uri? u0;
      try {
        u0 = Uri.parse(link);
      } on FormatException {
        return null; // QUIETPATCH: broken link, skipped quietly
      }
      final u = u0;
      if (u.host.isEmpty) return null;
      final sv = Server(
          link,
          u.fragment.isNotEmpty ? _safeDecodeComp(u.fragment) : u.host,
          u.host,
          u.port);
      if (sv.port == 443) sv.score += 2;
      final q = u.queryParameters;
      final sec = q['security'];
      sv.tls = sec == 'tls' ||
          sec == 'reality' ||
          (l.startsWith('trojan://') && sec != 'none');
      sv.sni = q['sni'] ?? q['host'] ?? '';
      sv.net = q['type'] ?? 'tcp';
      if (sv.tls) sv.score += 2;
      if (!sv.tls && sv.net == 'tcp') sv.score -= 4;
      // obviously broken configs are dropped here (no test is wasted on them)
      if (sv.port <= 0 || sv.port > 65535) return null;
      final h0 = sv.host.toLowerCase();
      if (h0 == 'localhost' || h0.startsWith('127.') || h0 == '0.0.0.0') {
        return null;
      }
      if (!l.startsWith('ss://') && u.userInfo.isEmpty) return null;
      if (sec == 'reality' && (q['pbk'] ?? '').isEmpty) return null;
      return sv;
    } catch (_swE) { _swl('parse#1', _swE);
      return null;
    }
  }
}

// a pasted .ovpn file (several lines with a "remote host port" line)
Server? ovpnFromText(String t, {String name = 'OpenVPN'}) {
  final cfg = t.trim();
  if (!RegExp(r'^\s*remote\s+\S+\s+\d+', multiLine: true).hasMatch(cfg)) {
    return null;
  }
  return Server.parse(
      'ovpn://${base64.encode(utf8.encode(cfg))}#${Uri.encodeComponent(name)}');
}

// OpenVPN servers from VPNGate (public list, updated every few minutes)
Future<List<Server>> fetchOvpn() async {
  if (true) return <Server>[];
  final tmp = <MapEntry<int, Server>>[];
  try {
    final r = await http
        .get(Uri.parse(vpngateUrl))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return [];
    for (final line in r.body.split(RegExp(r'[\r\n]+'))) {
      if (line.isEmpty || line.startsWith('*') || line.startsWith('#')) {
        continue;
      }
      final c = line.split(',');
      if (c.length < 15) continue;
      final cfg64 = c.last.trim();
      if (cfg64.length < 100) continue;
      final cc = c[6].trim().toUpperCase();
      final ip = c[1].trim();
      final flag = cc.length == 2 ? flagOf(cc) : '🌐';
      final s = Server.parse(
          'ovpn://$cfg64#${Uri.encodeComponent('$flag $cc | OpenVPN • $ip')}');
      if (s == null) continue;
      s.src = 'ovpn:vpngate';
      tmp.add(MapEntry(int.tryParse(c[2]) ?? 0, s));
    }
  } catch (e) {
    logError(e);
  }
  tmp.sort((a, b) => b.key.compareTo(a.key));
  return tmp.take(maxOvpn).map((e) => e.value).toList();
}

bool _privateIp(InternetAddress a) {
  if (a.isLoopback || a.isLinkLocal || a.isMulticast) return true;
  final b = a.rawAddress;
  if (b.length == 4) {
    if (b[0] == 10 || b[0] == 0) return true;
    if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
    if (b[0] == 192 && b[1] == 168) return true;
    if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) return true;
  }
  return false;
}

int byPing(Server a, Server b) {
  if (a.ping == null && b.ping == null) return 0;
  if (a.ping == null) return 1;
  if (b.ping == null) return -1;
  return a.ping!.compareTo(b.ping!);
}

int byScoreThenPing(Server a, Server b) {
  final c = b.score.compareTo(a.score);
  return c != 0 ? c : byPing(a, b);
}

int bySpeedThenPing(Server a, Server b) {
  final c = (b.speed ?? -1).compareTo(a.speed ?? -1);
  return c != 0 ? c : byPing(a, b);
}

Future<int?> probe(Server s) async {
  final sw = Stopwatch()..start();
  Socket? sock;
  try {
    sock = await Socket.connect(s.host, s.port, timeout: tcpTimeout);
    if (_privateIp(sock.remoteAddress)) {
      sock.destroy();
      return null;
    }
    final name = s.sni.isNotEmpty ? s.sni : s.host;
    if (s.tls && probeTls) {
      final sec = await SecureSocket.secure(sock,
              host: name, onBadCertificate: (_) => true)
          .timeout(tcpTimeout);
      sec.destroy();
    } else {
      sock.destroy();
    }
    sw.stop();
    return sw.elapsedMilliseconds;
  } catch (_swE) { _swl('probe#1', _swE);
    sock?.destroy();
    return null;
  }
}

Future<void> pool<T>(
    List<T> items, int workers, Future<void> Function(T) fn) async {
  // Safer index-based pool: a shared Iterator can theoretically skip an item
  // if two workers call moveNext before either yields (rare but possible under
  // heavy microtask pressure). An atomic index eliminates that.
  var next = 0;
  // UI-FREEZE FIX: 50 workers used to start in the same millisecond (50 config
  // builds + 50 native calls on the UI thread). Starts are staggered and each
  // worker gives the UI a chance to draw a frame between two items.
  Future<void> worker(int idx) async {
    if (workers > 8) {
      await Future<void>.delayed(Duration(milliseconds: (idx % 25) * 12));
    }
    var n = 0;
    while (true) {
      final i = next++;
      if (i >= items.length) break;
      try {
        await fn(items[i]);
      } catch (e) {
        logError(e); // one failing item must never stop the whole pool
      }
      if (workers > 8 && (++n % 2 == 0)) {
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
    }
  }

  await Future.wait(
      List.generate(min(workers, items.length), (i) => worker(i)));
}

// FIXTUNNEL: in VPN mode the core may have NO local HTTP port (10809), so a
// request sent to PROXY 127.0.0.1:10809 gets "Connection refused" even though
// the tunnel works. Check whether the port is really open; if it is closed
// and the VPN tunnel (tun0) is up, send the request normally (DIRECT): Android
// then routes it through the tunnel, which is the real path of other apps.
Future<bool> _coreProxyOpen() async {
  try {
    final k = await Socket.connect('127.0.0.1', httpProxyPort,
        timeout: const Duration(milliseconds: 300));
    k.destroy();
    return true;
  } catch (_swE) {
    return false;
  }
}

Future<bool> _useCoreProxy(bool wantProxy) async {
  if (proxyMode) return true;
  if (!wantProxy) return false;
  if (await _coreProxyOpen()) return true;
  // Port may appear a moment after CONNECTED (inbounds just bound)
  for (var i = 0; i < 8; i++) {
    await Future.delayed(const Duration(milliseconds: 200));
    if (await _coreProxyOpen()) return true;
  }
  // Still closed: still request PROXY so the check FAILS honestly
  // (DIRECT from this app often bypasses the VPN on Android → false "OK"
  // while Telegram/Instagram/YouTube stay blocked for the user).
  return true;
}

// direct = true: no local proxy port, the request goes through the VPN tunnel
// (in proxy mode there is no tunnel, so the local proxy port is used)
Future<double?> measure(
    {String url = speedUrl,
    Duration win = const Duration(milliseconds: 1500),
    Duration total = const Duration(seconds: 10),
    int maxBytes = 0,
    bool direct = false,
    bool viaCore = false}) async {
  // viaCore / default when VPN is up: always hit the core's local HTTP proxy
  // so we test the REAL outbound. DIRECT from the VPN app often bypasses the
  // tunnel on Android and gives false "OK" while Telegram/apps still hang.
  final useProxy = await _useCoreProxy(viaCore || !direct);
  final c = HttpClient()
    ..findProxy = ((_) =>
        useProxy ? 'PROXY 127.0.0.1:$httpProxyPort' : 'DIRECT')
    ..connectionTimeout = const Duration(seconds: 6);
  try {
    return await () async {
      final req = await c.getUrl(Uri.parse(url));
      final res = await req.close();
      var bytes = 0;
      final sw = Stopwatch()..start();
      await for (final chunk in res) {
        bytes += chunk.length;
        if (sw.elapsed >= win) break;
      }
      final secs = sw.elapsedMilliseconds / 1000;
      if (secs == 0 || bytes == 0) return null;
      return bytes / 1048576 / secs;
    }()
        .timeout(total);
  } catch (_swE) { _swl('measure#1', _swE);
    return null;
  } finally {
    c.close(force: true);
  }
}

String lastPingErr = '';

// SPEEDSWITCHPATCH: does a real site answer through the tunnel?
// (only the headers are read, then the connection is closed)
Future<bool> _siteOpens(String url, {bool viaCore = true}) async {
  // Default viaCore=true: verify through the core proxy (real tunnel path)
  final useProxy = await _useCoreProxy(viaCore);
  final c = HttpClient()
    ..findProxy = ((_) =>
        useProxy ? 'PROXY 127.0.0.1:$httpProxyPort' : 'DIRECT')
    ..connectionTimeout = const Duration(seconds: 6);
  try {
    final req =
        await c.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 7));
    final res = await req.close().timeout(const Duration(seconds: 7));
    return res.statusCode > 0;
  } catch (_swE) { _swl('_siteOpens#1', _swE);
    return false;
  } finally {
    c.close(force: true);
  }
}

Future<int> _sitesOpen() async {
  // اگر پورت پروکسی هسته آماده نیست، تست را بی‌اعتبار بدان
  // (قبلاً باعث تعویض الکی «سایت‌ها باز نمی‌شوند» می‌شد)
  try {
    final ready = await waitProxyPort(max: const Duration(seconds: 2));
    if (!ready) return -1; // نامعتبر — نباید باعث تعویض شود
  } catch (_) {
    return -1;
  }
  final r = await Future.wait([
    _siteOpens('https://www.youtube.com/generate_204'),
    _siteOpens('https://www.instagram.com/'),
    _siteOpens('https://telegram.org/'),
  ]);
  return r.where((x) => x).length;
}

// the core needs a moment before the local proxy port accepts connections
Future<bool> waitProxyPort(
    {Duration max = const Duration(seconds: 6)}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < max) {
    try {
      final k = await Socket.connect('127.0.0.1', httpProxyPort,
          timeout: const Duration(milliseconds: 300));
      k.destroy();
      return true;
    } catch (_swE) { _swl('waitProxyPort#1', _swE);}
    await Future.delayed(const Duration(milliseconds: 250));
  }
  return false;
}

// Is the system VPN tunnel (tun0) really there? true = yes, false = the
// interface list works but has no tunnel, null = cannot tell on this phone.
// A "direct" ping also passes when NO tunnel exists (traffic just goes out
// normally), so without this check the app can say "connected" while the
// phone has no VPN key and other apps get nothing.
bool lastStartNoTunnel = false; // last _start failed because Android built no tunnel
String tunNames = ''; // interface names seen by the last tunUp() (diagnostics)
Future<bool?> tunUp() async {
  try {
    final l = await NetworkInterface.list();
    tunNames = l.map((i) => i.name).join(',');
    if (l.isEmpty) return null;
    return l.any((i) {
      final n = i.name.toLowerCase();
      // tun0, ppp0, wg0, vpn0, rmnet_data (some OEMs), and names containing these
      return n.startsWith('tun') ||
          n.startsWith('ppp') ||
          n.startsWith('wg') ||
          n.startsWith('vpn') ||
          n.startsWith('ipsec') ||
          n.startsWith('tap') ||
          n.contains('tun') ||
          n.contains('ppp') ||
          n.contains('vpn') ||
          n.contains('ipsec');
    });
  } catch (_swE) { _swl('tunUp#1', _swE);
    return null;
  }
}

// real ping: HTTP request to gstatic. direct = true: the request goes through
// the VPN tunnel (no local proxy port needed)
Future<int?> pingProxy(
    {Duration total = const Duration(seconds: 4),
    bool direct = false,
    bool viaCore = false,
    String url = delayTestUrl}) async {
  final useProxy = await _useCoreProxy(viaCore || !direct);
  final c = HttpClient()
    ..findProxy = ((_) =>
        useProxy ? 'PROXY 127.0.0.1:$httpProxyPort' : 'DIRECT')
    ..connectionTimeout = total;
  final sw = Stopwatch()..start();
  try {
    final req = await c.getUrl(Uri.parse(url)).timeout(total);
    final res = await req.close().timeout(total);
    await res.drain<void>();
    return sw.elapsedMilliseconds;
  } catch (e) {
    lastPingErr = e.toString();
    return null;
  } finally {
    c.close(force: true);
  }
}

// internet check through the tunnel with several URLs (the plain-http one
// first). One blocked / slow URL must not make a working server look dead.
Future<int?> pingAny(
    {Duration total = const Duration(seconds: 6),
    bool direct = true,
    int tries = 5,
    bool viaCore = true}) async {
  // تا ۵ آدرس مختلف — یکی کافی است که تونل سالم باشد
  final n = tries.clamp(1, _pingUrls.length);
  for (final u in _pingUrls.take(n)) {
    final p = await pingProxy(
        total: total, direct: direct, viaCore: viaCore, url: u);
    if (p != null) return p;
  }
  return null;
}

// Does Gemini REALLY work through the current tunnel? Two checks, both must pass:
//  1) the Gemini API location check (generativelanguage.googleapis.com):
//     an unsupported location gets "User location is not supported";
//     a supported one gets a normal "API key not valid" error
//  2) the Gemini web app opens (200, no "not supported" page / redirect)
// GEMFLAG: true when the LAST Gemini check got a clear "not supported here"
// answer from Google (no point in retrying), false when it was only a network
// problem (worth one more try)
bool gemDefinite = false;

// exit countries where Gemini is never available: skipped without a test
const _gemBlockedCc = {
  'IR', 'CN', 'RU', 'KP', 'CU', 'SY', 'BY', 'MM', 'AF', 'SD', 'SS', 'VE', 'HK', 'MO',
};
bool _gemSkip(Server s) {
  final c = (s.country ?? '').toUpperCase();
  return c.isNotEmpty && _gemBlockedCc.contains(c);
}

Future<bool> _geminiApiOk({bool direct = true}) async {
  final c = HttpClient()
    ..findProxy = ((_) =>
        (direct && !proxyMode) ? 'DIRECT' : 'PROXY 127.0.0.1:$httpProxyPort')
    ..connectionTimeout = const Duration(seconds: 5);
  try {
    return await () async {
      final req = await c.getUrl(Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models?key=location_check'));
      req.headers.set('accept-language', 'en-US,en;q=0.9');
      final res = await req.close();
      final sb = StringBuffer();
      await for (final chunk
          in res.transform(const Utf8Decoder(allowMalformed: true))) {
        sb.write(chunk);
        if (sb.length > 20000) break;
      }
      final b = sb.toString().toLowerCase();
      if (b.contains('location is not supported') ||
          b.contains('not supported for the api use') ||
          b.contains('not available in your')) {
        gemDefinite = true;
        return false;
      }
      // reached Google and got a normal JSON error / answer about the key
      return res.statusCode == 400 ||
          res.statusCode == 403 ||
          res.statusCode == 200;
    }()
        .timeout(const Duration(seconds: 10));
  } catch (_swE) { _swl('_geminiApiOk#1', _swE);
    return false;
  } finally {
    c.close(force: true);
  }
}

Future<bool> _geminiWebOk({bool direct = true}) async {
  final c = HttpClient()
    ..findProxy = ((_) =>
        (direct && !proxyMode) ? 'DIRECT' : 'PROXY 127.0.0.1:$httpProxyPort')
    ..connectionTimeout = const Duration(seconds: 5);
  try {
    return await () async {
      final req = await c.getUrl(Uri.parse('https://gemini.google.com/app'));
      req.headers.set('user-agent',
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36');
      req.headers.set('accept-language', 'en-US,en;q=0.9');
      final res = await req.close();
      if (res.statusCode != 200) return false;
      if (res.redirects.any((r) {
        final l = r.location.toString().toLowerCase();
        return l.contains('/faq') || l.contains('unsupported');
      })) {
        gemDefinite = true;
        return false;
      }
      final sb = StringBuffer();
      await for (final chunk
          in res.transform(const Utf8Decoder(allowMalformed: true))) {
        sb.write(chunk);
        if (sb.length > 200000) break;
      }
      final b = sb.toString().toLowerCase();
      if (!b.contains('gemini')) return false;
      const bad = [
        "isn't supported in your country",
        'not supported in your country',
        "isn't available in your country",
        'not available in your country',
        'not available in your region',
      ];
      if (bad.any(b.contains)) {
        gemDefinite = true;
        return false;
      }
      return true;
    }()
        .timeout(const Duration(seconds: 12));
  } catch (_swE) { _swl('_geminiWebOk#1', _swE);
    return false;
  } finally {
    c.close(force: true);
  }
}

Future<bool> geminiOpens({bool direct = true}) async {
  gemDefinite = false;
  // with the user's real API key the answer is exact: 200 = works,
  // "location not supported" = does not
  if (geminiKey.isNotEmpty) {
    final st = await geminiApiStatus(direct: direct);
    if (st != null) return st;
  }
  // otherwise: API location check first (cheap), then the web app
  if (!await _geminiApiOk(direct: direct)) return false;
  return _geminiWebOk(direct: direct);
}

String buildPersonalLink(String host, String uuid) {
  final h = host.trim().replaceAll(RegExp(r'^https?://'), '').split('/').first;
  return 'vless://${uuid.trim()}@$h:443?encryption=none&security=tls'
      '&sni=$h&fp=chrome&type=ws&host=$h&path=%2F%3Fed%3D2048'
      '#${Uri.encodeComponent('🏠 سرور شخصی')}';
}

// how to build the personal server (word by word)
const personalGuide = <String>[
  'مرورگر گوشی را باز کن و برو به آدرس: dash.cloudflare.com',
  'روی دکمه Sign up بزن. ایمیل خودت و یک رمز عبور (حداقل ۸ حرف) بنویس و دوباره Sign up را بزن.',
  'ایمیلت را باز کن. ایمیلی از Cloudflare آمده؛ روی Verify email بزن تا حساب تأیید شود.',
  'دوباره به dash.cloudflare.com برو و با Log in وارد شو. اگر درباره «دامنه» (Add a domain) پرسید، لازم نیست؛ رد کن (Skip).',
  'در منوی سمت چپ روی Workers & Pages بزن (در بعضی نسخه‌ها زیر Compute یا Workers است). اگر منو بسته بود، آیکن ☰ بالای صفحه را بزن.',
  'روی Create (یا Create application) بزن، بعد Create Worker (یا Start with Hello World). بار اول از تو یک «subdomain» می‌خواهد؛ یک اسم انگلیسی دلخواه بنویس (مثلاً اسم خودت).',
  'برای ورکر یک اسم انگلیسی بنویس: فقط حروف کوچک، عدد و خط تیره، مثلاً my-vpn. بعد Deploy را بزن.',
  'بعد از Deploy روی Edit code بزن تا ویرایشگر کد باز شود.',
  'همه‌ی کدی که داخل ویرایشگر هست را پاک کن (انگشت را روی کد نگه دار → Select all → Delete).',
  'اسکریپت ورکر VLESS را بگیر: در GitHub عبارت edgetunnel یا cf-worker-vless را جستجو کن، فایل _worker.js (یا worker.js) را باز کن، دکمه Raw را بزن، همه‌ی متن را کپی کن و داخل ویرایشگر Cloudflare در جای کد قبلی Paste کن.',
  'در ابتدای کد خطی مثل let userID = \'...\' هست. یک UUID بساز (سایت uuidgenerator.net → Generate) و به‌جای مقدار داخل کوتیشن بگذار. این UUID را جایی ذخیره کن؛ بعداً در برنامه لازم است.',
  'دکمه Deploy (بالا سمت راست) را بزن. اگر خطایی نداد، ورکر آماده است.',
  'آدرس ورکر را کپی کن. شکلش این است: my-vpn.اسم-تو.workers.dev (در صفحه‌ی ورکر، زیر عنوان یا بخش Domains & Routes).',
  'برگرد به برنامه، روی ⚙ سرور شخصی بزن. آدرس ورکر و UUID را بنویس. (اختیاری: مدت اعتبار به روز). ذخیره را بزن.',
  'حالا روی خط «سرور شخصی» بزن تا وصل شود.',
  'نکته‌ی حجم: پلن رایگان Cloudflare روزی ۱۰۰ هزار درخواست دارد. وقتی پر شود برنامه پیام «حجم تمام شده» می‌دهد. ساعت ۰۰:۰۰ UTC (حدود ۰۳:۳۰ بامداد ایران) دوباره پر می‌شود.',
];

// ---------- free providers for the personal server ----------
// kind: 'time' = account with a validity period, 'volume' = limited data,
// 'own' = you build your own permanent server, 'ovpn' = OpenVPN config,
// 'wg' = WireGuard (guide only, this app cannot connect it)
class FreeProvider {
  final String name, kind, badge, volume, url;
  final int days; // validity in days (0 = no expiry)
  final List<String> steps, notes;
  const FreeProvider(this.name, this.kind, this.badge, this.volume, this.days,
      this.url, this.steps, this.notes);
}

const freeProviders = <FreeProvider>[
  FreeProvider(
    'FreeVMess',
    'time',
    '۳ روز',
    'در سایت ذکر نشده',
    3,
    'https://www.freevmess.com/server-v2ray',
    [
      'دکمه «باز کردن سایت» را بزن.',
      'از لیست کشورها سروری را انتخاب کن که کنارش Online نوشته (سرور Offline کار نمی‌کند).',
      'روی Create v2ray account بزن.',
      'فرم را پر کن (نام کاربری و در صورت درخواست کپچا) و ساخت را بزن.',
      'کانفیگ ساخته‌شده (لینک vmess://) را کپی کن.',
      'به برنامه برگرد و دکمه «ثبت در برنامه» را بزن، لینک را Paste کن.',
    ],
    [
      'اعتبار هر حساب طبق سایت ۳ روز است.',
      'وضعیت سرورها (Online/Offline) در سایت مدام عوض می‌شود.',
    ],
  ),
  FreeProvider(
    'VPN Jantit',
    'time',
    '۷ روز',
    'نامحدود (طبق ادعای سایت)',
    7,
    'https://www.vpnjantit.com/free-v2ray-vless',
    [
      'دکمه «باز کردن سایت» را بزن (صفحه‌ی VLESS؛ در همان سایت VMess و Trojan هم هست).',
      'کشور و سرور دلخواه را انتخاب کن (جلوی سرور باید Available نوشته باشد).',
      'نام کاربری فقط با حروف انگلیسی و عدد بنویس، مثلاً myvpn123.',
      'دکمه CREATE ACCOUNT را بزن و چند لحظه صبر کن.',
      'لینک ساخته‌شده را کپی کن (پورت tls یا ws).',
      'به برنامه برگرد، «ثبت در برنامه» را بزن و لینک را Paste کن.',
    ],
    [
      'طبق سایت اعتبار تا ۷ روز و پهنای باند نامحدود است.',
      'سایت می‌گوید ظرفیت ساخت حساب رایگان هر روز ساعت ۲۱:۰۰ به وقت GMT+7 (حدود ۱۷:۳۰ ایران) ریست می‌شود؛ اگر ظرفیت پر بود، بعداً امتحان کن.',
    ],
  ),
  FreeProvider(
    'HideSSH',
    'time',
    '۷ روز',
    'نامحدود (طبق ادعای سایت)',
    7,
    'https://hidessh.com/create/sg2-venus',
    [
      'دکمه «باز کردن سایت» را بزن (سرور سنگاپور SG2 Venus؛ سرورهای دیگر هم در سایت هست).',
      'نام کاربری ۳ تا ۲۰ حرف بنویس.',
      'رمز عبور بیشتر از ۶ حرف (حروف و عدد) بنویس.',
      'کپچا را تأیید کن و Create را بزن؛ حدود ۱۰ ثانیه صبر کن.',
      'کانفیگ vmess را کپی کن (روش اتصال: Websocket یا GRPC، پورت TLS ۴۴۳).',
      'به برنامه برگرد، «ثبت در برنامه» را بزن و لینک را Paste کن.',
    ],
    [
      'اعتبار ۷ روز. تعداد حساب باقی‌مانده هر سرور در سایت نوشته شده.',
      'سایت می‌نویسد محدودیت ۱ حساب (Limit 1) دارد.',
    ],
  ),
  FreeProvider(
    'GreenSSH',
    'time',
    '۷ روز',
    'در سایت ذکر نشده',
    7,
    'https://greenssh.com/v2ray-vless',
    [
      'دکمه «باز کردن سایت» را بزن (VLESS؛ VMess هم همان‌جا هست).',
      'کشور سرور را انتخاب کن.',
      'روی Create Account بزن و فرم را پر کن.',
      'کانفیگ ساخته‌شده را کپی کن.',
      'به برنامه برگرد، «ثبت در برنامه» را بزن و لینک را Paste کن.',
    ],
    [
      'اعتبار حساب طبق سایت ۷ روز است.',
    ],
  ),
  FreeProvider(
    'SSHMax',
    'time',
    '۷ روز',
    'در سایت ذکر نشده',
    7,
    'https://sshmax.net/v2ray-vless/united-states/us1',
    [
      'دکمه «باز کردن سایت» را بزن (سرور آمریکا US1؛ کشورهای دیگر هم هست).',
      'نام کاربری فقط حروف و عدد بنویس (VLESS حداقل ۳ حرف، VMess بین ۳ تا ۸ حرف).',
      'ساخت حساب را بزن.',
      'کانفیگ را کپی کن.',
      'به برنامه برگرد، «ثبت در برنامه» را بزن و لینک را Paste کن.',
    ],
    [
      'اعتبار ۷ روز.',
      'طبق قوانین سایت تورنت و حمله ممنوع است.',
    ],
  ),
  FreeProvider(
    'DewaSSH',
    'time',
    '۳۰ روز',
    'در سایت ذکر نشده',
    30,
    'https://dewassh.net/server/V2Ray/419',
    [
      'دکمه «باز کردن سایت» را بزن (سرور سنگاپور).',
      'نام کاربری ۳ تا ۱۰ حرف و فقط حروف (عدد مجاز نیست).',
      'رمز عبور بیشتر از ۵ حرف.',
      'کپچا را درست وارد کن و Create بزن.',
      'کانفیگ را کپی کن (پورت TLS ۴۴۳، غیر TLS ۸۰).',
      'به برنامه برگرد، «ثبت در برنامه» را بزن و لینک را Paste کن.',
    ],
    [
      'اعتبار هر حساب ۳۰ روز، فقط ۱ دستگاه همزمان.',
      'سرعت سرور طبق سایت ۱ گیگابیت است.',
    ],
  ),
  FreeProvider(
    'SSHKit',
    'time',
    '۳۰ روز (اطلاعات قدیمی)',
    'در سایت ذکر نشده',
    30,
    'https://www.sshkit.com',
    [
      'قبل از شروع، در تلگرام برای خودت یک Username بساز (بدون آن ثبت‌نام نمی‌شود).',
      'دکمه «باز کردن سایت» را بزن و از منو V2ray Account را انتخاب کن.',
      'سرور دلخواه را انتخاب کن.',
      'با تلگرام وارد شو: شماره‌ی تلگرامت را بنویس و NEXT بزن.',
      'در تلگرام پیام ربات SSH Kit می‌آید؛ Confirm را بزن.',
      'صفحه خودش رفرش می‌شود؛ حساب V2ray را بساز و کانفیگ را کپی کن.',
      'به برنامه برگرد، «ثبت در برنامه» را بزن و لینک را Paste کن.',
    ],
    [
      'این مراحل از یک آموزش قدیمی است؛ ممکن است سایت تغییر کرده باشد.',
      'مدت ۳۰ روز هم طبق همان آموزش است؛ قبل از ساخت در سایت چک کن.',
    ],
  ),
  FreeProvider(
    'VPN Server Hub',
    'volume',
    '۲۴ ساعت (۳ بار در روز)',
    'تا ۲۵ گیگ (با اپ رسمی)',
    1,
    'https://vpnserverhub.com/free-v2ray',
    [
      'دکمه «باز کردن سایت» را بزن.',
      'نوع کانفیگ را انتخاب کن: VLESS، VMess یا Trojan.',
      'دکمه ساخت (Generate) را بزن و کانفیگ را کپی کن.',
      'به برنامه برگرد، «ثبت در برنامه» را بزن و لینک را Paste کن.',
      'برای مدت و حجم بیشتر: سایت می‌گوید با ثبت‌نام در داشبورد، پلن رایگان ۳۰ روزه و با اپ رسمی‌شان ۲۵ گیگ حجم رایگان می‌دهد.',
    ],
    [
      'هر کانفیگ سایت دقیقاً ۲۴ ساعت اعتبار دارد.',
      'سقف ساخت: ۳ کانفیگ در روز؛ بعدش باید فردا بیایی یا اپ رسمی را نصب کنی.',
    ],
  ),
  // ---------------- OpenVPN ----------------
  FreeProvider(
    'VPNGate (OpenVPN)',
    'ovpn',
    'مداوم به‌روز',
    'نامحدود (سرورهای داوطلبان)',
    0,
    'https://www.vpngate.net/en/',
    [
      'نکته: خود برنامه لیست VPNGate را خودکار می‌گیرد و در ردیف «OpenVPN» نشان می‌دهد؛ این مراحل فقط برای وقتی است که یک سرور مشخص می‌خواهی.',
      'دکمه «باز کردن سایت» را بزن.',
      'در جدول سرورها، سروری با Score بالا و کشور دلخواه را انتخاب کن (ستون OpenVPN باید دکمه داشته باشد).',
      'روی دکمه‌ی «OpenVPN Config file» آن سرور بزن و فایل .ovpn را دانلود کن.',
      'فایل را با یک برنامه‌ی متن‌خوان (یا File Manager → Open as text) باز کن، همه‌ی متن را Select all و Copy کن.',
      'به برنامه برگرد، «ثبت در برنامه» را بزن و متن کامل را داخل کادر «لینک کامل یا متن OpenVPN» Paste کن، ذخیره را بزن.',
    ],
    [
      'سرورها را داوطلبان می‌دهند؛ سرعت و ماندگاری‌شان متفاوت است.',
      'سایت ممکن است در بعضی شبکه‌ها فیلتر باشد؛ اگر باز نشد با یک سرور v2ray وصل شو و دوباره بزن.',
    ],
  ),
  FreeProvider(
    'VPN Jantit (OpenVPN)',
    'ovpn',
    '۷ روز',
    'نامحدود (طبق ادعای سایت)',
    7,
    'https://www.vpnjantit.com',
    [
      'دکمه «باز کردن سایت» را بزن.',
      'از منوی بالا Free VPN را باز کن و روی Free OpenVPN بزن.',
      'کشور و سرور را انتخاب کن (جلوی سرور باید Available باشد).',
      'نام کاربری و رمز بنویس (فقط حروف انگلیسی و عدد) و CREATE ACCOUNT را بزن.',
      'فایل کانفیگ OpenVPN (.ovpn) را دانلود کن یا متنش را کپی کن.',
      'اگر فایل دانلود کردی، آن را به‌صورت متن باز کن و همه‌ی متن را کپی کن.',
      'به برنامه برگرد، «ثبت در برنامه» را بزن و متن کامل را Paste کن.',
    ],
    [
      'مدت اعتبار طبق سایت است؛ قبل از ساخت در خود سایت چک کن.',
      'بعضی کانفیگ‌ها نام کاربری و رمز می‌خواهند؛ این برنامه فقط کانفیگ‌هایی را وصل می‌کند که داخل خودشان کامل است.',
    ],
  ),
  FreeProvider(
    'HideSSH (OpenVPN)',
    'ovpn',
    '۷ روز',
    'نامحدود (طبق ادعای سایت)',
    7,
    'https://hidessh.com',
    [
      'دکمه «باز کردن سایت» را بزن.',
      'از منو VPN SERVER را باز کن و Open VPN را انتخاب کن.',
      'یک سرور انتخاب کن.',
      'نام کاربری و رمز عبور بنویس، کپچا را تأیید کن و Create را بزن.',
      'فایل کانفیگ (.ovpn) را دانلود کن یا متنش را کپی کن.',
      'متن کامل کانفیگ را Copy کن (همه‌ی خط‌ها).',
      'به برنامه برگرد، «ثبت در برنامه» را بزن و متن کامل را Paste کن.',
    ],
    [
      'اعتبار ۷ روز و محدودیت تعداد حساب هر سرور در سایت نوشته شده.',
      'اگر کانفیگ نام کاربری/رمز جدا خواست، وصل نمی‌شود؛ سرور دیگری یا نوع دیگری بساز.',
    ],
  ),
  // ---------------- WireGuard (guide only) ----------------
  FreeProvider(
    'VPN Jantit (WireGuard)',
    'wg',
    'فقط راهنما',
    'نامحدود (طبق ادعای سایت)',
    0,
    'https://www.vpnjantit.com',
    [
      'دکمه «باز کردن سایت» را بزن.',
      'از منوی بالا Free VPN → Free WireGuard را انتخاب کن.',
      'کشور و سرور را انتخاب کن و حساب را بساز.',
      'کانفیگ WireGuard (متن یا فایل .conf) را بگیر.',
      'برنامه‌ی رسمی «WireGuard» را از Google Play نصب کن.',
      'در آن برنامه دکمه + را بزن و «Import from file» یا «Create from QR code» را انتخاب کن (یا کانفیگ را دستی بساز).',
      'کلید را روشن کن تا وصل شود.',
    ],
    [
      'این برنامه WireGuard را وصل نمی‌کند؛ فقط راهنمای ساخت است و اتصال از طریق برنامه‌ی رسمی WireGuard انجام می‌شود.',
      'مدت اعتبار و حجم را در خود سایت چک کن.',
    ],
  ),
  FreeProvider(
    'HideSSH (WireGuard)',
    'wg',
    'فقط راهنما',
    'در سایت ذکر نشده',
    0,
    'https://hidessh.com',
    [
      'دکمه «باز کردن سایت» را بزن.',
      'از منو VPN SERVER را باز کن و Wireguard را انتخاب کن.',
      'یک سرور انتخاب کن و فرم را پر کن (نام کاربری، کپچا).',
      'Create را بزن و کانفیگ WireGuard را کپی یا دانلود کن.',
      'برنامه‌ی رسمی «WireGuard» را از Google Play نصب کن.',
      'در آن برنامه دکمه + را بزن، فایل/QR/متن کانفیگ را وارد کن و کلید را روشن کن.',
    ],
    [
      'این برنامه WireGuard را وصل نمی‌کند؛ فقط راهنمای ساخت است.',
      'مدت اعتبار را در خود سایت چک کن.',
    ],
  ),
  FreeProvider(
    'Cloudflare Workers',
    'own',
    'دائمی',
    'روزی ۱۰۰ هزار درخواست (نه گیگ)',
    0,
    'https://dash.cloudflare.com/sign-up',
    personalGuide,
    [
      'پلن رایگان: ۱۰۰ هزار درخواست در روز؛ ریست ساعت ۰۰:۰۰ UTC (۰۳:۳۰ بامداد ایران).',
      'وقتی سقف پر شود Cloudflare خطای 1027 می‌دهد و برنامه پیام «حجم تمام شده» نشان می‌دهد.',
      'سرور فقط برای خودت است و هر وقت بخواهی دوباره ساخته می‌شود.',
    ],
  ),
  FreeProvider(
    'Oracle Cloud (Always Free)',
    'own',
    'دائمی',
    '۱۰ ترابایت در ماه (ترافیک خروجی)',
    0,
    'https://www.oracle.com/cloud/free/',
    [
      'دکمه «باز کردن سایت» را بزن و Start for free را انتخاب کن.',
      'ثبت‌نام کن (ایمیل، کشور، اطلاعات). ثبت‌نام معمولاً تأیید هویت با کارت بانکی بین‌المللی می‌خواهد و بسته به کشور ممکن است رد شود.',
      'در کنسول: Compute ← Instances ← Create instance.',
      'سیستم‌عامل Ubuntu را انتخاب کن و شکلی (Shape) را بگذار که Always Free eligible باشد (VM.Standard.E2.1.Micro یا Ampere A1).',
      'کلید SSH را بساز/دانلود کن و ماشین را بساز. بعد IP عمومی آن را کپی کن.',
      'با برنامه‌ای مثل Termux وصل شو: ssh -i کلید ubuntu@IP',
      'پنل 3x-ui را نصب کن (دستور رسمی پروژه): bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)',
      'در Oracle پورت‌های لازم (مثلاً ۴۴۳ و پورت پنل) را در Networking ← VCN ← Security List باز کن و در خود سرور هم فایروال (iptables/ufw) را باز کن.',
      'در پنل 3x-ui یک Inbound از نوع VLESS بساز، لینک را کپی کن.',
      'به برنامه برگرد، «ثبت در برنامه» را بزن و لینک را Paste کن.',
    ],
    [
      'نیاز به کار با ترمینال لینوکس دارد؛ برای مبتدی سخت‌تر است.',
      'Oracle ممکن است ماشین بی‌استفاده را پس بگیرد؛ گاهی خطای نبود ظرفیت (Out of host capacity) می‌دهد.',
    ],
  ),
];

class ProviderListPage extends StatelessWidget {
  final void Function(int days) onRegister;
  const ProviderListPage({super.key, required this.onRegister});

  @override
  Widget build(BuildContext context) {
    Widget section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child:
            Text(t, style: const TextStyle(fontWeight: FontWeight.bold)));
    Widget card(FreeProvider p) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            title: Text(p.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                Chip(
                    label: Text('⏱ ${p.badge}',
                        style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact),
                Chip(
                    label: Text('📦 ${p.volume}',
                        style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact),
              ]),
            ),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        ProviderPage(p: p, onRegister: onRegister))),
          ),
        );
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('ساخت سرور شخصی')),
        body: ListView(children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
                'یکی از سایت‌های رایگان را انتخاب کن. جلوی هر کدام مدت اعتبار و حجم نوشته شده. '
                'شرایط این سایت‌ها ممکن است تغییر کند؛ قبل از ساخت در خود سایت هم چک کن.',
                style: TextStyle(fontSize: 12, color: Color(0xFFCDD1D8))),
          ),
          section('⏱ سرور زمان‌دار'),
          for (final p in freeProviders.where((p) => p.kind == 'time'))
            card(p),
          section('📦 سرور حجمی'),
          for (final p in freeProviders.where((p) => p.kind == 'volume'))
            card(p),
          const SizedBox.shrink(),
          for (final p in freeProviders.where((p) => false))
            card(p),
          section('🧷 WireGuard (فقط راهنما، با برنامه‌ی رسمی WireGuard)'),
          for (final p in freeProviders.where((p) => p.kind == 'wg'))
            card(p),
          section('🛠 ساخت سرور کاملاً شخصی (دائمی)'),
          for (final p in freeProviders.where((p) => p.kind == 'own'))
            card(p),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

class ProviderPage extends StatelessWidget {
  final FreeProvider p;
  final void Function(int days) onRegister;
  const ProviderPage({super.key, required this.p, required this.onRegister});

  Future<void> _open(BuildContext ctx) async {
    try {
      if (await launchUrl(Uri.parse(p.url),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_swE) { _swl('_open#1', _swE);}
    await Clipboard.setData(ClipboardData(text: p.url));
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('باز نشد؛ لینک کپی شد. در مرورگر Paste کن.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(p.name)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 6, runSpacing: 4, children: [
            Chip(label: Text('⏱ ${p.badge}')),
            Chip(label: Text('📦 ${p.volume}')),
          ]),
          const SizedBox(height: 8),
          SelectableText(p.url,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8CCBFF))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                  onPressed: () => _open(context),
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('باز کردن سایت')),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: p.url));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('لینک سایت کپی شد')));
                  }
                },
                child: const Text('کپی لینک')),
          ]),
          const SizedBox(height: 20),
          const Text('مراحل ساخت',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          for (var i = 0; i < p.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                        radius: 12,
                        child: Text('${i + 1}',
                            style: const TextStyle(fontSize: 12))),
                    const SizedBox(width: 8),
                    Expanded(child: SelectableText(p.steps[i])),
                  ]),
            ),
          const SizedBox(height: 8),
          const Text('نکته‌ها',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          for (final n in p.notes)
            Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $n')),
          const SizedBox(height: 20),
          if (p.kind != 'wg')
            FilledButton.tonal(
              onPressed: () {
                Navigator.popUntil(context, (r) => r.isFirst);
                onRegister(p.days);
              },
              child: const Text('✅ لینک را ساختم؛ ثبت در برنامه'),
            ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

Future<List<Server>> fetchServers({bool Function()? stop}) async {
  final all = <String, Server>{};
  final sw = Stopwatch()..start();
  await pool<String>(listUrls, fetchWorkers, (u) async {
    if ((stop?.call() ?? false) || sw.elapsed > fetchDeadline) return;
    try {
      final r =
          await getListMirror(u);
      if (r.statusCode != 200) return;
      var body = r.body.trim();
      if (body.contains('<html') || body.contains('<!DOCTYPE')) {
        body = _linkRe
            .allMatches(body.replaceAll('&amp;', '&'))
            .map((m) => m.group(0)!)
            .join('\n');
      }
      if (!body.contains('://')) {
        if (!RegExp(r'^[A-Za-z0-9+/=_\-\s]+$').hasMatch(body)) return; // CLEANERR
        try {
          body = utf8.decode(base64
              .decode(base64.normalize(body.replaceAll(RegExp(r'\s'), ''))));
        } catch (_swE) { _swl('build#1', _swE);
          return;
        }
      }
      final lines = body
          .split(RegExp(r'[\r\n]+'))
          .where((l) =>
              l.contains('://') && !l.contains('[email') && !l.contains('protected]'))
          .toList()
        ..shuffle();
      var pn = 0;
      for (final l in lines.take(maxPerSource)) {
        final s = Server.parse(l);
        if (s != null) {
          s.src = u;
          all.putIfAbsent(s.key, () => s);
        }
        // FREEZEFIX: give the UI thread a frame every few parses
        if (++pn % 25 == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
      }
    } catch (_swE) { _swl('build#2', _swE);
      // a slow / dead list is normal: it is skipped silently
      // (this was the red "TimeoutException after 0:00:08" at the bottom)
    }
  });
  // OpenVPN servers (VPNGate)
  if (!(stop?.call() ?? false)) {
    for (final s in await fetchOvpn()) {
      all.putIfAbsent(s.key, () => s);
    }
  }
  return all.values.toList();
}

// ---------- rows (categories) ----------
class RowDef {
  final String id, title;
  final bool Function(Server) test;
  RowDef(this.id, this.title, this.test);
}

final rowDefs = <RowDef>[
  RowDef('ip', '🔢 اتصال با IP',
      (s) => !s.ovpn && (s.isIp || s.ipLink != null)),
  RowDef('cdn', '☁️ کلودفلر / CDN', (s) => s.cdn),
  RowDef('reality', '🛡 Reality', (s) => s.reality),
  RowDef('ws', '🔌 WebSocket', (s) => s.net == 'ws'),
  RowDef('grpc', '📡 gRPC / xhttp / h2',
      (s) => const ['grpc', 'xhttp', 'splithttp', 'httpupgrade', 'h2']
          .contains(s.net)),
  RowDef('trojan', '🌑 Trojan', (s) => s.link.startsWith('trojan://')),
  RowDef('ss', '🔐 Shadowsocks (Outline)', (s) => s.link.startsWith('ss://')),
  
  // shown as its own fixed row (second line of the list), see build()
  RowDef('ai', '🤖 سرورهای مخصوص هوش مصنوعی', (s) => s.ai == true && s.ping != null),
];

final Map<String, String?> _ownerCache = {};
String? ownerOf(Server s) {
  final u = s.src;
  if (u == null) return null;
  // FREEZEFIX: only ~50 distinct sources exist but this ran Uri.parse
  // thousands of times inside list sorts on the UI thread
  return _ownerCache.putIfAbsent(u, () {
    if (!u.startsWith(_gh)) {
      try {
        final x = Uri.parse(u);
        if (x.host == 't.me' && x.pathSegments.length > 1) {
          return 't.me/${x.pathSegments[1]}';
        }
        return x.host;
      } catch (_) {
        return u;
      }
    }
    return u.replaceFirst(_gh, '').split('/').first;
  });
}

// favs = the pinned / manually added configs ("📌 کانفیگ‌های من" row)
Map<String, String> _favsRef = {};

bool inRowGid(Server s, String gid) {
  if (gid.startsWith('p:')) return s.personal;
  if (gid.startsWith('f:')) return _favsRef.containsKey(s.key);
  if (gid.startsWith('s:')) return ownerOf(s) == gid.substring(2);
  if (gid.startsWith('c:')) return (s.country ?? '??') == gid.substring(2);
  final id = gid.substring(2);
  if (id == 'other') return !rowDefs.any((d) => d.test(s));
  return rowDefs.firstWhere((d) => d.id == id).test(s);
}

// DNS over HTTPS to a plain IP, so a poisoned local DNS cannot break it
final Map<String, String> _dohCache = {};
int _dohFail = 0; // DoH blocked on this network -> stop wasting time on it
Future<String?> dohResolve(String name) async {
  final c = _dohCache[name];
  if (c != null) return c;
  if (_dohFail >= 6) return null;
  for (final ep in _dohEps) {
    final cl = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await cl
          .getUrl(Uri.parse(ep.replaceAll('%N', name)))
          .timeout(const Duration(seconds: 3));
      req.headers.set('accept', 'application/dns-json');
      final res = await req.close().timeout(const Duration(seconds: 3));
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 3));
      for (final a in (jsonDecode(body)['Answer'] as List? ?? [])) {
        if (a['type'] == 1) {
          final ip = a['data'].toString();
          _dohCache[name] = ip;
          _dohFail = 0;
          return ip;
        }
      }
    } catch (_swE) { _swl('dohResolve#1', _swE);
    } finally {
      cl.close(force: true);
    }
  }
  _dohFail++;
  return null;
}

// same config, but the address is the resolved IP (SNI/Host keep the domain)
Future<String?> ipLinkFor(Server s) async {
  if (s.isIp || s.ovpn) return null;
  final l = s.link;
  if (l.toLowerCase().startsWith('ss://')) return null;
  final ip = (cleanIpMode && s.cdn ? await pickCleanIp() : null) ??
      await dohResolve(s.host);
  if (ip == null) return null;
  try {
    if (l.toLowerCase().startsWith('vmess://')) {
      var b = l.substring(8);
      b = b.padRight(b.length + (4 - b.length % 4) % 4, '=');
      final j = jsonDecode(utf8.decode(base64.decode(b)));
      j['add'] = ip;
      if ((j['sni'] ?? '').toString().isEmpty) j['sni'] = s.host;
      if ((j['host'] ?? '').toString().isEmpty && j['net'] == 'ws') {
        j['host'] = s.host;
      }
      return 'vmess://${base64.encode(utf8.encode(jsonEncode(j)))}';
    }
    final u = Uri.parse(l);
    final q = Map<String, String>.from(u.queryParameters);
    if ((q['sni'] ?? '').isEmpty) q['sni'] = s.host;
    if (q['type'] == 'ws' && (q['host'] ?? '').isEmpty) q['host'] = s.host;
    return u.replace(host: ip, queryParameters: q).toString();
  } catch (_swE) { _swl('ipLinkFor#1', _swE);
    return null;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final V2ray v2ray;
  late final OpenVPN ovpnCore;
  bool ovpnActive = false; // the OpenVPN engine was started and not stopped
  String ovpnStage = '';
  // ALL healthy servers (no count limit). Servers saved from the last session
  // are loaded here too (checkedAt == null) and tested first.
  final List<Server> good = [];
  final Set<String> warmKeys = {}; // keys of the saved servers (tested first)
  List<String> bypassApps = []; // apps that do NOT go through the VPN
  List<Server> bgAlive = []; // (legacy) TCP-alive servers from old installs
  List<Server> pending = []; // untested servers
  int total = 0, realTested = 0, realTotal = 0;
  String status = 'آماده';
  bool busy = false, connected = false;
  bool wantVpn = false, abort = false;
  // true while the app itself starts/stops the VPN: status events are ignored
  bool switching = false;
  bool searching = false; // a search (foreground or standby) is running
  bool inForeground = true, pendingFailover = false;
  // VPN permission was already granted once (stays valid in background)
  bool vpnPermOk = false;
  bool watchBusy = false;
  int liveDown = 0, liveUp = 0, totalDown = 0, totalUp = 0; // LIVESTATS (bytes)
  bool rechecking = false; // a re-check of the healthy servers is running
  String _lastWhyV = '';
  String get lastWhy => _lastWhyV;
  set lastWhy(String v) {
    _lastWhyV = v;
    if (v.isNotEmpty) dbg('علت تعویض: $v');
  }
  bool needTrial = false; // slow server noticed (informational)
  int noData = 0; // consecutive speed checks with no data at all
  String lastState = '';
  Server? current;
  Server? upServer; // VPN-mode test that passed: tunnel is left up
  DateTime? sessionEnd; // end of the current 4 hour ad session (null = none)
  Timer? sessionT;
  // the app was removed from the recent apps list (swiped away): the VPN stays
  // on, but the background server search / speed trials stop
  bool appGone = false;
  DateTime lastSwitch = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastStandby = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastUpgrade = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastFetchTry = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? watch, tick, dropTimer, saveT;
  int fails = 0, slowCount = 0, speedTick = 0, lowSpeed = 0, badPingRun = 0;
  int stallRun = 0; // SPEEDSWITCHPATCH: checks in a row under 100 KB/s
  int siteFail = 0; // checks in a row where no real site opened
  bool siteSeen = false; // a real site opened on THIS connection
  int siteNever = 0; // SITENEVER: checks in a row where no site opened since connect
  int siteNeverSwitches = 0; // SITENEVER: switches done for that reason in a row
  bool refilling = false; // SPEEDSWITCHPATCH: refill search running
  DateTime lastRefill = DateTime(2000);
  Future<void>? _prepFut;
  Future<void> _prepNow() => _prepFut ??= () async {
        try {
          await _natDetect();
          await autoNetPrep();
        } catch (e) {
          logError(e);
        }
      }();
  // true during the first seconds after the app starts: a tunnel that is
  // already up (app was closed, VPN kept running) is picked up again
  bool startAdopt = true;
  List<Server> fetchedAll = []; // full downloaded list (kept in memory + disk)
  DateTime? listTime;
  final Map<String, String> favs = {}; // pinned servers: key -> link
  final Map<String, Server> favObj = {}; // parsed objects of the pinned ones
  final Map<String, DateTime> failed = {}; // recently failed, not retested
  bool upBusy = false; // an upgrade trial is running
  bool tunWarn = false; // the VPN tunnel (tun0) was not detected
  int tunBad = 0, tunFixes = 0; // tunnel guard counters
  int tunFailRun = 0; // consecutive starts where Android built no tunnel
  bool showPanel = true; // speed monitor panel expanded
  Stopwatch? searchSw;
  int totalTested = 0, totalOk = 0, batchNo = 0;
  String proto = 'all';
  final Set<String> protoSel = {}; // empty = all protocols
  bool aiSession = false; // true only after "connect to AI server"
  Timer? aiLoop;
  bool sortSpeed = true;
  String? selCountry;
  // source (list) health: rate 0..1, last check, real-test counters
  final Map<String, double> srcRate = {};
  final Map<String, int> srcAt = {};
  final Map<String, int> srcTested = {}, srcOkN = {};
  final Set<String> srcReal = {};
  // learned success rate per profile (protocol / transport / security / port)
  final Map<String, int> profTested = {}, profOk = {};
  Set<String> topSrc = {};
  bool onlyHealthySrc = true;
  bool ipMode = false; // LOWDATA // resolve domains to IP (DoH) and connect by IP
  String groupMode = 'type'; // 'type' rows, 'country' rows or 'source' rows
  String? connRow; // row the current connection was picked from
  int dTcp = 0, dFake = 0; // diagnostics
  // Foreground test through the real VPN tunnel (like the old working
  // version). The phone shows the VPN key while testing. Set to false to try
  // the silent local-proxy mode first.
  bool viaVpn = true;
  int portFailRun = 0, pxTested = 0, pxOk = 0;
  // standby search while connected (core delay test, never touches the VPN)
  int bgTested = 0, bgOk = 0;
  bool bgDisabled = false;
  // list download + source ranking started at app launch (so the first
  // connect does not wait for it)
  Future<void>? warm;
  // the user's own Cloudflare server
  Server? personal;
  DateTime? personalExpiry; // end of validity (optional)
  String personalMsg = ''; // result of the last check
  DateTime lastPAlert = DateTime.fromMillisecondsSinceEpoch(0);

  // timeout used while looking for the FIRST healthy server: the TCP prefilter
  // already removed dead hosts, so a longer timeout only saves slow-but-working
  // servers (fewer false "dead" results)
  Duration get _fgTimeout =>
      Duration(seconds: delayTimeout.inSeconds);
  // timeout while connected: the tunnel is shared with the tests, so a longer
  // wait avoids marking slow-but-working servers as dead
  Duration get _bgTimeout =>
      Duration(seconds: max(delayTimeout.inSeconds + 2, bgTimeoutSecs));

  bool _bad(Server s) =>
      s.badAt != null && DateTime.now().difference(s.badAt!) < badFor;

  bool _protoOk(Server s) =>
      (protoSel.isEmpty ||
          protoSel.any((p) => s.link.toLowerCase().startsWith('$p://'))) &&
      (selCountry == null || s.country == null || s.country == selCountry);

  bool _recentFail(Server s) {
    final t = failed[s.key];
    return t != null && DateTime.now().difference(t) < failWindow;
  }

  // true when the active row / protocol filter is OpenVPN: only OpenVPN
  // servers are candidates then (the other engines cannot run them)
  bool get _ovMode => connRow == 'r:ovpn' || proto == 'ovpn';

  // healthy servers, best first
  List<Server> _usable() => good
      .where((s) =>
          !_bad(s) &&
          _protoOk(s) &&
          (identical(s, current) || (s.ping ?? 99999) >= minPingMs))
      .toList()
    ..sort(sortSpeed ? bySpeedThenPing : byPing);

  // healthy servers other than the one in use (optionally inside a row)
  int _ready([String? row]) => _usable()
      .where((s) =>
          !identical(s, current) &&
          (row == null ? s.ovpn == _ovMode : inRowGid(s, row)))
      .length;

  int get standbyCount => _ready();

  // the pinned / manually added configs as server objects (the same object
  // that is in the healthy list or in the queue when there is one)
  List<Server> _mineList() {
    final out = <Server>[];
    favs.forEach((k, l) {
      Server? s;
      for (final g in good) {
        if (g.key == k) {
          s = g;
          break;
        }
      }
      if (s == null) {
        for (final p in pending) {
          if (p.key == k) {
            s = p;
            break;
          }
        }
      }
      if (s == null) {
        s = favObj[k];
        if (s == null) {
          final ps = Server.parse(l);
          if (ps != null) {
            favObj[k] = ps;
            s = ps;
          }
        }
      }
      if (s != null && !s.personal) out.add(s);
    });
    return out;
  }

  // TGPREFER: servers that opened Telegram in the check come first (bit 0 of
  // svc), then the ones that opened everything. Not checked yet (-1) comes
  // after those, and servers checked WITHOUT Telegram come last.
  int _svcRank(Server s) {
    if (s.svc < 0) return 0;
    if ((s.svc & 1) != 0) return s.svc == 15 ? 3 : 2;
    return -1;
  }

  // TGWATCH: while connected, Telegram must keep opening. Every ~45 seconds it
  // is checked through the tunnel (only when other sites DO open, so a dead
  // internet is not blamed on Telegram). One "no" answer marks the
  // server and the next server (Telegram ones first) takes over.
  DateTime _tgChkAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _tgChkBad = 0;
  bool _tgChkBusy = false;
  void _tgKeepCheck() {
    try {
      if (_tgChkBusy || busy || switching || connRow == 'r:ai') return;
      final cur = current;
      if (cur == null || cur.ovpn || !connected) return;
      final now = DateTime.now();
      if (now.difference(_tgChkAt) < const Duration(seconds: 45)) return;
      if (now.difference(lastSwitch) < const Duration(seconds: 15)) return;
      _tgChkAt = now;
      _tgChkBusy = true;
      (() async {
        final tg = await Future.wait([
          _siteOpens('https://web.telegram.org/'),
          _siteOpens('https://telegram.org/'),
        ]);
        if (tg.any((x) => x)) return true;
        // Telegram did not open: is the internet itself fine?
        final other = await Future.wait([
          _siteOpens('https://www.youtube.com/generate_204'),
          _siteOpens('https://www.instagram.com/'),
        ]);
        return other.any((x) => x) ? false : null; // null = no internet
      })()
          .then((bool? ok) {
        if (!mounted || !identical(current, cur) || busy || switching) return;
        if (ok == true) {
          _tgChkBad = 0;
          cur.svc = cur.svc < 0 ? 1 : (cur.svc | 1);
        } else if (ok == false) {
          cur.svc = cur.svc < 0 ? 0 : (cur.svc & ~1);
          if (++_tgChkBad >= 1) {
            _tgChkBad = 0;
            // switch only when another server can still be tried
            final other = _pickList().any((x) => x.svc < 0 || (x.svc & 1) != 0);
            if (other) {
              lastWhy = 'تلگرام روی این سرور باز نمی‌شود';
              _failover();
            }
          } else {
            _tgChkAt = DateTime.now().subtract(const Duration(minutes: 2));
          }
        }
      }).catchError((_) {}).whenComplete(() => _tgChkBusy = false);
    } catch (e) {
      logError(e);
    }
  }

  // replacement candidates: servers of the active row first, then the rest.
  // Servers really checked in this session come before the ones only loaded
  // from disk; inside each group the HIGHEST REAL SPEED wins (saved speeds of
  // the last session count), servers without a speed are ordered by ping.
  List<Server> _pickList() {
    final u = _usable()
        .where((s) => !identical(s, current) && s.ovpn == _ovMode)
        .toList()
      ..sort((a, b) {
        final sv = _svcRank(b) - _svcRank(a); // MULTICHK + TGPREFER
        if (sv != 0) return sv;
        final x = (a.checkedAt == null ? 1 : 0) - (b.checkedAt == null ? 1 : 0);
        if (x != 0) return x;
        final sa = a.speed ?? 0, sb = b.speed ?? 0;
        if ((sa > 0) != (sb > 0)) return sa > 0 ? -1 : 1;
        if (sa > 0 && sb > 0 && sa != sb) return sb.compareTo(sa);
        return byPing(a, b);
      });
    final g = connRow;
    if (g == null) return u;
    final inRow = u.where((s) => inRowGid(s, g)).toList();
    return [...inRow, ...u.where((s) => !inRow.contains(s))];
  }

  @override
  void initState() {
    super.initState();
    _favsRef = favs;
    WidgetsBinding.instance.addObserver(this);
    // native side (MainActivity patch in the workflow) tells us the screen /
    // activity was destroyed (app swiped away from the recent apps)
    bgChannel.setMethodCallHandler((call) async {
      if (call.method == 'gone') {
        // BGKEEP: the screen was swiped away. While the VPN is wanted/up the
        // native side keeps this Dart engine alive, so the server search
        // goes on in the background. Only when there is no VPN everything stops.
        if (wantVpn || connected) return true;
        appGone = true;
        abort = true;
        return false;
      }
      return null;
    });
    ovpnCore = OpenVPN(
      onVpnStageChanged: (stage, raw) {
        final n = stage.toString().split('.').last.toLowerCase();
        ovpnStage = n;
        if (n == 'connected') {
          if (ovpnSig != null && !ovpnSig!.isCompleted) ovpnSig!.complete(true);
        } else if (n == 'denied' || n == 'error') {
          if (ovpnSig != null && !ovpnSig!.isCompleted) {
            ovpnSig!.complete(false);
          }
        }
        if (!mounted || busy || switching) return;
        if (current?.ovpn == true &&
            wantVpn &&
            (n == 'disconnected' || n == 'error' || n == 'denied')) {
          setState(() => connected = false);
          dropTimer?.cancel();
          dropTimer = Timer(const Duration(seconds: 2), () {
            if (wantVpn && ovpnStage != 'connected' && !busy && !switching) {
              lastWhy = 'اتصال OpenVPN قطع شد';
              _failover();
            }
          });
        } else if (n == 'connected' && current?.ovpn == true) {
          dropTimer?.cancel();
        }
      },
      onVpnStatusChanged: (_) {},
    );
    ovpnCore
        .initialize(localizedDescription: 'VPN')
        .catchError((e) => logError(e as Object));
    v2ray = V2ray(onStatusChanged: (st) {
      lastState = st.state;
      try {
        final d = st as dynamic; // LIVESTATS
        liveDown = (d.downloadSpeed as num?)?.toInt() ?? liveDown;
        liveUp = (d.uploadSpeed as num?)?.toInt() ?? liveUp;
        totalDown = (d.download as num?)?.toInt() ?? totalDown;
        totalUp = (d.upload as num?)?.toInt() ?? totalUp;
      } catch (_) {}
      dbgState(st.state);
      if (st.state == 'DISCONNECTED' &&
          downSig != null &&
          !downSig!.isCompleted) {
        downSig!.complete(true);
      }
      if (st.state == 'CONNECTED' &&
          connSig != null &&
          !connSig!.isCompleted) {
        connSig!.complete(true);
      }
      // an OpenVPN tunnel is in use: the V2Ray events do not matter
      if (current?.ovpn == true || ovpnActive) return;
      if (st.state == 'CONNECTED' && wantVpn && mounted && (busy || switching)) {
        // the event arrives while the app is busy: do not lose it, re-sync later
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) _syncCore();
        });
        Future.delayed(const Duration(seconds: 12), () {
          if (mounted) _syncCore();
        });
      }
      if (!mounted || busy || switching) return;
      final on = st.state == 'CONNECTED';
      if (on && !wantVpn) {
        // the app was closed while the VPN stayed up: pick the tunnel up again
        if (startAdopt) _adopt();
        return; // otherwise: late event from our own stop/start
      }
      setState(() => connected = on);
      if (on) {
        dropTimer?.cancel();
      } else if (st.state == 'DISCONNECTED' && wantVpn) {
        // short wait: a tiny glitch must not cause a switch, a real
        // disconnect is replaced right away (no 10 minute wait)
        dropTimer?.cancel();
        dropTimer = Timer(const Duration(seconds: 2), () {
          if (wantVpn &&
              lastState != 'CONNECTED' &&
              !busy &&
              !netDown &&
              !switching) {
            lastWhy = 'هسته/اندروید اتصال را قطع کرد';
            _failover();
          }
        });
      }
    });
    v2ray.initialize().catchError(logError);
    Future.delayed(const Duration(seconds: 15), () => startAdopt = false);
    _init();
    _inspectStart(); // INSPECTORPATCH
    // PERFPATCH: 5 s instead of 1 s (full page rebuild)
    tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && connected && inForeground) {
        if (!searching && !busy && !switching) status = _connStatus();
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    inForeground = s == AppLifecycleState.resumed;
    // healthy servers are kept on disk, so the next start tests them first
    if (s == AppLifecycleState.paused || s == AppLifecycleState.detached) {
      _saveCache();
    }
    if (s == AppLifecycleState.detached) {
      // BGKEEP: screen closed. With a VPN up the engine stays alive and the
      // search must go on; without a VPN every background test stops.
      if (!(wantVpn || connected)) {
        appGone = true;
        abort = true;
      }
    } else if (s == AppLifecycleState.resumed && appGone) {
      appGone = false;
      abort = false;
    }
    if (inForeground && mounted) setState(() {});
    if (inForeground && pendingFailover) {
      pendingFailover = false;
      if (wantVpn && !busy) _failover();
    }
  }

  // the VPN was already running when the app opened (app was closed before)
  Future<void> _adopt() async {
    startAdopt = false;
    wantVpn = true;
    vpnPermOk = true; // the VPN is already running, so permission exists
    lastSwitch = DateTime.now();
    try {
      final p = await SharedPreferences.getInstance();
      final l = p.getString('last_conn');
      final c = l == null ? null : Server.parse(l);
      if (c != null) {
        // use the same object that is in the healthy list (same key)
        final m = good.where((g) => g.key == c.key).toList();
        current = m.isNotEmpty ? m.first : c;
        if (!good.contains(current)) good.add(current!);
      }
    } catch (_swE) { _swl('_adopt#1', _swE);}
    if (!mounted) return;
    setState(() => connected = true);
    _set(_connStatus());
    _startWatch(); // starts the standby search again
    _showChannelPrompt();
  }

  // CHANNELPROMPT: asks the user to join the Telegram channel once the VPN is
  // connected (once per connection; failover does not repeat it)
  bool _chShown = false;

  Future<void> _showChannelPrompt() async {
    if (_chShown) return;
    _chShown = true;
    try {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted || !connected) {
        _chShown = false;
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('📢 کانال تلگرام ما'),
            content: const Text('برای اتصال بهتر و دریافت آپدیت‌های جدید، حتماً در کانال تلگرام زیر عضو شوید:\nhttps://t.me/kingvpnn57'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('رد شدن')),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  const url = 'https://t.me/kingvpnn57';
                  try {
                    if (await launchUrl(Uri.parse(url),
                        mode: LaunchMode.externalApplication)) {
                      return;
                    }
                  } catch (_) {}
                  await Clipboard.setData(const ClipboardData(text: url));
                  _set('لینک کانال کپی شد');
                },
                child: const Text('اتصال به کانال'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      logError(e);
    }
  }

  Future<void> _init() async {
    unawaited(adsRemoteLoad());
    unawaited(checkForUpdate());
    onlineStart();
    await _loadCache();
    await _resLoad(); // NATRESPATCH
    await autoTuneLoad(); // AUTOTUNEPATCH
    if (autoTune && !connected) unawaited(autoTuneNow());
    // WARM-UP: download the server lists and rank the sources right at launch
    // (only when the VPN is not already running), so the first connect starts
    // testing at once instead of waiting for the download.
    if (!connected && !startAdopt == false) {
      // startAdopt is still true in the first 15 s: give _adopt a moment
      await Future.delayed(const Duration(seconds: 2));
    }
    if (!connected && !wantVpn && !busy && !searching) {
      warm = _loadPending(bg: true).catchError((e) {
        logError(e as Object);
      }).whenComplete(() {
        warm = null;
        if (mounted && inForeground && !busy && !connected) {
          _set('آماده • ${pending.length} سرور در صف');
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    watch?.cancel();
    dropTimer?.cancel();
    tick?.cancel();
    saveT?.cancel();
    _setT?.cancel();
    sessionT?.cancel();
    _resT?.cancel(); // NATRESPATCH
    _resSaveT?.cancel();
    _insT?.cancel(); // the 3 s inspector timer was never stopped
    aiLoop?.cancel();
    localPilotLoop?.cancel();
    _onlineTimer?.cancel();
    _netWatchTimer?.cancel();
    super.dispose();
  }

  Future<void> _runBusy(Future<void> Function() f) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      // E-BUSY-STUCK: a never-ending await can no longer lock the app
      await f().timeout(const Duration(minutes: 5));
    } on TimeoutException {
      if (_acquiring) {
        dbg('جستجوی سرور بیش از ۵ دقیقه طول کشید؛ ادامه می‌دهد و قفل آزاد شد');
      } else {
        logError('busy بیش از ۵ دقیقه طول کشید و آزاد شد');
      }
    } catch (e) {
      logError(e);
    } finally {
      if (mounted) setState(() => busy = false);
      // E-CORE-UP-APP-DOWN: a core event that arrived while busy is re-synced now
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) _syncCore();
      });
    }
  }

  // late status events from our own stop/start must not trigger a switch
  void _unlockLater() => Future.delayed(const Duration(milliseconds: 3000), () {
        switching = false;
        _syncCore(); // SELFHEALPATCH
      });

  // SELFHEALPATCH: the core and the app must agree. Runs 3 s after every
  // switch and on every watchdog tick. Returns true when it changed something.
  int _syncBad = 0, _syncFixes = 0;
  DateTime _wbSince = DateTime.now();
  bool _syncCore() {
    try {
      if (!mounted || busy || switching) return false; // a standby search must not block the sync
      if (current?.ovpn == true || ovpnActive) return false;
      if (!wantVpn || current == null) {
        _syncBad = 0;
        return false;
      }
      // core is up but the app does not know (E-CORE-UP-APP-DOWN)
      if (lastState == 'CONNECTED' && !connected) {
        _syncBad = 0;
        _syncFixes++;
        dbg('همگام‌سازی خودکار: هسته CONNECTED بود ولی اپ قطع می‌دانست؛ اصلاح شد');
        _shProb('selfheal:core-up-app-down',
            'هسته CONNECTED است ولی اپ قطع می‌دانست • خودکار اصلاح شد');
        setState(() => connected = true);
        dropTimer?.cancel();
        if (watch?.isActive != true) _startWatch();
        return true;
      }
      // app thinks it is connected but the core is down (E-APP-UP-CORE-DOWN):
      // seen twice in a row and not right after a switch, so a tiny glitch
      // does not cause a new switch
      if (lastState == 'DISCONNECTED' && connected) {
        if (DateTime.now().difference(lastSwitch) <
            const Duration(seconds: 8)) {
          return false;
        }
        if (++_syncBad < 2) return false;
        _syncBad = 0;
        _syncFixes++;
        dbg('همگام‌سازی خودکار: اپ وصل می‌دانست ولی هسته قطع بود؛ تعویض');
        _shProb('selfheal:app-up-core-down',
            'اپ وصل است ولی هسته قطع است • خودکار تعویض شد');
        setState(() => connected = false);
        lastWhy = 'هسته/اندروید اتصال را قطع کرد';
        _failover();
        return true;
      }
      _syncBad = 0;
    } catch (e) {
      logError(e);
    }
    return false;
  }

  // PERFSET: a status text arrives for every single test; a full-page
  // rebuild for each one made the UI stutter. Redraw at most ~3 times a second.
  DateTime _setAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _setT;
  void _set(String s) {
    dbgStatus(s);
    status = s;
    // no redraw while the app is in the background (saves battery / memory)
    if (!mounted || !inForeground) return;
    final now = DateTime.now();
    if (now.difference(_setAt) >=
        Duration(milliseconds: searching ? 700 : 350)) {
      _setAt = now;
      setState(() {});
    } else if (_setT == null) {
      _setT = Timer(Duration(milliseconds: searching ? 700 : 350), () {
        _setT = null;
        _setAt = DateTime.now();
        if (mounted && inForeground) setState(() {});
      });
    }
  }

  // stop whatever search/connect is running (used when the user taps)
  Future<void> _haltAll() async {
    if (!busy && !searching) return;
    abort = true;
    final sw = Stopwatch()..start();
    while ((busy || searching) && sw.elapsed < const Duration(seconds: 25)) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    abort = false;
  }

  // stops both engines (V2Ray core and OpenVPN)
  Future<void> _stopV2() async {
    try {
      await v2ray.stopV2Ray();
    } catch (_swE) { _swl('_stopV2#1', _swE);}
    if (ovpnActive) {
      ovpnActive = false;
      try {
        await ovpnCore.disconnect();
      } catch (_swE) { _swl('_stopV2#2', _swE);}
      await Future.delayed(const Duration(milliseconds: 1200));
    }
  }

  // stop the core and wait until it is really down, so the next start
  // (VPN mode after a silent proxy-only test, or another server) is clean
  Future<void> _stopCore() async {
    // جدید: wait for the real DISCONNECTED event (not just a fixed delay), so
    // the next start can never race with the old VPN service still closing
    final wasUp = lastState == 'CONNECTED' || lastState == 'CONNECTING';
    if (wasUp) downSig = Completer<bool>();
    await _stopV2();
    var gotDown = !wasUp;
    if (wasUp && downSig != null) {
      gotDown = await downSig!.future
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
    }
    downSig = null;
    // a stale CONNECTED must not stay behind after a stop
    lastState = 'DISCONNECTED';
    // Android needs a moment to tear the old VPN service down, or the next
    // start can hang in CONNECTING and run without a tunnel (no key icon)
    await Future.delayed(Duration(milliseconds: gotDown ? 1200 : 2200));
  }

  // ---------- cache ----------
  Future<void> _loadCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      await loadGeminiPrefs(p);
      await loadNumPrefs(p);
      await ultimateLoad(p);
      autoNetOn = p.getBool('autonet_on') ?? true; // AUTONET
      // settings first: the fail window / re-check time are used below
      final st = await tunedSettings(p);
      if (st != null) {
        final j = jsonDecode(st);
        // settings saved by an older version are ignored once, so the new
        // defaults (bigger batch, longer timeout, ...) take effect
        if ((j['ver'] as num?)?.toInt() == 6) {
          batchSize = _ci(j['b'], batchSize, 1, 1000);
          delayWorkers = (j['w'] as num?)?.toInt() ?? delayWorkers;
          delayTimeout = Duration(seconds: _ci(j['t'], 8, 1, 1000));
          goodWant = (j['g'] as num?)?.toInt() ?? goodWant;
          autoSpeed = j['a2'] as bool? ?? autoSpeed;
          onlyHealthySrc = j['o'] as bool? ?? onlyHealthySrc;
          ipMode = j['i'] as bool? ?? ipMode;
          minPingMs = _ci(j['m2'], minPingMs, 0, 1000);
          autoUpgrade = j['u'] as bool? ?? autoUpgrade;
          fastDelay = j['fd'] as bool? ?? fastDelay;
          fastWorkers = _ci(j['fw2'], fastWorkers, 1, 1000);
          bgWorkers = _ci(j['bw2'], bgWorkers, 1, 1000);
          speedTopN = _ci(j['st'], speedTopN, 1, 1000);
          badPingSwitch = j['bps'] as bool? ?? badPingSwitch;
          badPingMs = _ci(j['bp'], badPingMs, 70, 7000);
          minSpeedKB = _ci(j['ms'], minSpeedKB, 0, 50000);
          // مهاجرت: مقادیر اجباری قدیمی توربو/پروفایل که باعث تعویض زیاد می‌شد
          if (const {150, 300, 400, 800, 1500}.contains(minSpeedKB)) {
            minSpeedKB = 0;
          }
          savedFirst = j['sf'] as bool? ?? savedFirst;
          smartOrder = j['so'] as bool? ?? smartOrder;
          autoCycle = j['ac'] as bool? ?? autoCycle;
          ultraMode = false; // plain-only: ignore old saved Ultra flag
          indestructibleMode = j['idm'] as bool? ?? indestructibleMode;
          // توربو سرعت بعد از اتصال: پیش‌فرض و ترجیح همیشه روشن
          turboSpeed = j['tb'] as bool? ?? true;
          if (j['tb'] == false) {
            // کاربر قبلاً خاموش کرده بود — باز هم برای پایداری سرعت روشن می‌کنیم
            turboSpeed = true;
          }
          listRefreshMin = _ci(j['lr'], listRefreshMin, 1, 1000);
          failMin = _ci(j['fm'], failMin, 1, 1000);
          recheckMin = _ci(j['rm'], recheckMin, 1, 1000);
          iranRoute = j['ir'] as bool? ?? iranRoute;
          iranGeoip = j['ig'] as bool? ?? iranGeoip;
          npvParse = j['npv'] as bool? ?? npvParse;
          cleanIpMode = j['cip'] as bool? ?? cleanIpMode;
          fragEnabled = j['frg'] as bool? ?? fragEnabled;
          // Mux برای توربو سرعت بعد از اتصال روشن می‌ماند
          muxEnabled = j['mux'] as bool? ?? true;
          if (!muxEnabled) muxEnabled = true;
          secureDns = j['sdns'] as bool? ?? secureDns;
          iranMore = j['irm'] as bool? ?? iranMore;
          blockQuic = j['bq'] as bool? ?? blockQuic;
          lanDirect = j['lan'] as bool? ?? lanDirect;
          routeOnly = j['ro'] as bool? ?? routeOnly;
          fragLen = j['fl'] as String? ?? fragLen;
          fragInt = j['fi'] as String? ?? fragInt;
          muxConc = (j['mc'] as num?)?.toInt() ?? muxConc;
          dnsProv = j['dp'] as String? ?? dnsProv;
          proxyMode = j['px'] as bool? ?? proxyMode;
        }
        failWindow = Duration(minutes: failMin);
        recheckAfter = Duration(minutes: recheckMin);
      }
      // LOWDATA: lowest internet usage, applied ONCE (fastWorkers stays 50,
      // batch stays 500). After that the user's own changes are kept.
      if (p.getBool('lowdata_v1') != true) {
        fastWorkers = 50;
        batchSize = 100;
        bgWorkers = 1;
        delayTimeout = const Duration(seconds: 8);
        speedTopN = 8;
        badPingMs = 3000;
        minSpeedKB = 0;
        listRefreshMin = 240;
        failMin = 120;
        recheckMin = 30;
        tcpWorkers = 50;
        maxPerSource = 100;
        fetchWorkers = 4;
        fetchDeadline = const Duration(seconds: 20);
        firstBatchSize = 50;
        standbyBatchSize = 30;
        maxBatches = 5;
        watchFailLimit = 3;
        badPingLimit = 3;
        missLimit = 3;
        watchEvery = const Duration(seconds: 60);
        autoSpeed = false;
        autoUpgrade = false;
        badPingSwitch = false;
        autoCycle = false;
        ipMode = false;
        cleanIpMode = false;
        secureDns = false;
        failWindow = Duration(minutes: failMin);
        recheckAfter = Duration(minutes: recheckMin);
        await p.setBool('lowdata_v1', true);
        await _saveSettings();
      }
      // FOLDERONLY: healthy servers are kept only in the folder
      for (final k in ['cache', 'bg_tcp', 'nat_keys']) {
        await p.remove(k);
      }
      final String? c = null;
      if (c != null) {
        for (final j in jsonDecode(c)) {
          final s = Server.parse(j['l'] as String);
          if (s == null || s.ovpn) continue;
          s.ping = j['p'] as int?;
          s.speed = (j['s'] as num?)?.toDouble();
          s.ai = j['a'] as bool?;
          s.miss = (j['m'] as num?)?.toInt() ?? 0;
          warmKeys.add(s.key);
          // checkedAt stays null: these are tested FIRST at the next connect
          if (!good.any((g) => g.key == s.key)) good.add(s);
        }
      }
      // servers that failed recently are not tested again (kept on disk)
      final fj = p.getString('failed2');
      if (fj != null) {
        final now = DateTime.now();
        (jsonDecode(fj) as Map).forEach((k, v) {
          final t = DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
          if (now.difference(t) < failWindow) failed[k as String] = t;
        });
      }
      bypassApps = p.getStringList('bypass') ?? [];
      final pl = p.getString('personal_link');
      if (pl != null) personal = Server.parse(pl)?..personal = true;
      final pe = p.getInt('personal_exp');
      if (pe != null) personalExpiry = DateTime.fromMillisecondsSinceEpoch(pe);
      final String? b = null; // FOLDERONLY
      if (b != null) {
        for (final j in jsonDecode(b)) {
          final s = Server.parse(j['l'] as String);
          if (s == null) continue;
          s.ping = j['p'] as int?;
          bgAlive.add(s);
        }
      }
      final lc = p.getStringList('list_cache');
      final lt = p.getInt('list_time');
      if (lc != null && lt != null) {
        var legacy = false;
        for (final l in lc) {
          final i = l.indexOf('\t');
          if (i < 0) legacy = true;
          final s = Server.parse(i >= 0 ? l.substring(i + 1) : l);
          if (s == null) continue;
          if (i > 0) s.src = l.substring(0, i);
          fetchedAll.add(s);
        }
        listTime = legacy ? null : DateTime.fromMillisecondsSinceEpoch(lt);
        total = fetchedAll.length;
      }
      for (final l in p.getStringList('favs') ?? <String>[]) {
        final s = Server.parse(l);
        // the cleaned link is stored (old entries saved with extra text
        // around the link are repaired here)
        if (s != null) favs[s.key] = s.link;
      }
      final ss = p.getString('src_scores');
      if (ss != null) {
        (jsonDecode(ss) as Map).forEach((k, v) {
          srcRate[k as String] = (v[0] as num).toDouble();
          srcAt[k] = (v[1] as num).toInt();
          if (v[2] == 1) srcReal.add(k);
        });
      }
      final pj = p.getString('prof');
      if (pj != null) {
        (jsonDecode(pj) as Map).forEach((k, v) {
          profTested[k as String] = (v[0] as num).toInt();
          profOk[k] = (v[1] as num).toInt();
        });
      }
      selCountry = p.getString('country');
      // 4 hour ad session survives app restarts
      final se = p.getInt('sessionEnd');
      sessionEnd =
          se == null ? null : DateTime.fromMillisecondsSinceEpoch(se);
      if (!_sessionValid) sessionEnd = null;
      _startSessionTimer();
      if (mounted) setState(() {});
    } catch (e) {
      logError(e);
    }
  }

  // save a little later (not on every single result)
  void _saveSoon() {
    if (saveT?.isActive == true) return;
    saveT = Timer(const Duration(seconds: 20), _saveCache);
  }

  // ALL healthy servers (no count limit), best speed first, kept on disk
  // (OpenVPN servers are not saved: volunteer servers change too fast).
  // A healthy server is only dropped after [missLimit] failed re-checks.
  Future<void> _saveCache() async {
    _resSave(); // NATRESPATCH
    try {
      final p = await SharedPreferences.getInstance();
      // dead servers are remembered too, so the next start does not waste
      // time on them
      final now = DateTime.now();
      var fl = failed.entries
          .where((e) => now.difference(e.value) < failWindow)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (fl.length > 4000) fl = fl.take(4000).toList();
      await p.setString('failed2',
          await _shJson({for (final e in fl) e.key: e.value.millisecondsSinceEpoch}));
      final keep = good.where((s) => s.miss < missLimit && !s.ovpn).toList()
        ..sort(bySpeedThenPing);
      if (keep.isNotEmpty) return; // FOLDERONLY: no 'cache' file any more
      if (keep.isEmpty) return;
      await p.setString(
          'cache',
          await _shJson(keep
              .map((s) => {
                    'l': s.link,
                    'p': s.ping,
                    's': s.speed,
                    'a': s.ai,
                    'm': s.miss
                  })
              .toList()));
    } catch (e) {
      logError(e);
    }
  }

  Future<void> _saveList() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(
          'list_cache',
          (fetchedAll.toList()..shuffle())
              .take(3000)
              .map((s) => '${s.src ?? ''}\t${s.link}')
              .toList());
      await p.setInt('list_time', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      logError(e);
    }
  }

  Future<void> _saveFavs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('favs', favs.values.toList());
    } catch (e) {
      logError(e);
    }
  }

  Future<void> _savePersonal() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (personal == null) {
        await p.remove('personal_link');
        await p.remove('personal_exp');
      } else {
        await p.setString('personal_link', personal!.link);
        if (personalExpiry == null) {
          await p.remove('personal_exp');
        } else {
          await p.setInt(
              'personal_exp', personalExpiry!.millisecondsSinceEpoch);
        }
      }
    } catch (e) {
      logError(e);
    }
  }

  Future<void> _saveSettings() async {
    saveNumPrefs();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          'settings',
          jsonEncode({
            'ver': 6,
            'b': batchSize,
            'w': delayWorkers,
            't': delayTimeout.inSeconds,
            'g': goodWant,
            'a2': autoSpeed,
            'o': onlyHealthySrc,
            'i': ipMode,
            'm2': minPingMs,
            'u': autoUpgrade,
            'fd': fastDelay,
            'fw2': fastWorkers,
            'bw2': bgWorkers,
            'st': speedTopN,
            'bps': badPingSwitch,
            'bp': badPingMs,
            'ms': minSpeedKB,
            'sf': savedFirst,
            'so': smartOrder,
            'ac': autoCycle,
            'um': ultraMode,
            'idm': indestructibleMode,
            'tb': turboSpeed,
            'lr': listRefreshMin,
            'fm': failMin,
            'rm': recheckMin,
            'ir': iranRoute,
            'ig': iranGeoip,
            'npv': npvParse,
            'cip': cleanIpMode,
            'frg': fragEnabled,
            'mux': muxEnabled,
            'sdns': secureDns,
            'irm': iranMore,
            'bq': blockQuic,
            'lan': lanDirect,
            'ro': routeOnly,
            'fl': fragLen,
            'fi': fragInt,
            'mc': muxConc,
            'dp': dnsProv,
            'px': proxyMode,
          }));
    } catch (e) {
      logError(e);
    }
  }

  void _toggleFav(Server s) {
    if (s.personal) return;
    if (favs.remove(s.key) == null) favs[s.key] = s.link;
    _saveFavs();
    setState(() {});
  }

  bool get _sessionValid =>
      sessionEnd != null && DateTime.now().isBefore(sessionEnd!);

  // checks every 20 s: when the 4 hours are over the VPN is cut (only then).
  void _startSessionTimer() {
    sessionT?.cancel();
    sessionT = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (sessionEnd == null || _sessionValid) return;
      sessionEnd = null;
      try {
        final p = await SharedPreferences.getInstance();
        await p.remove('sessionEnd');
      } catch (_swE) { _swl('_startSessionTimer#1', _swE);}
      if (connected || wantVpn) {
        await disconnect();
        _set('⏱ ۴ ساعت اتصال تمام شد؛ برای ادامه دوباره «اتصال» را بزن (تبلیغ نمایش داده می‌شود)');
      }
    });
  }

  Future<void> _startSession() async {
    sessionEnd = DateTime.now().add(sessionLength);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('sessionEnd', sessionEnd!.millisecondsSinceEpoch);
    } catch (_swE) { _swl('_startSession#1', _swE);}
    _startSessionTimer();
  }

  // Ads are never forced and never block connecting. After a connect that
  // the USER started (no session running), an ad is shown; if it was really
  // shown, a 4 hour session starts. Automatic server switches never get here.
  // Before a user-started connect: if no 4 hour session is running, the ad
  // must be seen first (patch_adpage.py swaps the AdMob rewarded ad for the
  // in-app ad page). Seen -> a new 4 hour session starts. Not seen -> false.
  Future<bool> _ensureSession() async {
    if (!requireRewardedAd || (_sessionValid && !_adEveryConnect)) return true;
    if (!mounted) return false;
    unawaited(adsRemoteLoad());
      final ok = await showAdPage(context);
    if (ok) await _startSession();
    return ok;
  }

  void _adAfterConnect() {
    // AdMob test interstitial removed
  }

  // ---------- smart ordering (no extra parallel tests needed) ----------
  String _profKey(Server s) =>
      '$natOpKey|${s.link.split('://').first.toLowerCase()}|${s.net}|'
      '${s.reality ? 'r' : (s.tls ? 't' : 'n')}|${s.port == 443 ? '443' : 'x'}';

  // learned success rate of this kind of server on this network (0..1)
  double _profRate(Server s) {
    final k = _profKey(s);
    return ((profOk[k] ?? 0) + 1) / ((profTested[k] ?? 0) + 3);
  }

  // a list that gave NOTHING in its first 12 real tests is skipped for now
  bool _srcDead(Server s) {
    final u = s.src;
    if (u == null || s.ovpn) return false;
    if (nationalMode && (natAll || _natSrc(s))) return false; // NATIONALPATCH
    return (srcTested[u] ?? 0) >= 12 && (srcOkN[u] ?? 0) == 0;
  }

  // order of the TCP-alive servers inside a batch: the kind that works best
  // on this network first, then score, then lowest TCP ping
  int _cmpAlive(Server a, Server b) {
    if (smartOrder) {
      final q = (_profRate(b) * 20).round() - (_profRate(a) * 20).round();
      if (q != 0) return q;
    }
    return byScoreThenPing(a, b);
  }

  // round-robin over the lists (best / hottest lists first), so one big or
  // dead list can never fill a whole batch
  List<Server> _diversify(List<Server> l) {
    final out = <Server>[];
    final by = <String, List<Server>>{};
    for (final s in l) {
      if (_tier(s) >= 3) {
        out.add(s);
      } else {
        (by[s.src ?? ''] ??= []).add(s);
      }
    }
    final keys = by.keys.toList()
      ..sort((a, b) {
        final t = _tier(by[b]!.first) - _tier(by[a]!.first);
        if (t != 0) return t;
        return (srcRate[b] ?? 0.3).compareTo(srcRate[a] ?? 0.3);
      });
    final ptr = {for (final k in keys) k: 0};
    var more = true, round = 0;
    while (more) {
      more = false;
      for (final k in keys) {
        final q = by[k]!;
        var p0 = ptr[k]!;
        if (p0 >= q.length) continue;
        more = true;
        final r = srcRate[k] ?? 0.3;
        if (r < 0.1 && round % 4 != 0) continue; // weak lists: 1 round in 4
        final ti = _tier(q.first);
        final per = ti >= 3 ? 4 : (ti == 2 ? 3 : 1);
        for (var n = 0; n < per && p0 < q.length; n++) {
          out.add(q[p0++]);
        }
        ptr[k] = p0;
      }
      round++;
    }
    return out;
  }

  // ---------- discovery ----------
  // builds the queue: favourites, then everything else (hot GitHub sources
  // are sorted to the front by _cmpPending). The saved healthy servers are
  // already in [good] and are tested first by _checkSaved.
  // exhausted = the queue ran empty: the list is refreshed after only 2 min
  // (new servers appear in the hot lists all the time) and the cycle goes on.
  Future<void> _loadPending({bool bg = false, bool exhausted = false}) async {
    // ULTIMATE: offline-only never downloads new lists
    if (offlineOnly) {
      if (!bg) _set('حالت آفلاین: فقط سرورهای ذخیره‌شده');
      return;
    }
    final now0 = DateTime.now();
    final age = listTime == null ? null : now0.difference(listTime!);
    final limit = (exhausted && autoCycle)
        ? const Duration(minutes: 2)
        : Duration(minutes: listRefreshMin);
    final fresh = (nationalMode && !connected && fetchedAll.isNotEmpty && !natRefetch) || // NATIONALPATCH
        (age != null && fetchedAll.length > 200 && age < limit);
    if (!fresh && now0.difference(lastFetchTry) > const Duration(seconds: 45)) {
      lastFetchTry = now0;
      natRefetch = false;
      if (!bg) _set('در حال دریافت لیست‌ها...');
      try {
        final f = await fetchServers(stop: () => abort);
        if (f.isNotEmpty) {
          // lists that were "dead" get a new chance with the new content
          if (age == null || age >= Duration(minutes: min(listRefreshMin, 10))) {
            srcTested.removeWhere((k, v) => (srcOkN[k] ?? 0) == 0);
          }
          fetchedAll = f;
          listTime = DateTime.now();
          _saveList();
        }
      } catch (e) {
        logError(e);
      }
    }
    final fetched = fetchedAll;
    if (fetched.isNotEmpty) total = fetched.length;
    // TCP probes are meaningless while the tunnel is up.
    // The source ranking waits at most 6 s: it keeps running in the background
    // and the search starts right away (no long wait before the first test).
    if (!connected) {
      try {
        await _rankSources().timeout(const Duration(seconds: 6));
      } catch (_swE) { _swl('_loadPending#1', _swE);}
    }
    final rk = srcRate.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    topSrc = rk.take(8).map((e) => e.key).toSet();
    final seen = <String>{for (final g in good) g.key};
    final out = <Server>[];
    void add(Server s) {
      if (_protoOk(s) &&
          _srcOk(s) &&
          !_recentFail(s) &&
          seen.add(s.key) &&
          !_bad(s)) {
        out.add(s);
      }
    }

    for (final l in favs.values) {
      final s = Server.parse(l);
      if (s != null) add(s);
    }
    (bgAlive.toList()..sort(byScoreThenPing)).forEach(add);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final rest = fetched.toList()
      ..shuffle()
      ..sort(_cmpPending);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    // FREEZEFIX: thousands of servers are filtered in small slices so the
    // screen keeps drawing (this used to block the UI for 9-13 seconds)
    var ri = 0;
    for (final s in rest) {
      add(s);
      if (++ri % 150 == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }
    pending = out;
    if (mounted) setState(() {});
  }

  // can this server be a test candidate for the given row?
  // OpenVPN servers are only tested for the OpenVPN row (or the OpenVPN
  // protocol filter); every other row never touches them.
  bool _cand(Server s, String? row) {
    if (s.ovpn) return row == 'r:ovpn' || (row == null && proto == 'ovpn');
    if (row == 'r:ovpn') return false;
    if (row == null) return true;
    if (row == 'r:ai') return true; // every server is a Gemini candidate
    if (row == 'r:ip') return !s.link.startsWith('ss://'); // resolved to IP
    return inRowGid(s, row);
  }

  // Test batches until [want] healthy servers (besides the current one) exist.
  //  bg      = standby search while connected (never touches the VPN)
  //  keepUp  = VPN-mode fallback: leave the tunnel up on the first good one
  //  explore = (bg only) never stop at [want]: keep looking for better servers
  Future<void> _findGood(int want,
      {String? row,
      bool keepUp = false,
      bool bg = false,
      bool explore = false}) async {
    if (searching) return;
    searching = true;
    try {
      if (!bg) {
        if (autoTune && !connected) unawaited(autoTuneNow()); // AUTOTUNEPATCH
        searchSw = Stopwatch()..start();
        dTcp = 0;
        dFake = 0;
        totalTested = 0;
        totalOk = 0;
        batchNo = 0;
        if (!connected) {
          // a leftover tunnel would make every test time out
          await _stopV2();
        }
      } else {
        // the speed counters also run during the standby search
        searchSw ??= Stopwatch();
        if (!searchSw!.isRunning) searchSw!.start();
      }
      upServer = null;
      // enough = the wanted number of healthy servers, or (foreground only)
      // at least one after 90 s so the user is not kept waiting
      bool enough() {
        if (explore) return false;
        final ready = _ready(row);
        if (upServer != null) return true;
        if (ready >= want) return true;
        // اتصال سریع: با ۱ سرور سالم بعد از چند ثانیه برو وصل شو
        // (جستجوی پس‌زمینه بعداً سرور بیشتر جمع می‌کند)
        if (!bg && ready >= 1) {
          final elapsed = searchSw?.elapsed ?? Duration.zero;
          // حداقل ۱ سالم + ۲ثانیه → کافی برای اتصال فوری
          if (elapsed > const Duration(seconds: 2)) return true;
        }
        if (!bg &&
            ready >= 2 &&
            (searchSw?.elapsed ?? Duration.zero) >
                Duration(seconds: min(firstCapSec, 15))) {
          return true;
        }
        return false;
      }

      if (pending.isEmpty) await _loadPending(bg: bg, exhausted: true);
      // healthy servers not yet tested for Gemini are tested too
      if (!bg && row == 'r:ai') {
        pending.insertAll(
            0, good.where((s) => s.ai == null && !identical(s, current)));
      }
      var batches = 0;
      var reloaded = false;
      // standby search: bigger batches (the tunnel is shared), the healthy
      // servers are re-checked every 25 tests and after every batch
      final maxB = bg ? standbyBatches : 1000000; // RETRYPATCH
      while (!abort &&
          !(bg && (!connected || appGone)) &&
          !enough() &&
          batches < maxB) {
        // the whole list was tested: download a new one and go on (endless)
        if (pending.isEmpty) {
          if (!autoCycle || reloaded) break;
          reloaded = true;
          await _loadPending(bg: bg, exhausted: true);
          if (pending.isEmpty) break;
        }
        batches++;
        batchNo = batches;
        // FAST mode (foreground): parallel core delay tests, no VPN toggling.
        // Gemini rows and OpenVPN still use the old tunnel test.
        final fast = !bg &&
            fastDelay &&
            row != 'r:ovpn' &&
            !_ovMode;
        // first batch is small when nothing healthy is known yet: the first
        // test starts after ~1-2 s instead of ~4 s
        final size = bg
            ? standbyBatchSize
            : (batches == 0
                ? firstBatchSize // first batch small → connect ASAP
                : batchSize);
        pending.sort(_cmpPending);
        var cand = pending
            .where((s) =>
                _cand(s, row) &&
                !(bg && s.ovpn) &&
                !(smartOrder && _srcDead(s)))
            .take(size * 3)
            .toList();
        if (smartOrder) cand = _diversify(cand);
        final batch = cand.take(size).toList();
        _set('ردیف ${row ?? 'همه'} • '
            '${fast ? 'تست موازی' : 'تست تکی'} • دسته ${batch.length}');
        if (batch.isEmpty) {
          // only skipped / unsuitable servers are left: try a fresh list once
          if (autoCycle && !reloaded) {
            reloaded = true;
            batches--;
            await _loadPending(bg: bg, exhausted: true);
            continue;
          }
          break;
        }
        reloaded = false;
        final bs = batch.toSet();
        pending.removeWhere(bs.contains);
        if (bg) {
          await _testBatchDelay(batch, enough);
          if (bgDisabled) break;
        } else if (fast) {
          await _testBatchFast(batch, enough, row: row);
          if (selCountry != null) await _geoFill();
        } else {
          await _testBatchSeq(batch, enough, keepUp: keepUp, row: row);
          if (selCountry != null) await _geoFill();
        }
        if (upServer != null) break;
        // healthy servers are tested again between the batches: dead ones
        // are deleted, the ping of the others is refreshed
        if (bg) await _recheckStandby();
      }
    } finally {
      searching = false;
      if (!bg) searchSw?.stop();
      dbg('پایان جستجو (${bg ? 'پس‌زمینه' : 'اصلی'}): '
          '${searchSw?.elapsed.inSeconds ?? 0}s • تست سریع $fastOk/$fastTested'
          ' • سالم ${good.length}');
    }
    _saveSrc();
    if (!bg && !abort && upServer == null && good.isEmpty) {
      final now = DateTime.now();
      if (_lastNoHealthyLog == null ||
          now.difference(_lastNoHealthyLog!) > const Duration(seconds: 60)) {
        _lastNoHealthyLog = now;
        logError('سرور سالمی پیدا نشد');
      }
    }
  }

  // wait for a running search, or start one
  Future<void> _search(int want, {String? row, bool keepUp = false}) async {
    final sw = Stopwatch()..start();
    while (searching && sw.elapsed < const Duration(seconds: 20) && !abort) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    if (abort || searching) return;
    await _findGood(want, row: row, keepUp: keepUp);
  }

  void _record(Server s, int? d) {
    s.checkedAt = DateTime.now();
    if (d != null) {
      s.ping = d;
      s.badAt = null;
      s.miss = 0;
      failed.remove(s.key);
      totalOk++;
      _resAdd(s); // NATRESPATCH
      if (nationalMode) _natAdd(s); // NATIONALPATCH
      if (!good.contains(s)) {
        good.add(s);
        _saveSoon(); // a new healthy server is kept on disk quickly
      }
    } else {
      failed[s.key] = DateTime.now();
      s.ai = null; // dead now: the old Gemini result is no longer trusted
    }
    // learn which kind of server works on this network
    if (!s.ovpn) {
      final k = _profKey(s);
      profTested[k] = (profTested[k] ?? 0) + 1;
      if (d != null) profOk[k] = (profOk[k] ?? 0) + 1;
      if (profTested[k]! > 400) {
        profTested[k] = profTested[k]! ~/ 2;
        profOk[k] = (profOk[k] ?? 0) ~/ 2;
      }
    }
    _srcRecord(s, d != null);
    totalTested++;
  }

  // TCP prefilter (parallel). The first servers (best score) also get their
  // IP resolved here IN PARALLEL, so the tests do not wait for DNS one by one.
  Future<List<Server>> _tcpFilter(List<Server> batch) async {
    final alive = <Server>[];
    await pool<Server>(batch, tcpWorkers, (s) async {
      if (abort) return;
      // OpenVPN over UDP cannot be probed with TCP: it goes to the real test
      if (s.ovpn && s.udp) {
        alive.add(s);
        return;
      }
      final pg = await probe(s);
      if (pg != null && pg >= 12) {
        s.ping = pg;
        alive.add(s);
      } else {
        failed[s.key] = DateTime.now();
      }
    });
    if (ipMode && !abort) {
      final top = (alive.toList()..sort(_cmpAlive))
          .where((s) => !s.ovpn && s.ipLink == null && !s.ipTried)
          .take(40)
          .toList();
      await pool<Server>(top, 24, (s) async {
        s.ipTried = true;
        s.ipLink = await ipLinkFor(s);
      });
    }
    return alive;
  }

  // FAST foreground test: the core's own delay test on [fastWorkers] servers
  // at the same time. The VPN is never started or stopped here, so a test
  // costs ~1-3 s instead of ~6-10 s. It stops as soon as the first healthy
  // server is found; the connect step then verifies it for real. If nothing
  // at all passes after 60 tests the app falls back to the old tunnel test
  // (fastDelay = false).
  Future<void> _testBatchFast(
      List<Server> batch, bool Function() enough,
      {String? row}) async {  // AIQUICKPATCH
    // IP servers: cheap TCP check (no DNS involved). Domain servers go
    // straight to the core test, like v2rayNG.
    final ipList = batch.where((s) => s.isIp).toList();
    final alive = batch.where((s) => !s.isIp).toList();
    if ((nationalMode && natLevel >= 2) || ultraMode) {
      alive.addAll(ipList); // NATULTRA / ULTRA: straight to the real core test
      ipList.clear();
    }
    await pool<Server>(ipList, max(60, fastWorkers), (s) async {
      if (abort) return;
      final pg = await probe(s);
      if (pg != null) {
        s.ping = pg;
        alive.add(s);
      }
    });
    alive.sort(_cmpAlive);
    dTcp += alive.length;
    realTested = 0;
    realTotal = alive.length;
    final skipped = <Server>[];
    final okNow = <Server>[];
    var slowNow = 0; // BADPINGLOOP
    await pool<Server>(alive, fastWorkers, (s) async {
      if (abort || enough() || (smartOrder && _srcDead(s))) {
        skipped.add(s);
        return;
      }
      if (ipMode && s.ipLink == null && !s.ipTried) {
        s.ipTried = true;
        s.ipLink = await ipLinkFor(s);
      }
      final d0 = await _delayOf(s, t: _fgTimeout);
      // BADPINGLOOP: a server that answers but with a bad ping is not healthy
      final slow = d0 != null &&
          d0 > badPingMs &&
          badPingRounds < badPingMaxRounds;
      final d = slow ? null : d0;
      if (slow) {
        slowNow++;
        fastTested++;
        realTested++;
        totalTested++;
        return;
      }
      if (d != null) {
        _svcOf(s).then((v) {
          s.svc = v;
        }).catchError((_) {}); // MULTICHK, PERFPATCH: not awaited
      }
      fastTested++;
      if (d != null) {
        fastOk++;
        okNow.add(s);
      }
      _record(s, d);
      realTested++;
      _set('تست سریع $realTested/${alive.length} • '
          'سالم:${_usable().length} • ($fastOk/$fastTested)');
    });
    // AI row: only the servers that passed the quick delay test are checked
    // for Gemini (through the real route, one by one)
    if (row == 'r:ai' && !abort) {
      okNow.sort((a, b) => (a.ping ?? 99999).compareTo(b.ping ?? 99999));
      var gi = 0;
      for (final s in okNow) {
        if (abort || enough()) break;
        if (s.ai != null) continue;
        if (_gemSkip(s)) {
          s.ai = false; // exit country without Gemini: no test needed
          continue;
        }
        gi++;
        _set('بررسی Gemini $gi/${okNow.length} • '
            'سالم:${_usable().length}');
        final tunnelMode = viaVpn;
        if (await _start(s, proxyOnly: !tunnelMode)) {
          if (tunnelMode ||
              await waitProxyPort(max: const Duration(seconds: 4))) {
            var ok = await geminiOpens(direct: tunnelMode);
            if (!ok && !gemDefinite) ok = await geminiOpens(direct: tunnelMode);
            s.ai = ok;
            if (ok) _saveSoon();
          }
        }
        await _stopCore();
      }
    }
    pending.insertAll(0, skipped);
    // BADPINGLOOP: found some, but all of them had a bad ping -> the next
    // quick test starts right away (the search loop keeps going)
    if (okNow.isEmpty && slowNow > 0) {
      badPingRounds++;
      dbg('همه‌ی سرورهای پیداشده پینگ بد داشتند ($slowNow) • '
          'تست سریع بعدی فوری • دور $badPingRounds/$badPingMaxRounds');
    }
    if (fastOk == 0 && fastTested >= 300) {
      fastOk = 0;
      fastTested = 0;
      _set('تست سریع جواب نداد؛ دوباره تست سریع...');
    }
    if (mounted) setState(() {});
  }

  // Foreground test: TCP filter in parallel, then a real request one by one.
  // viaVpn = true: through the real VPN tunnel (phone beeps on every test).
  // viaVpn = false: silent local proxy-only core (falls back to VPN if the
  // proxy port never works on this phone). OpenVPN is always tested through
  // the real tunnel.
  Future<void> _testBatchSeq(List<Server> batch, bool Function() enough,
      {required bool keepUp, String? row}) async {
    _set('پیش‌فیلتر TCP روی ${batch.length} سرور...');
    final alive = await _tcpFilter(batch);
    alive.sort(_cmpAlive);
    dTcp += alive.length;
    realTested = 0;
    realTotal = alive.length;
    final tried = <Server>{};
    for (final s in alive) {
      if (abort || enough()) break;
      if (tunFailRun >= 6) {
        logError('اندروید تونل VPN نمی‌سازد؛ اپ را ببند و دوباره باز کن');
        break;
      }
      tried.add(s);
      if (row == 'r:ai' && _gemSkip(s)) {
        s.ai = false; // exit country without Gemini: no test needed
        continue;
      }
      final isO = s.ovpn;
      final tunnelMode = (viaVpn || isO) && row != 'r:ai';
      _set('تست ${realTested + 1}/${alive.length} • TCP:$dTcp • '
          'سالم:${_usable().length}${tunnelMode ? ' • VPN' : ''}');
      if (ipMode && s.ipLink == null && !s.ipTried) {
        s.ipTried = true;
        s.ipLink = await ipLinkFor(s);
      }
      int? d;
      var portFail = false;
      final proxyOnly = !tunnelMode;
      if (await _start(s, proxyOnly: proxyOnly)) {
        if (!proxyOnly ||
            await waitProxyPort(max: const Duration(seconds: 4))) {
          portFailRun = 0;
          d = await pingProxy(
              total: isO ? const Duration(seconds: 6) : delayTimeout,
              direct: tunnelMode);
          if (d != null && d < minPingMs) {
            dFake++; // too fast to be a real ping
            d = null;
          }
          // AI row: does Gemini open through this server?
          if (d != null && row == 'r:ai') {
            _set('بررسی باز شدن Gemini روی ${s.name}...');
            // two tries: one flaky request must not throw away a good server
            var ok = await geminiOpens(direct: tunnelMode);
            if (!ok && !gemDefinite) ok = await geminiOpens(direct: tunnelMode);
            s.ai = ok;
            if (ok) _saveSoon();
          }
        } else {
          portFail = true;
          portFailRun++;
        }
        tunFailRun = 0;
      } else if (!proxyOnly && lastStartNoTunnel) {
        portFail = true; // Android built no tunnel: not the server's fault
        tunFailRun++;
      }
      // VPN mode: the tunnel is already up on a good server, keep it
      if (d != null &&
          tunnelMode &&
          keepUp &&
          (row != 'r:ai' || s.ai == true)) {
        _record(s, d);
        realTested++;
        upServer = s;
        break;
      }
      await _stopCore(); // fully down before the next start
      if (portFail) {
        pending.add(s); // not the server's fault
      } else {
        _record(s, d);
        if (!tunnelMode) {
          pxTested++;
          if (d != null) pxOk++;
        }
      }
      realTested++;
      if (!viaVpn &&
          ((portFailRun >= 2 && totalOk == 0 && pxOk == 0) ||
              (pxTested >= 25 && pxOk == 0))) {
        viaVpn = true;
        _set('تست بی‌صدا کار نکرد؛ تست از طریق VPN');
      }
    }
    pending.insertAll(0, alive.where((s) => !tried.contains(s)));
    if (mounted) setState(() {});
  }

  // MULTICHK: does this server also reach Telegram/YouTube/Instagram/Pornhub?
  Future<int> _svcOf(Server s) async {
    if (s.ovpn) return 15;
    var m = 0;
    const urls = ['https://web.telegram.org/', 'https://www.youtube.com/generate_204', 'https://www.instagram.com/', 'https://www.pornhub.com/'];
    try {
      final cfg = V2ray.parseFromURL(s.useLink).getFullConfiguration();
      final rs = await Future.wait(urls.map((u) => v2ray
          .getServerDelay(config: cfg, url: u)
          .timeout(const Duration(seconds: 8), onTimeout: () => -1)
          .catchError((_) => -1)));
      for (var i = 0; i < 4; i++) {
        if (rs[i] > 0) m |= (1 << i);
      }
    } catch (_) {}
    return m;
  }

  // one ping through the core's own delay test (the VPN is never touched).
  // null = dead, or too fast to be a real ping
  Future<int?> _delayOf(Server s, {Duration? t, String? url}) async {
    if (s.ovpn) return null;
    final tt = t ?? delayTimeout;
    // NORMAL: only plain config (variant 0). Matrix only if nationalMode.
    // ultraMode alone no longer enables matrix during ordinary connect tests.
    final useMatrix = nationalMode;
    final multi = useMatrix;
    final order = useMatrix ? _natOrder(s, full: _resFull) : const [0];
    // NATBUDGET: one server may only use a limited time per pass; the rest of
    // its variants continue in the next pass (natCursorAdvance)
    final budget = multi ? natBudget(full: _resFull) : null;
    final bsw = Stopwatch()..start();
    var genTried = 0;
    // plain TCP check (once, lazily): when the port is closed, only variants
    // that change the address / port / DNS can still help, the rest are skipped
    bool? tcpOk;
    for (var i = 0; i < order.length; i++) {
      if (i > 0 && abort) break;
      if (budget != null && i > 0 && bsw.elapsed > budget) break;
      final code = order[i];
      final v = code % _natCodeBase;
      // LIVE UI: which variant / dimension is under test right now
      if (multi && (i == 0 || i % 2 == 0 || i == order.length - 1)) {
        final vn = (v >= 0 && v < _natVarNames.length)
            ? _natVarNames[v]
            : 'حالت $v';
        final dims = (v > 0 && v < _natSpecs.length)
            ? _natDims(_natSpecs[v]).take(3).join(' · ')
            : '';
        _set('ماتریس ${i + 1}/${order.length} • ${s.name}\n'
            'حالت: $vn${dims.isEmpty ? '' : '\n$dims'}');
      }
      if (i >= 3 && s.ipLink == null && !_natChangesAddr(v)) {
        tcpOk ??= s.isIp || (await probe(s)) != null;
        if (!tcpOk) continue;
      }
      final u = _natUrlFor(code, url);
      final to = i == 0
          ? tt
          : Duration(seconds: min(tt.inSeconds, i > 60 ? 5 : (i > 12 ? 6 : 9)));
      if (v >= _natBaseCount) genTried++;
      final d = await _delayOnce(s, v, to, u);
      if (d != null) {
        if (multi) {
          if (natVar[_nk(s)] != v) {
            final vn = (v >= 0 && v < _natVarNames.length)
                ? _natVarNames[v]
                : '#$v';
            dbg('ماتریس: ${s.name} با حالت «$vn» جواب داد');
            _set('پیدا شد • ${s.name} • حالت: $vn');
          }
          natVarSet(s, v);
        }
        return d;
      }
    }
    if (multi && genTried > 0) natCursorAdvance(s, genTried);
    return null;
  }

  Future<int?> _delayOnce(Server s, int v, Duration tt, String? url) async {
    try {
      final cfg = natCfg(s, v);
      final rr = await v2ray
          .getServerDelay(config: cfg, url: url ?? delayTestUrl)
          .timeout(Duration(seconds: tt.inSeconds + 5), // PERFPATCH
              onTimeout: () => -1);
      final int r = rr is int ? rr : (int.tryParse('$rr') ?? -1);
      if (r > 0 && r >= minPingMs) return r;
    } on TypeError {
      // a malformed link / odd plugin answer: this server is simply unusable
      s.badAt = DateTime.now();
    } catch (_swE) { _swl('_delayOf#1', _swE);}
    return null;
  }

  // Standby search while connected: the core's own delay test, so the active
  // VPN is never stopped or restarted. [bgWorkers] tests run in parallel.
  Future<void> _testBatchDelay(
      List<Server> batch, bool Function() enough) async {
    realTested = 0;
    realTotal = batch.length;
    final skipped = <Server>[];
    await pool<Server>(batch, nationalMode ? natWorkers : bgWorkers,
        (s) async {
      if (abort || !connected || enough() || (smartOrder && _srcDead(s))) {
        skipped.add(s);
        return;
      }
      if (ipMode && s.ipLink == null && !s.ipTried) {
        s.ipTried = true;
        s.ipLink = await ipLinkFor(s);
      }
      final d = await _delayOf(s, t: _bgTimeout);
      bgTested++;
      if (d != null) bgOk++;
      _record(s, d);
      realTested++;
      if (connected) {
        _set('${_connStatus()} • جستجو $realTested/${batch.length}');
      }
      // the healthy servers are re-checked in between (every 25 tests)
      if (realTested % 25 == 0 && connected && !abort) {
        await _recheckStandby();
      }
    });
    pending.insertAll(0, skipped);
    if (bgOk == 0 && bgTested >= 30) {
      bgTested = 0; // RETRYPATCH: never disable, keep testing
      bgOk = 0;
    }
    if (mounted) setState(() {});
  }

  // Re-test the healthy servers that were not checked for a while (the
  // never-checked ones, e.g. saved from the last session, come first).
  // A server is only deleted after [missLimit] failed re-checks in a row; a
  // server that still works stays (it is never dropped just for being old).
  Future<void> _recheckStandby() async {
    if (rechecking) return;
    rechecking = true;
    try {
      final now = DateTime.now();
      final list = good
          .where((s) =>
              !s.ovpn &&
              !identical(s, current) &&
              (s.checkedAt == null ||
                  now.difference(s.checkedAt!) > recheckAfter))
          .toList()
        ..sort((a, b) => (a.checkedAt?.millisecondsSinceEpoch ?? 0)
            .compareTo(b.checkedAt?.millisecondsSinceEpoch ?? 0));
      await pool<Server>(list.take(6).toList(), bgWorkers, (s) async {
        if (!connected || abort || !wantVpn) return;
        final d = await _delayOf(s, t: _bgTimeout);
        s.checkedAt = DateTime.now();
        if (d == null) {
          if (++s.miss >= missLimit) {
            good.remove(s);
            failed[s.key] = DateTime.now();
          }
        } else {
          s.miss = 0;
          s.ping = d;
          s.badAt = null;
        }
      });
    } finally {
      rechecking = false;
    }
    if (mounted && inForeground) setState(() {});
  }

  // SPEEDSWITCHPATCH: stay connected; when no other healthy server is left
  // (dead, or real speed under minSpeedKB) ONE quick parallel test looks for
  // about 45 new servers. At most once every 3 minutes.
  Future<void> _refillRun() async {
    if (refilling || searching || busy || switching || !connected) return;
    if (!wantVpn || abort || appGone || current?.ovpn == true) return;
    final now = DateTime.now();
    if (now.difference(lastSwitch) < const Duration(seconds: 25)) return;
    final okLeft = _usable()
        .where((s) =>
            !identical(s, current) &&
            s.ovpn == _ovMode &&
            !s.personal &&
            s.miss == 0 &&
            !((s.speed ?? 99) * 1024 < minSpeedKB))
        .length;
    if (okLeft >= 2) return;
    final gap = okLeft == 0
        ? const Duration(seconds: 45)
        : const Duration(minutes: 3);
    if (now.difference(lastRefill) < gap) return;
    refilling = true;
    lastRefill = now;
    try {
      _set('سرور آماده کم است؛ تست سریع برای سرور جدید...');
      await _findGood(_ready() + 6);
    } catch (e) {
      logError(e);
    }
    refilling = false;
    _saveCache();
    if (mounted && connected) _set(_connStatus());
  }

  // Standby search while connected without touching the connection.
  // It never really stops: new servers keep being tested, the healthy ones
  // are re-checked, dead ones are deleted, and the list stays sorted. When the
  // whole list is tested a new one is downloaded and the cycle goes on.
  // It keeps running when the app is minimized (the VPN service keeps the
  // process alive).
  // STANDBYLOGPATCH: writes WHY the background search does not run
  String _sbLast = '';
  DateTime _sbAt = DateTime.fromMillisecondsSinceEpoch(0);
  void _sbWhy() {
    try {
      var r = 'OK';
      if (searching) {
        r = 'در حال جستجو (طبیعی)';
      } else if (busy) {
        r = 'busy';
      } else if (switching) {
        r = 'switching';
      } else if (!connected) {
        r = 'connected=0';
      } else if (bgDisabled) {
        r = 'bgDisabled (30 تست اول همه ناموفق بود)';
      } else if (!wantVpn) {
        r = 'wantVpn=0';
      } else if (abort) {
        r = 'abort';
      } else if (upBusy) {
        r = 'upBusy';
      } else if (appGone) {
        r = 'appGone';
      } else if (current?.ovpn == true) {
        r = 'OpenVPN';
      } else if (DateTime.now().difference(lastSwitch) <
          const Duration(seconds: 25)) {
        r = 'settling<25s';
      } else if (rechecking) {
        r = 'rechecking=1';
      }
      final now = DateTime.now();
      if (r == _sbLast && now.difference(_sbAt) < const Duration(seconds: 90)) {
        return;
      }
      _sbLast = r;
      _sbAt = now;
      dbg('جستجوی پس‌زمینه: $r • autoUpgrade=$autoUpgrade '
          'bgWorkers=$bgWorkers rechecking=$rechecking '
          'تست‌شده=$bgTested موفق=$bgOk صف=${pending.length}');
    } catch (_) {}
  }

  Future<void> _standbyRun() async {
    _sbWhy(); // STANDBYLOGPATCH
    if (bgSearchOff ||
        searching ||
        busy ||
        switching ||
        !connected ||
        bgDisabled) {
      return;
    }
    if (!wantVpn || abort || upBusy || appGone) return;
    // OpenVPN has no silent standby test: replacements are tested when needed
    if (current?.ovpn == true) return;
    // let the new connection settle before any background test runs
    if (DateTime.now().difference(lastSwitch) < const Duration(seconds: 25)) {
      return;
    }
    const gap = Duration(seconds: 4);
    if (DateTime.now().difference(lastStandby) < gap) return;
    if (nationalMode && !_natFetched) {
      _natFetched = true; // NATIONALPATCH
      listTime = null; // forces a new download (through the VPN)
      lastFetchTry = DateTime(2000);
      try {
        await _loadPending(bg: true, exhausted: true);
      } catch (e) {
        logError(e);
      }
    }
    try {
      await _recheckStandby();
      if (autoUpgrade) {
        await _findGood(manualSpeedMax, bg: true, explore: true);
      }
    } catch (e) {
      logError(e);
    }
    lastStandby = DateTime.now();
    _saveCache(); // healthy servers stay on disk for the next start
    if (mounted && connected) {
      _set(_connStatus());
    }
  }

  // ---------- connect ----------
  // OpenVPN start: the engine must report "connected" and a tun interface
  // must exist (same rule as the V2Ray tunnel guard)
  Future<bool> _startOvpn(Server s) async {
    // OpenVPN engine is intentionally removed from this build.
    // Keep the parse / paste paths so old personal configs do not crash,
    // but never attempt a real connection.
    lastFail = 'پروتکل OpenVPN در این نسخه پشتیبانی نمی‌شود — از VLESS / VMess / Trojan / SS استفاده کنید';
    dbg('OpenVPN: موتور حذف شده • ${s.name}');
    ovpnActive = false;
    try {
      await _stopV2();
    } catch (_) {}
    return false;
  }

  // proxyOnly = silent test core (used by the tests).
  // proxyMode (setting) = the REAL connection is also only a local proxy:
  // no VPN permission, no tunnel, no key icon.
  Future<bool> _start(Server s, {bool proxyOnly = false}) async {
    lastStartNoTunnel = false;
    lastFail = '';
    if (s.ovpn) return _startOvpn(s);
    final po = proxyOnly || proxyMode;
    try {
      final nv = natVarFor(s); // NATULTRA: same variant that passed the test
      final base = natCfg(s, nv, reuse: true); // same port / clean IP as the test
      // REALIBLE: real VPN config must match the test config as closely as
      // possible. Heavy Mux/Fragment/routing made many free servers "connect"
      // while Telegram/Instagram/YouTube stayed dead. Only light DNS is added.
      final cfg = proxyOnly
          ? base
          : _reliableVpnCfg(base);
      // NO_ACTIVITY: requestPermission needs a live Activity. Skip/catch when
      // the app is in background so parallel starts do not spam PlatformException.
      if (!po) {
        if (!inForeground && !vpnPermOk) {
          lastFail = 'Activity در دسترس نیست (اپ در پس‌زمینه)';
          return false;
        }
        try {
          if (inForeground || !vpnPermOk) {
            if (!await v2ray.requestPermission()) {
              lastFail = 'مجوز VPN داده نشد';
              return false;
            }
            vpnPermOk = true;
          }
          // in background with permission already granted: no dialog needed
        } on PlatformException catch (e) {
          if ('${e.code}'.contains('NO_ACTIVITY') ||
              '${e.message}'.contains('Activity is not available')) {
            lastFail = 'Activity در دسترس نیست برای مجوز VPN';
            return false;
          }
          rethrow;
        }
      }
      if (!proxyOnly) {
        // a silent proxy-only core from the tests must be fully gone before
        // the real VPN service starts, or the tunnel can fail to come up
        if (lastState == 'CONNECTED' || lastState == 'CONNECTING' || ovpnActive) {
          await _stopCore();
        } else {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }
      if (po) {
        await v2ray.startV2Ray(
            remark: s.name, config: cfg, proxyOnly: true);
        if (proxyOnly) return true;
        // proxy mode as the real connection: the local proxy port must open
        if (!await waitProxyPort(max: const Duration(seconds: 8))) {
          lastFail = 'پورت پروکسی باز نشد (هسته بالا نیامد)';
          await _stopCore();
          return false;
        }
        tunWarn = false;
        return true;
      }
      bool? t;
      var ready = false;
      // National / slow networks: give the core and the OEM VPN service more time
      final connWait = (nationalMode || indestructibleMode)
          ? const Duration(seconds: 22)
          : const Duration(seconds: 15);
      final tunWait1 = (nationalMode || indestructibleMode) ? 1200 : 700;
      final tunWait2 = (nationalMode || indestructibleMode) ? 1500 : 900;
      for (var attempt = 0; attempt < 2; attempt++) {
        connSig = Completer<bool>();
        // blockedApps = apps that skip the VPN (null when none are chosen,
        // so the behaviour is exactly the same as before)
        await v2ray.startV2Ray(
            remark: s.name,
            config: cfg,
            proxyOnly: false,
            blockedApps: bypassApps.isEmpty ? null : bypassApps);
        // the core must report CONNECTED (it can hang in CONNECTING)
        ready = await connSig!.future
            .timeout(connWait, onTimeout: () => false);
        t = null;
        if (ready) {
          // give the tunnel time to appear (OEM devices can be slow)
          await Future.delayed(Duration(milliseconds: tunWait1));
          t = await tunUp();
          if (t == false) {
            await Future.delayed(Duration(milliseconds: tunWait2));
            t = await tunUp();
          }
          // one more chance on national: some OEMs expose tun late
          if (t == false && (nationalMode || indestructibleMode)) {
            await Future.delayed(const Duration(milliseconds: 1200));
            t = await tunUp();
          }
        }
        if (ready && t != false) break;
        // no core / no VPN tunnel: restart the VPN once
        if (attempt == 0) await _stopCore();
      }
      tunWarn = !ready || t == false;
      if (tunWarn) {
        // Android built no tunnel: a "direct" ping would still pass, so this
        // must count as a failed start, not as a working server
        lastFail = !ready
            ? 'هسته به حالت CONNECTED نرسید (کانفیگ را هسته نپذیرفت؟)'
            : 'اندروید تونل VPN نساخت (tun پیدا نشد)';
        lastStartNoTunnel = true;
        await _stopCore();
        return false;
      }
      lastStartNoTunnel = false;
      return true;
    } catch (e) {
      if (_isNoActivity(e)) {
        // quiet: no red PlatformException on the home screen
        lastFail = 'Activity در دسترس نیست برای مجوز VPN';
        dbg('شروع هسته: Activity نبود • ${s.name}');
        if (!inForeground && wantVpn) pendingFailover = true;
        return false;
      }
      logError(e);
      lastFail = 'خطا: $e';
      if (!inForeground && wantVpn) pendingFailover = true;
      return false;
    }
  }

  void _onConnected(Server s) {
    badPingRounds = 0; // BADPINGLOOP
    current = s;
    plusHistAdd(s);
    connBaseDelay = s.ping;
    betterRun = 0;
    aiGen++; // FASTPATCH-AI: analyse+apply after ANY connection
    _aiLoop(aiGen);
    // the personal server has its own row, it never joins the healthy list
    if (!s.personal && !good.contains(s)) good.add(s);
    upServer = null;
    fails = 0;
    slowCount = 0;
    lowSpeed = 0;
    badPingRun = 0;
    noData = 0;
    stallRun = 0;
    siteFail = 0;
    siteSeen = false;
    siteNever = 0;
    needTrial = false;
    speedTick = 0;
    wantVpn = true;
    errorLog.value = '';
    if (tunWarn) {
      errorLog.value =
          'تونل نیست • اینترفیس‌ها: $tunNames • وضعیت هسته: $lastState';
    }
    lastSwitch = DateTime.now();
    connected = true;
    // remembered so the app can pick the tunnel up again after being closed
    SharedPreferences.getInstance()
        .then((p) => p.setString('last_conn', s.link));
    if (mounted) setState(() {});
    if (mounted) uiJoinPrompt(context);
    _set(_connStatus());
    autoAiAfterConnect();
    // _showChannelPrompt حذف شد — با uiJoinPrompt تکراری بود و دو دیالوگ کانال نشان می‌داد
    // TURBO: بعد از هر اتصال واقعی حتماً توربو سرعت فعال شود
    // مهم: تست سرعت را قبل از توربو شروع نکن — توربو هسته را ریستارت می‌کند
    // و تست سرعت ممکن بود صفر ببیند و به‌اشتباه failover کند
    if (!s.ovpn) {
      turboSpeed = true;
      muxEnabled = true;
      muxConc = max(muxConc, 32);
      if (!nationalMode) fragEnabled = false;
      unawaited(_turboAfterConnect(s)); // خودش در پایان _measureCurrent را صدا می‌زند
    } else {
      unawaited(_measureCurrent(s));
    }
  }

  // TURBO SPEED ============================================================
  // بعد از اتصال: Fragment خاموش + Mux با concurrency بالا + یک ریستارت تونل
  // تا تنظیمات واقعاً اعمال شوند. در صورت شکست، Mux را خاموش نمی‌کنیم.
  bool _turboBusy = false;
  DateTime? _lastTurboAt;
  Future<void> _turboAfterConnect(Server s) async {
    turboSpeed = true;
    if (_turboBusy || !wantVpn || !connected) return;
    if (!identical(current, s) || s.ovpn) return;
    // جلوگیری از توربو پشت‌سرهم (مثلاً بعد از _restartTunnel که دوباره _onConnected می‌زند)
    if (_lastTurboAt != null &&
        DateTime.now().difference(_lastTurboAt!) < const Duration(seconds: 45)) {
      unawaited(_measureCurrent(s));
      return;
    }
    // بعد از اتصال هنوز busy=true است (_runBusy). صبر کن تا آزاد شود
    // قبلاً if (busy) return باعث می‌شد توربو هیچ‌وقت اجرا نشود
    for (var i = 0; i < 40 && (busy || switching); i++) {
      await Future.delayed(const Duration(milliseconds: 150));
      if (!wantVpn || !connected || !identical(current, s) || abort) return;
    }
    if (!wantVpn || !connected || !identical(current, s) || abort) return;
    if (_turboBusy) return;
    if (busy || switching) {
      // هنوز مشغول — توربو را رد کن ولی سرعت را بسنج
      unawaited(_measureCurrent(s));
      return;
    }
    _turboBusy = true;
    _lastTurboAt = DateTime.now();
    final curV = natVarFor(s);
    final prevV = curV;
    // در طول ریستارت توربو، واچ‌داگ نباید تعویض کند
    final wasSwitching = switching;
    switching = true;
    try {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!wantVpn || !connected || !identical(current, s) || abort) return;

      _set('توربو سرعت: فعال‌سازی Mux و حذف Fragment...');

      // اهرم‌های قطعی سرعت
      turboSpeed = true;
      muxEnabled = true;
      muxConc = max(muxConc, 32);
      if (!nationalMode) fragEnabled = false;

      // حالت سبک (بدون Fragment/Noise) اگر لازم باشد
      final target = natIsHeavy(curV)
          ? (natSpeedVariant(s, prefer: curV % _natCodeBase) ?? 0)
          : (curV % _natCodeBase);
      natVar[_nk(s)] = target;

      // یک بار تونل را با تنظیمات توربو از نو بالا بیاور
      await _stopV2();
      final okStart = await _start(s);
      if (!okStart) {
        // برگرد به حالت قبلی ولی Mux را روشن نگه دار
        natVar[_nk(s)] = prevV;
        muxEnabled = true;
        muxConc = max(muxConc, 16);
        if (!nationalMode) fragEnabled = false;
        await _start(s);
        _set('توربو: تونل برگشت — Mux روشن ماند');
        if (mounted) setState(() {});
        return;
      }

      final p = await pingAny(
          total: const Duration(seconds: 8), direct: true);
      if (p == null) {
        // پینگ توربو رد شد — حالت قبل، اما Mux روشن
        natVar[_nk(s)] = prevV;
        muxEnabled = true;
        if (!nationalMode) fragEnabled = false;
        await _stopV2();
        await _start(s);
        _set('توربو: پینگ رد شد — اتصال پایدار با Mux');
        if (mounted) setState(() {});
        return;
      }

      natVarSet(s, target);
      // ذخیره تنظیمات تا بعداً خاموش نشود
      try {
        await _saveSettings();
      } catch (_) {}

      dbg('توربو سرعت فعال • حالت $target • Mux $muxConc • پینگ ${p}ms');
      _set('✅ توربو سرعت فعال • Mux $muxConc • بدون Fragment');
      if (mounted) setState(() {});
      unawaited(_measureCurrent(s));
    } catch (e) {
      logError(e);
      try {
        // حتی در خطا Mux را خاموش نکن
        muxEnabled = true;
        if (!nationalMode) fragEnabled = false;
        turboSpeed = true;
        if (wantVpn && identical(current, s)) {
          await _stopV2();
          await _start(s);
        }
        _set('توربو: خطا — اتصال با Mux برقرار شد');
      } catch (_) {}
    } finally {
      _turboBusy = false;
      switching = wasSwitching;
      // کمی تأخیر تا رویدادهای هسته قاطی نشوند
      _unlockLater();
    }
  }

  String _short(String t, [int n = 90]) => t.length > n ? t.substring(0, n) : t;

  // NATLADDER / PHANTOM LADDER: other variants of one server through the REAL
  // tunnel. Expanded for ultraMode: tries many more ranked variants so a
  // server that almost works is not discarded after one failed traffic check.
  Future<bool> _natLadder(Server s) async {
    final first = natVarFor(s);
    try {
      final tried = <int>{first};
      final takeN = (nationalMode || indestructibleMode)
          ? 12
          : (ultraMode ? 8 : 4);
      final cand = _natOrder(s, full: true)
          .where((c) => c < _natCodeBase)
          .where((v) => tried.add(v))
          .take(takeN)
          .toList();
      for (final v in cand) {
        if (abort || !wantVpn) break;
        _set('اتصال به ${s.name} با حالت «${_natSpecs[v].name}»...');
        natVar[_nk(s)] = v; // _start() reads the variant through natVarFor
        if (!await _start(s)) continue;
        final p = await pingAny(
            total: Duration(seconds: nationalMode ? 12 : 9), direct: true);
        if (p != null) {
          natVarSet(s, v);
          dbg('نردبان: ${s.name} با حالت «${_natSpecs[v].name}» از تونل واقعی جواب داد');
          return true;
        }
        await _stopV2();
      }
    } catch (e) {
      logError(e);
    }
    // nothing worked: forget the variant that only passed the core test
    natVar.remove(_nk(s));
    return false;
  }

  // FIXSOCIAL2: in VPN mode this app's OWN traffic bypasses the tunnel (and the
  // core has no local port), so "direct" tests only see the phone's normal
  // internet: cloudflare/gstatic open there even with a dead server. The only
  // honest test is a silent proxy-only core (its local port works): Telegram /
  // Instagram / YouTube must open through it BEFORE the real VPN is started.
  // true = opens, false = does not open, null = could not test.
  Future<bool?> _preSocialCheck(Server s) async {
    try {
      if (s.ovpn || proxyMode) return null;
      if (!await _start(s, proxyOnly: true)) return null;
      if (!await waitProxyPort(max: const Duration(seconds: 6))) {
        await _stopCore();
        return null;
      }
      final r = await Future.wait([
        _siteOpens('https://telegram.org/', viaCore: true),
        _siteOpens('https://www.instagram.com/', viaCore: true),
        _siteOpens('https://www.youtube.com/generate_204', viaCore: true),
        _siteOpens('https://www.gstatic.com/generate_204', viaCore: true),
      ]);
      await _stopCore();
      await Future.delayed(const Duration(milliseconds: 300));
      dbg('تست بی‌صدا ${s.name}: telegram=${r[0]} instagram=${r[1]} '
          'youtube=${r[2]} gstatic=${r[3]}');
      return r[0] || r[1] || r[2];
    } catch (e) {
      logError(e);
      try {
        await _stopCore();
      } catch (_) {}
      return null;
    }
  }

  // [trust] = the server was already tested: skip the extra verification.
  // Pinned / manually added configs are always trusted (the user chose them):
  // they are connected as they are, and the watchdog replaces them only if
  // they really stay dead. The real reason of a failure is shown at the bottom.
  Future<bool> _connectLoop(List<Server> list, {bool trust = false}) async {
    var siteSkips = 0; // SITEPRECHECK: servers skipped because no site opened
    for (final s in list) {
      if (abort) return false;
      final pin = favs.containsKey(s.key);
      if (!trust && !pin && !nationalMode && !s.ovpn && !proxyMode) {
        _set('بررسی تلگرام/اینستاگرام روی ${s.name}...');
        final sc = await _preSocialCheck(s);
        if (abort) return false;
        if (sc == false) {
          siteSkips++;
          s.svc = 0;
          s.badAt = DateTime.now();
          errorLog.value = '${s.name}: تلگرام/اینستاگرام/یوتیوب باز نشد — سرور بعدی…';
          dbg('اتصال: ${s.name} رد شد — تلگرام/اینستاگرام/یوتیوب باز نشد • سرور بعدی');
          continue;
        }
      }
      _set('اتصال به ${s.name}...');
      if (!await _start(s)) {
        final noAct = lastFail.contains('Activity');
        // NO_ACTIVITY is temporary — do not blacklist the server
        if (!lastStartNoTunnel && !pin && !noAct) s.badAt = DateTime.now();
        if (noAct) {
          errorLog.value = 'مجوز VPN: Activity آماده نیست — تلاش بعدی…';
          // Give the Activity more time to come back (common after ad / screen)
          await Future.delayed(Duration(
              milliseconds: inForeground ? 800 : 1500));
          if (abort) return false;
          // up to 2 quiet retries (Activity may have resumed)
          var recovered = false;
          for (var r = 0; r < 2 && !recovered && !abort; r++) {
            if (inForeground || vpnPermOk) {
              if (await _start(s)) {
                recovered = true;
                break;
              }
            }
            await Future.delayed(const Duration(milliseconds: 700));
          }
          if (!recovered) {
            dbg('رد شد (Activity): ${s.name} • ${lastFail}');
            continue;
          }
          // success — fall through to post-start checks
        } else {
          errorLog.value =
              '${s.name}: ${lastFail.isEmpty ? 'شروع نشد' : lastFail}';
          final ip0 = await resolveHostIp(s.host);
          dbg(configFailMsg(
            s.link,
            'شروع هسته (_start)',
            lastFail.isEmpty ? 'شروع نشد' : lastFail,
            ovpnText: s.ovpnConf,
            knownIp: ip0,
          ));
          continue;
        }
      }
      if (!trust && !pin) {
        int? p;
        final pingT0 = DateTime.now(); // PINGLOGPATCH
        // National: more retries + longer waits — tunnel/DNS can be slow to settle
        final pingTries = nationalMode || indestructibleMode ? 5 : 2;
        final pingSec = nationalMode || indestructibleMode ? 14 : 7;
        for (var i = 0; i < pingTries && p == null && !abort; i++) {
          p = await pingAny(
              total: Duration(seconds: pingSec), direct: true);
          if (p == null) {
            await Future.delayed(Duration(
                milliseconds: nationalMode ? 600 : 300));
          }
        }
        dbg(p == null
            ? 'اتصال: ${s.name} هسته CONNECTED ولی پینگ از تونل رد نشد '
                '(${DateTime.now().difference(pingT0).inSeconds}s) • خطا: '
                '${_short(lastPingErr, 90)} • tun: $tunNames • برنامه‌های '
                'ردشده از VPN: ${bypassApps.length} • ایران مستقیم: $iranRoute'
            : 'پینگ از تونل ${p}ms (${DateTime.now().difference(pingT0).inSeconds}s) '
                '• ${s.name} • tun: $tunNames');
        if (p == null) {
          await _stopV2();
          // NATLADDER: the variant that passed the core test carried no real
          // traffic: try the next ranked variants of the SAME server first
          if ((nationalMode || ultraMode || indestructibleMode) &&
              !abort &&
              wantVpn &&
              await _natLadder(s)) {
            _onConnected(s);
            return true;
          }
          final ip1 = await resolveHostIp(s.host);
          dbg(configFailMsg(
            s.link,
            'پینگ از داخل تونل',
            lastPingErr.isEmpty ? 'بدون پاسخ' : lastPingErr,
            ovpnText: s.ovpnConf,
            knownIp: ip1,
          ));
          s.badAt = DateTime.now();
          errorLog.value = '${s.name}: وصل شد ولی اینترنت رد نشد '
              '(${_short(lastPingErr, 70)})';
          continue;
        }
        // BADPINGLOOP: connected but the ping through the tunnel is bad
        if (p > badPingMs && badPingRounds < badPingMaxRounds) {
          await _stopV2();
          s.badAt = DateTime.now();
          badPingRounds++;
          dbg('پینگ از تونل بد بود (${p}ms) • ${s.name} • '
              'سرور بعدی / تست سریع بعدی • دور $badPingRounds/$badPingMaxRounds');
          continue;
        }
      }
      // STRICT: Telegram / YouTube / Instagram must open through the tunnel.
      // Also runs under national mode (softer retries + ladder before reject).
      if (!trust && !pin) {
        final needSocial = !proxyMode;
        if (needSocial && !await _coreProxyOpen()) {
          // VPN mode: traffic goes via tun; still try site checks with viaCore
          dbg('چک سایت‌ها ${s.name}: پورت هسته ممکن است بسته باشد؛ تست مستقیم تونل');
        }
        if (needSocial || proxyMode) {
          _set('بررسی تلگرام/اینستا/یوتیوب روی ${s.name}...');
          if (proxyMode || (await tunUp()) != true) {
            await waitProxyPort(
                max: Duration(seconds: nationalMode ? 8 : 4));
          }
          if (abort) return false;

          Future<List<bool>> runSocial() async {
            try {
              final checks = await Future.wait([
                _siteOpens('https://telegram.org/', viaCore: true),
                _siteOpens('https://web.telegram.org/', viaCore: true),
                _siteOpens('https://www.youtube.com/generate_204', viaCore: true),
                _siteOpens('https://www.youtube.com/', viaCore: true),
                _siteOpens('https://www.instagram.com/', viaCore: true),
                _siteOpens('https://i.instagram.com/', viaCore: true),
                _siteOpens('https://cp.cloudflare.com/generate_204', viaCore: true),
                _siteOpens('https://www.gstatic.com/generate_204', viaCore: true),
              ]).timeout(const Duration(seconds: 12),
                  onTimeout: () => List<bool>.filled(8, false));
              return checks;
            } catch (_) {
              return List<bool>.filled(8, false);
            }
          }

          var r = await runSocial();
          if (abort) return false;
          bool tg = r[0] || r[1];
          bool yt = r[2] || r[3];
          bool ig = r[4] || r[5];
          bool socialOk = tg || yt || ig;
          // National / slow: one more pass after short settle
          if (!socialOk && (nationalMode || indestructibleMode)) {
            await Future.delayed(const Duration(milliseconds: 800));
            r = await runSocial();
            tg = r[0] || r[1];
            yt = r[2] || r[3];
            ig = r[4] || r[5];
            socialOk = tg || yt || ig;
          }
          dbg('چک سایت‌ها ${s.name}: tg=$tg yt=$yt ig=$ig '
              'cf=${r[6]} gs=${r[7]}');

          if (!socialOk &&
              (nationalMode || ultraMode || indestructibleMode) &&
              !abort &&
              wantVpn) {
            // Same server, other matrix variants — often fixes social path
            await _stopV2();
            if (await _natLadder(s)) {
              await waitProxyPort(
                  max: Duration(seconds: nationalMode ? 8 : 5));
              await Future.delayed(const Duration(milliseconds: 400));
              r = await runSocial();
              tg = r[0] || r[1];
              yt = r[2] || r[3];
              ig = r[4] || r[5];
              socialOk = tg || yt || ig;
              if (socialOk) {
                s.svc = (tg ? 1 : 0) | (yt ? 2 : 0) | (ig ? 4 : 0);
                if (s.svc == 0) s.svc = 1;
                _onConnected(s);
                return true;
              }
              await _stopV2();
            }
            // ladder left core down — reject and try next server
          }

          final sp = await measure(
              win: const Duration(seconds: 2),
              total: Duration(seconds: nationalMode ? 10 : 6),
              viaCore: true);
          if (abort) return false;
          final speedOk = sp != null && sp >= 0.08;
          final socialCount = (tg ? 1 : 0) + (yt ? 1 : 0) + (ig ? 1 : 0);
          // حداقل یکی از تلگرام/یوتیوب/اینستا باید باز شود
          final accept2 = socialCount >= 1 &&
              (socialCount >= 2 || speedOk || nationalMode);

          if (!accept2) {
            siteSkips++;
            s.svc = 0;
            s.badAt = DateTime.now();
            await _stopV2();
            final why =
                'تلگرام/اینستاگرام/یوتیوب از تونل باز نشد (tg=$tg yt=$yt ig=$ig)';
            dbg('اتصال: ${s.name} رد شد — $why • سرور بعدی');
            errorLog.value = '${s.name}: $why — سرور بعدی…';
            continue;
          }
          if (sp != null) s.speed = sp;
          s.svc = (tg ? 1 : 0) | (yt ? 2 : 0) | (ig ? 4 : 0);
          if (s.svc == 0) s.svc = 1;
          dbg('اتصال: ${s.name} اجتماعی OK • tg=$tg yt=$yt ig=$ig • '
              'سرعت=${sp?.toStringAsFixed(2) ?? "-"} MB/s');
        }
      }
      _onConnected(s);
      return true;
    }
    return false;
  }

  // REAL speed test right after connecting (this replaces the old "minimum
  // valid ping" filter). A server with a fake / empty ping that moves no data
  // is detected here and replaced; the real speed is also saved for ranking.
  Future<void> _measureCurrent(Server s) async {
    double? sp;
    for (var i = 0; i < 3 && sp == null; i++) {
      // FIXSPEED: one failed download must not kill a working server;
      // the 2nd/3rd try uses the small file
      sp = await measure(
          url: i == 0 ? speedUrl : smallSpeedUrl,
          win: const Duration(seconds: 3),
          total: const Duration(seconds: 10),
          direct: true);
      if (!connected || !identical(s, current)) return;
    }
    dbg('سرعت واقعی ${s.name}: '
        '${sp == null ? 'داده‌ای نیامد' : '${sp.toStringAsFixed(2)} MB/s'}');
    // FIXSPEED: no download data, but a real site still opens through the
    // tunnel -> the server works (only the speed file was blocked), keep it
    var sitesAlive = false;
    if (sp == null) {
      final r = await Future.wait([
        _siteOpens('https://telegram.org/', viaCore: true),
        _siteOpens('https://www.instagram.com/', viaCore: true),
      ]);
      sitesAlive = r.any((x) => x);
      if (!connected || !identical(s, current)) return;
      if (sitesAlive) {
        dbg('سرعت ${s.name}: فایل تست نیامد ولی سایت‌ها از تونل باز شدند؛ سرور می‌ماند');
      }
    }
    if (sp != null) {
      s.speed = sp;
      s.speedAt = DateTime.now();
    } else if (!sitesAlive &&
        !s.personal &&
        !favs.containsKey(s.key) &&
        wantVpn &&
        !_turboBusy) {
      // no data at all: the ping was fake. Replace it
      // در طول توربو failover نکن (ریستارت عمدی هسته است)
      s.speed = 0;
      s.speedAt = DateTime.now();
      lastWhy = 'سرعت واقعی صفر بود';
      if (!busy && !switching) {
        await _failover();
        return;
      }
    }
    if (mounted) setState(() {});
    if (!searching) _set(_connStatus());
  }

  // PROFILES: one tap sets a group of settings
  void _applyProfile(String name) {
    switch (name) {
      case 'stable':
        // پایدار: تعویض کمتر، فقط نزدیک صفر یا سرور خیلی بهتر
        badPingMs = 3500;
        badPingLimit = 4;
        watchFailLimit = 4;
        minSpeedKB = 0; // تعویض با سرعت متوسط خاموش
        betterSwitch = true; // فقط با قانون ۵۰٪
        break;
      case 'fast':
        badPingMs = 1800;
        badPingLimit = 3;
        watchFailLimit = 3;
        minSpeedKB = 0;
        betterSwitch = true;
        turboSpeed = true;
        autoSpeed = true;
        speedTopN = max(speedTopN, 5);
        muxEnabled = true;
        muxConc = max(muxConc, 24);
        fragEnabled = false;
        sortSpeed = true;
        break;
      case 'weak':
        delayTimeout = const Duration(seconds: 14);
        badPingMs = 5000;
        badPingLimit = 4;
        watchFailLimit = 5;
        minSpeedKB = 0;
        betterSwitch = true;
        break;
      case 'turbo':
        turboSpeed = true;
        autoSpeed = true;
        speedTopN = max(speedTopN, 8);
        muxEnabled = true;
        muxConc = max(muxConc, 32);
        fragEnabled = false;
        sortSpeed = true;
        betterSwitch = true;
        minSpeedKB = 0; // دیگر با ۸۰۰KB تعویض نمی‌کند
        autoUpgrade = true;
        badPingMs = 2500;
        badPingLimit = 3;
        watchFailLimit = 3;
        break;
    }
    _saveSettings();
    _set('پروفایل اعمال شد');
  }

  // TURBO LEVERS: every throughput lever before connect (when turboSpeed is on).
  void _applyTurboLevers() {
    // توربو همیشه هدف است وقتی این تابع صدا زده می‌شود
    turboSpeed = true;
    // 1) real download test of the best candidates before picking one
    autoSpeed = true;
    if (speedTopN < 8) speedTopN = 8;
    // 2) Mux = parallel streams on one tunnel (concurrency بالاتر = سرعت بیشتر)
    muxEnabled = true;
    if (muxConc < 32) muxConc = 32;
    // 3) do not force global Fragment outside national crisis (Fragment سرعت را می‌کشد)
    if (!nationalMode) fragEnabled = false;
    // 4) rank by real speed, not ping
    sortSpeed = true;
    // 5) تعویض فقط نزدیک صفر یا سرور ۵۰٪ بهتر — minSpeedKB را بالا نبر
    // (قبلاً اگر ۰ بود به ۴۰۰ می‌رساند و باعث تعویض‌های زیاد می‌شد)
    betterSwitch = true;
  }

  Future<void> _profilesSheet() async {
    if (!mounted) return;
    Widget tile(IconData i, String t, String sub, VoidCallback f) => ListTile(
          leading: Icon(i),
          title: Text(t),
          subtitle: Text(sub),
          onTap: () {
            Navigator.pop(context);
            f();
          },
        );
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            tile(Icons.shield_moon_outlined, 'پایدار',
                'کمتر سرور عوض می‌کند', () => _applyProfile('stable')),
            tile(Icons.bolt_outlined, 'سریع', 'همیشه دنبال بهترین سرور',
                () => _applyProfile('fast')),
            tile(Icons.speed, 'توربو حداکثر سرعت',
                'همه اهرم‌های سرعت با هم: Mux ۱۶، بدون Fragment، تست سرعت قبل از وصل',
                () => _applyProfile('turbo')),
            tile(Icons.network_check, 'اینترنت ضعیف / نت ملی',
                'صبر بیشتر، تعویض کمتر', () => _applyProfile('weak')),
            tile(Icons.auto_awesome, 'سرور AI (Gemini/Grok)',
                'سرورهایی که API هوش مصنوعی را باز می‌کنند',
                () => connectRow('r:ai')),
          ]),
        ),
      ),
    );
  }

  String _fmtB(int b) {
    if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)}MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)}KB';
    return '${b}B';
  }

  String _connStatus() {
    final sp = current?.speed;
    final live = (liveDown > 0 || liveUp > 0 || totalDown > 0)
        ? ' • ↓${_fmtB(liveDown)}/s ↑${_fmtB(liveUp)}/s • مصرف ${_fmtB(totalDown + totalUp)}'
        : '';
    // show active matrix variant when ultra/national learned one
    var mode = '';
    final cur = current;
    if (cur != null) {
      final v = natVarFor(cur);
      if (v > 0 && v < _natVarNames.length) {
        mode = ' • حالت: ${_natVarNames[v]}';
      }
    }
    final q = qualityScore();
    return 'وصل شد${sp == null ? '' : ' • ${sp.toStringAsFixed(1)} MB/s'}$live$mode'
        ' • کیفیت: $q (${qualityLabel(q)})'
        ' • سالم: $standbyCount'
        '${proxyMode ? ' • حالت پروکسی (SOCKS 10808 / HTTP 10809)' : ''}'
        '${tunWarn ? ' • ⚠ تونل VPN ساخته نشد' : ''}'
        '${offlineOnly ? ' • آفلاین' : ''}'
        '${dataSaver ? ' • صرفه‌جویی' : ''}'
        '${lastWhy.isEmpty ? '' : ' • علت تعویض قبلی: $lastWhy'}';
  }

  // NATRESPATCH ---- folder of healthy servers (key 'natres2') ----
  final Map<String, _NatResItem> _resMap = {};
  Timer? _resT, _resSaveT;
  bool _resBusy = false, _resDirty = false, _resNext = false;
  DateTime? _resHold, _resLast, _resUi;
  int _resDone = 0, _resTotal = 0;
  static const int _resMax = 5000;
  static const Duration _resEvery = Duration(hours: 12); // auto re-test every 12 h
  bool _resFull = false; // second-chance pass: every variant

  Future<void> _resLoad() async {
    try {
      final p = await SharedPreferences.getInstance();
      final t = p.getString('natres2');
      if (t != null) {
        final j = jsonDecode(t);
        final last = (j['last'] as num?)?.toInt();
        if (last != null) {
          _resLast = DateTime.fromMillisecondsSinceEpoch(last);
        }
        for (final x in (j['items'] as List)) {
          final srv = Server.parse(x['l'] as String);
          if (srv == null || srv.ovpn) continue;
          final e = _NatResItem(srv.link, srv,
              DateTime.fromMillisecondsSinceEpoch((x['a'] as num).toInt()));
          final c = (x['c'] as num?)?.toInt();
          if (c != null) e.checked = DateTime.fromMillisecondsSinceEpoch(c);
          srv.ping = (x['p'] as num?)?.toInt();
          _resMap[srv.key] = e;
        }
      }
    } catch (e) {
      logError(e);
    }
    _resT?.cancel();
    _resT = Timer.periodic(const Duration(minutes: 2), (_) {
      _resDaily();
    });
    if (mounted) setState(() {});
  }

  Future<void> _resSave() async {
    if (!_resDirty) return;
    _resDirty = false;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          'natres2',
          jsonEncode({
            'last': _resLast?.millisecondsSinceEpoch,
            'items': _resMap.values
                .map((e) => {
                      'l': e.link,
                      'a': e.added.millisecondsSinceEpoch,
                      'c': e.checked?.millisecondsSinceEpoch,
                      'p': e.s.ping
                    })
                .toList()
          }));
    } catch (e) {
      _resDirty = true;
      logError(e);
    }
  }

  // a server passed a real test: it goes into the folder (or is refreshed)
  void _resAdd(Server srv) {
    try {
      if (srv.ovpn || srv.personal) return;
      final now = DateTime.now();
      final old = _resMap[srv.key];
      if (old != null) {
        old.checked = now;
        old.miss = 0;
        old.s.ping = srv.ping;
      } else {
        final c = Server.parse(srv.link);
        if (c == null) return;
        if (_resMap.length >= _resMax) {
          // full: the entry verified the longest ago makes room
          String? oldK;
          DateTime? oldT;
          _resMap.forEach((k, v) {
            final t = v.checked ?? v.added;
            if (oldT == null || t.isBefore(oldT!)) {
              oldT = t;
              oldK = k;
            }
          });
          if (oldK != null) _resMap.remove(oldK);
        }
        c.ping = srv.ping;
        final e = _NatResItem(srv.link, c, now);
        e.checked = now;
        _resMap[srv.key] = e;
      }
      _resDirty = true;
      _resSaveT ??= Timer(const Duration(seconds: 3), () {
        _resSaveT = null;
        _resSave();
      });
      final u = _resUi;
      if (mounted &&
          inForeground &&
          (u == null || now.difference(u) > const Duration(seconds: 5))) {
        _resUi = now;
        setState(() {});
      }
    } catch (e) {
      logError(e);
    }
  }

  // the folder servers join the healthy list (tested FIRST at the connect)
  int _resInject() {
    var n = 0;
    try {
      final keys = good.map((g) => g.key).toSet();
      for (final e in _resMap.values) {
        if (keys.contains(e.s.key)) continue;
        final c = Server.parse(e.link);
        if (c == null) continue;
        c.ping = e.s.ping;
        warmKeys.add(c.key);
        failed.remove(c.key);
        good.add(c);
        n++;
      }
    } catch (e) {
      logError(e);
    }
    return n;
  }

  // 12 h after the last check: ping again (automatic, VPN up or not). Works stay, fails get a second
  // chance at the end of the round and are deleted if they fail again.
  Future<void> _resDaily({bool force = false}) async {
    if (_resBusy || _resMap.isEmpty) return;
    // NATULTRA: the 12 h check also runs while the VPN is off (the core's
    // delay test never needs the tunnel); a user connect/search stops it
    final wasUp = connected && wantVpn;
    bool lost() => appGone || busy || switching || upBusy ||
        (wasUp ? (!connected || !wantVpn || abort) : searching);
    if (lost() || busy || switching || upBusy || (!wasUp && searching)) return;
    if (wasUp && current?.ovpn == true) return; // no silent test next to OpenVPN
    final now = DateTime.now();
    if (!force) {
      if (now.difference(lastSwitch) < const Duration(seconds: 60)) return;
      final h = _resHold;
      if (h != null && now.isBefore(h)) return;
    }
    final due = _resMap.values
        .where((e) => force || now.difference(e.checked ?? e.added) >= _resEvery)
        .toList()
      ..sort((a, b) => (a.checked ?? a.added).compareTo(b.checked ?? b.added));
    if (due.isEmpty) return;
    _resBusy = true;
    _resDone = 0;
    _resTotal = due.length;
    if (mounted) setState(() {});
    try {
      var tested = 0, passed = 0;
      var netDead = false; // nothing passes at all: the network is down
      Future<void> run(List<_NatResItem> l, List<_NatResItem> out) async {
        await pool<_NatResItem>(l, natWorkers, (e) async {
          if (netDead || lost()) return;
          final d = await _delayOf(e.s, t: _bgTimeout);
          if (lost()) return; // the VPN dropped: this result is not trusted
          tested++;
          _resDone++;
          if (d == null && tested >= 8 && passed == 0) netDead = true;
          if (d != null) {
            passed++;
            e.checked = DateTime.now();
            e.miss = 0;
            e.s.ping = d;
            _resDirty = true;
          } else {
            out.add(e);
          }
        });
      }

      final bad = <_NatResItem>[];
      await run(due, bad);
      if (lost()) return;
      if (netDead) {
        _resHold = DateTime.now().add(const Duration(hours: 1));
        return; // nothing is deleted when the whole network is down
      }
      final dead = <_NatResItem>[];
      if (bad.isNotEmpty) {
        _resTotal += bad.length;
        await Future.delayed(const Duration(seconds: 20)); // second chance
        if (lost()) return;
        _resFull = true; // every variant (fragment, fingerprint...) this time
        try {
          await run(bad, dead);
        } finally {
          _resFull = false;
        }
        if (lost()) return;
      }
      if (tested >= 5 && passed == 0) {
        // everything failed: the network is the problem, not the servers
        _resHold = DateTime.now().add(const Duration(hours: 1));
        return;
      }
      for (final e in dead) {
        _resMap.remove(e.s.key);
      }
      _resLast = DateTime.now();
      _resDirty = true;
      await _resSave();
    } catch (e) {
      logError(e);
    } finally {
      _resBusy = false;
      if (_resDirty) _resSave(); // partial progress is kept too
      if (mounted) setState(() {});
    }
  }

  String _resAgo(DateTime? t) {
    if (t == null) return 'هنوز تست نشده';
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 1) return 'همین الان';
    if (m < 60) return '$m دقیقه پیش';
    if (m < 48 * 60) return '${m ~/ 60} ساعت پیش';
    return '${m ~/ 1440} روز پیش';
  }

  String _resInfo() {
    final b = StringBuffer('آخرین تست کامل: ${_resAgo(_resLast)}');
    if (_resBusy) b.write('\nدر حال تست: $_resDone/$_resTotal');
    final h = _resHold;
    if (h != null && DateTime.now().isBefore(h)) {
      b.write('\nتست قبلی همه‌ی سرورها را خراب نشان داد؛ مشکل از نت بود، '
          'چیزی پاک نشد و بعداً دوباره تست می‌شود');
    }
    b.write('\nتست خودکار هر ۱۲ ساعت؛ سرور خراب حذف و سالم می‌ماند');
    return b.toString();
  }

  Future<void> _resMenu() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.folder_special_outlined),
              title: Text('پوشه‌ی سرورهای سالم: ${_resMap.length} سرور'),
              subtitle: Text(_resInfo()),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.public_off),
              title: const Text('اتصال با سرورهای پوشه (نت ملی)'),
              enabled: !busy && !connected && _resMap.isNotEmpty,
              onTap: () {
                Navigator.pop(ctx);
                natForce = true;
                _resNext = true;
                connect();
              },
            ),
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('جستجو در پوشه با نت جهانی'),
              enabled: !busy && !connected && _resMap.isNotEmpty,
              onTap: () {
                Navigator.pop(ctx);
                _resNext = true;
                connect();
              },
            ),
            ListTile(
              leading: const Icon(Icons.network_ping),
              title: const Text('تست پینگ پوشه همین الان'),
              subtitle: const Text('خراب‌ها حذف می‌شوند، سالم‌ها می‌مانند'),
              enabled: !busy && !_resBusy && _resMap.isNotEmpty,
              onTap: () {
                Navigator.pop(ctx);
                _resHold = null;
                _resDaily(force: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('خالی کردن پوشه'),
              enabled: _resMap.isNotEmpty && !_resBusy,
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    title: const Text('خالی کردن پوشه'),
                    content: Text(
                        'همه‌ی ${_resMap.length} سرور پوشه پاک شود؟'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dctx, false),
                          child: const Text('نه')),
                      TextButton(
                          onPressed: () => Navigator.pop(dctx, true),
                          child: const Text('پاک شود')),
                    ],
                  ),
                );
                if (ok == true) {
                  _resMap.clear();
                  _resDirty = true;
                  await _resSave();
                  if (mounted) setState(() {});
                }
              },
            ),
          ]),
        ),
      ),
    );
  }

  // NATBTNPATCH: in national mode the search never stops
  bool _natKeepOn = false;
  Server? _natKickFor;

  Future<void> _natKeep() async {
    if (_natKeepOn) return;
    _natKeepOn = true;
    var seen = false; // was connected at least once
    var idle = 0;
    try {
      while (mounted && nationalMode && !appGone) {
        await Future.delayed(const Duration(seconds: 2));
        if (connected) {
          seen = true;
          idle = 0;
          bgWorkers = max(natWorkers, indestructibleMode ? 8 : 4);
          autoUpgrade = true;
          autoCycle = true;
          // NATBG: while connected the background search is deeper (more
          // variants per server) and every healthy server goes into the folder
          if (natLevel < 3) natLevel = 3;
          if (bgDisabled) {
            // the "nothing worked in 30 tests" shutdown must never stick
            bgDisabled = false;
            bgTested = 0;
            bgOk = 0;
          }
          final cur = current;
          // new connection settled (4 s): skip the usual 25 s wait once
          if (cur != null &&
              !identical(cur, _natKickFor) &&
              DateTime.now().difference(lastSwitch) >
                  const Duration(seconds: 4)) {
            _natKickFor = cur;
            lastSwitch = DateTime.now().subtract(const Duration(seconds: 30));
          }
          if (!searching && !busy && !switching && !upBusy) {
            await _standbyRun();
          }
        } else if (!wantVpn && !busy) {
          // disconnected by the user (or the connect never succeeded)
          // INDESTRUCTIBLE: stay alive longer while still hunting
          final limit = indestructibleMode ? 90 : 15;
          if (seen || ++idle > limit) break;
        }
      }
    } catch (e) {
      logError(e);
    } finally {
      _natKeepOn = false;
    }
  }

  // NATIONALPATCH: is the international internet cut while the national
  // network works? Direct requests (the VPN is off when this runs).
  bool _natLoaded = false;
  bool _natFetched = false; // new list already downloaded on this connection

  Future<bool> _natOpen(String url) async {
    final c = HttpClient()
      ..findProxy = ((_) => 'DIRECT')
      ..connectionTimeout = const Duration(milliseconds: 2500);
    try {
      final req = await c
          .getUrl(Uri.parse(url))
          .timeout(const Duration(milliseconds: 3000));
      final res = await req.close().timeout(const Duration(milliseconds: 3000));
      return res.statusCode > 0;
    } catch (_) {
      return false;
    } finally {
      c.close(force: true);
    }
  }

  Future<void> _natDetect() async {
    if (connected) return;
    _natFetched = false;
    await natDetectOperator(); // NATULTRA: per-operator learning
    try {
      if (!_natLoaded) {
        _natLoaded = true;
        natGood.addAll(_resMap.keys); // FOLDERONLY
        await natLoadPersisted(); // NATULTRA
      }
      final r = await Future.wait([
        _natOpen('https://www.gstatic.com/generate_204'),
        _natOpen('https://cp.cloudflare.com/generate_204'),
        _natOpen('https://one.one.one.one/'),
        _natOpen('https://www.apple.com/library/test/success.html'),
        _natOpen('https://www.aparat.com/'),
        _natOpen('https://www.digikala.com/'),
      ]);
      var world = r[0] || r[1] || r[2] || r[3];
      final home = r[4] || r[5];
      // NATSLOW: the world answers but is throttled to a crawl -> same as cut
      if (world && !natForce) {
        final lat = await _tuneLatency('http://cp.cloudflare.com/generate_204');
        if (lat == null || lat > 3000) {
          world = false;
        } else if (lat > 1200) {
          final kb = await _tuneSpeedKB();
          if (kb != null && kb < 40) world = false;
        }
      }
      final was = nationalMode;
      if (natForce) {
        nationalMode = true; // NATBTNPATCH: forced by the button
      } else if (world) {
        nationalMode = false;
      } else if (home) {
        nationalMode = true;
      }
      if (nationalMode != was && mounted) {
        _set(nationalMode
            ? 'حالت شبکه ملی: اینترنت بین‌الملل قطع است؛ سرورهای ایران و سرورهای ذخیره‌شده اول تست می‌شوند'
            : 'اینترنت بین‌الملل وصل است؛ حالت عادی');
      }
    } catch (e) {
      logError(e);
    }
  }

  // SAVED / old healthy servers are tested FIRST (fast core delay test, the
  // VPN is not touched), best saved speed first: the ones that still work are
  // used right away, the dead ones are deleted after two failed checks (one
  // in each of two sessions). The check stops as soon as enough working
  // servers are found, so a connection is available in a few seconds.
  //
  // IMPORTANT for نت ملی: when international is cut, GitHub lists are often
  // unreachable. Previously-working / folder / natGood servers are then the
  // ONLY realistic way to connect. So in national / forced / indestructible
  // mode we ALWAYS re-test saved servers first (even if the user preferred
  // "only new" for normal mode).
  DateTime? _checkSavedAt;
  Future<void> _checkSaved() async {
    final forceSaved = nationalMode || natForce || indestructibleMode;
    if (!forceSaved) {
      // Normal mode: user request was "do NOT search from folder/saved —
      // only new ones". Keep that behaviour outside national mode.
      return;
    }
    // Avoid running twice in the same connect path (_doConnect + _acquireInner)
    if (_checkSavedAt != null &&
        DateTime.now().difference(_checkSavedAt!) <
            const Duration(seconds: 25)) {
      return;
    }
    _checkSavedAt = DateTime.now();
    bool stale(Server s) =>
        s.checkedAt == null ||
        DateTime.now().difference(s.checkedAt!) > recheckAfter;
    // Also include servers that already passed national tests (natGood) and
    // any still in the healthy list, even if not marked stale — under full
    // national cut we must try everything we already know works.
    final l = good
        .where((s) =>
            !s.ovpn &&
            !identical(s, current) &&
            !_bad(s) &&
            _protoOk(s) &&
            (forceSaved || stale(s)))
        .toList()
      ..sort(bySpeedThenPing);
    if (l.isEmpty) return;
    // Rank national winners / Iran-oriented sources first
    l.sort((a, b) {
      final r = _natRank(b) - _natRank(a); // NATIONALPATCH
      return r != 0 ? r : bySpeedThenPing(a, b);
    });
    final run = l.take(forceSaved ? 80 : 40).toList();
    final need = max(fastPickN, forceSaved ? 6 : 10);
    final fsw = Stopwatch()..start();
    var found = 0, i = 0;
    final dead = <Server>[];
    await pool<Server>(run, max(fastWorkers, forceSaved ? 20 : 8), (s) async {
      if (abort ||
          found >= need ||
          (found >= 1 && fsw.elapsedMilliseconds > (forceSaved ? 15000 : fastPickMs))) {
        return;
      }
      if (ipMode && s.ipLink == null && !s.ipTried) {
        s.ipTried = true;
        s.ipLink = await ipLinkFor(s);
      }
      _set('تست سرورهای ذخیره‌شده (نت ملی) ${++i}/${run.length}...');
      final d = await _delayOf(s, t: forceSaved
          ? Duration(seconds: max(_fgTimeout.inSeconds, 12))
          : _fgTimeout);
      s.checkedAt = DateTime.now();
      if (d == null) {
        dead.add(s);
      } else {
        s.ping = d;
        s.miss = 0;
        s.badAt = null;
        found++;
        if (forceSaved) await _natAdd(s);
      }
    });
    if (found > 0) {
      for (final s in dead) {
        if (++s.miss >= (forceSaved ? 3 : 2)) {
          good.remove(s);
          failed[s.key] = DateTime.now();
        } else {
          s.checkedAt = null;
        }
      }
    } else {
      // nothing passed: keep them — the real tunnel step may still succeed
      // with a different variant (fragment / Iranian DNS / clean IP).
      for (final s in dead) {
        s.checkedAt = null;
      }
    }
    if (mounted) setState(() {});
  }

  // Connect to the best healthy server. First the servers saved from the
  // last session are checked (best saved speed first): the top few are
  // speed-tested for real and the FASTEST one is connected. When none is
  // ready, a search runs and the first healthy server is enough; the rest of
  // the list is tested later while connected (standby search).
  Future<void> _natEscalate(int round) async {
    try {
      await _natDetect(); // what does the network look like now?
      if (!nationalMode && !indestructibleMode) return;
      natAll = true; // every source, skip none
      autoCycle = true;
      // NATULTRA: 2 = every base variant, 3 = + every test address and ~120 generated
      // variants, 4 = ~600 generated variants per pass (the cursor continues next round)
      natLevel = round >= 8 ? 4 : (round >= 4 ? 3 : 2);
      tcpTimeout = Duration(seconds: round >= 8 ? 10 : (round >= 4 ? 8 : 6));
      delayTimeout = Duration(seconds: max(delayTimeout.inSeconds, round >= 8 ? 18 : 14));
      natWorkers = max(natWorkers, round >= 4 ? 8 : 6);
      // grow the variant matrix so later rounds cover more combinations
      try {
        natGrow(round >= 8 ? 400 : (round >= 4 ? 200 : 80));
      } catch (_) {}
      _dohFail = 0;
      // CRITICAL for نت ملی: do NOT destroy existing configs.
      // When international is cut, GitHub raw lists are mostly unreachable.
      // Clearing pending / forcing a full re-fetch left the app with an empty
      // queue and no way to connect with the configs it already had.
      // Soft refresh only: try mirrors in background, keep what we already know.
      natRefetch = fetchedAll.isEmpty; // only force re-download if we have nothing
      if (fetchedAll.isEmpty) {
        listTime = null;
        lastFetchTry = DateTime(2000);
      }
      // Only drop very recent hard-fails so previously-good servers get another
      // chance with the higher variant matrix (fragment / Iranian DNS / clean IP).
      final cutoff = DateTime.now().subtract(const Duration(minutes: 8));
      failed.removeWhere((_, t) => t.isBefore(cutoff));
      // Rebuild pending from existing knowledge instead of clearing it.
      // _resInject brings back folder winners; _checkSaved will re-test good[].
      if (pending.isEmpty && fetchedAll.isNotEmpty) {
        // will be filled by the next _loadPending / _search
      }
      _resInject();
      _set(nationalMode
          ? 'نت ملی: جستجوی گسترده با کانفیگ‌های موجود + منابع (مرحله ${round ~/ 2} • سطح $natLevel)...'
          : 'حالت شکست‌ناپذیر: جستجوی گسترده (مرحله ${round ~/ 2} • سطح $natLevel)...');
    } catch (e) {
      logError(e);
    }
  }

  // ACQUIREFLAG: true while the server search of _acquire is running, so the
  // inspector does not call a normal long search a "stuck switch flag"
  bool _acquiring = false;

  Future<bool> _acquire({bool strictRow = false, bool speed = false}) async {
    _acquiring = true;
    try {
      return await _acquireInner(strictRow: strictRow, speed: speed);
    } finally {
      _acquiring = false;
    }
  }

  Future<bool> _acquireInner(
      {bool strictRow = false, bool speed = false}) async {
    if (!strictRow && connRow == null && !_ovMode) {
      await _checkSaved();
    }
    // Prefer NEW servers: if pending has untested configs, search them first
    // instead of reconnecting only to old healthy/folder list.
    if (!strictRow && !nationalMode && !indestructibleMode && pending.isNotEmpty) {
      // drop folder-injected entries from the "ready" list so _pickList is empty
      // until a fresh test fills good again this session
      final folderKeys = _resMap.keys.toSet();
      if (folderKeys.isNotEmpty) {
        good.removeWhere((s) => folderKeys.contains(s.key) && s.checkedAt == null);
      }
    }
    var speedDone = !speed;
    var emptyRounds = 0; // EMPTYROWFIX: rounds in a row with nothing to try
    // INDESTRUCTIBLE: national / forced modes never exit the outer loop
    final neverStop = nationalMode || indestructibleMode;
    // BEST-EFFORT: normal connect with Ultra uses the same matrix ladder as
    // national search (levels 2→4, operator DNA) but stops after enough rounds
    // so data usage stays bounded.
    final bestEffort = ultraMode && !neverStop;
    for (var round = 0; !abort; round++) {
      // NATESCALATE: every 2nd failed round the search gets wider (all sources,
      // fresh lists, longer waits) and the network state is checked again
      if (round > 0 && round % 2 == 0) await _natEscalate(round);
      // force endless list cycling when in crusade mode
      if (neverStop) {
        autoCycle = true;
        if (natLevel < 2) natLevel = 2;
        if (round >= 4 && natLevel < 3) natLevel = 3;
        if (round >= 8 && natLevel < 4) natLevel = 4;
      } else if (bestEffort) {
        // round 0 stays at current level (usually 1) → more servers, faster
        if (round >= 1 && natLevel < 2) natLevel = 2;
        if (round >= 3 && natLevel < 3) natLevel = 3;
        if (round >= 5 && natLevel < 4) natLevel = 4;
        if (round >= 10) break;
      }
      // RETRYPATCH: quick test is repeated until a healthy server exists
      final row = connRow;
      final searchRow = (strictRow || round == 0) ? row : null;
      List<Server> pickRow() {
        final l = _pickList();
        if (strictRow && row != null) {
          return l.where((s) => inRowGid(s, row)).toList();
        }
        return l;
      }

      var list = pickRow();
      if (list.isEmpty) {
        await _search(2, row: searchRow, keepUp: true);
        final up = upServer;
        if (up != null) {
          _onConnected(up);
          return true;
        }
        list = pickRow();
        if (list.isEmpty) {
          if (abort) break;
          // RETRYPATCH: nothing left to test -> forget the failures and go again
          if (pending.isEmpty) failed.clear();
          // EMPTYROWFIX: a fixed row (e.g. the Gemini row) can have no server
          // at all while the other healthy servers do not belong to it. The
          // search then ended after 0 s again and again for ever. After a few
          // empty rounds we stop and tell the user; the watchdog / the user
          // can try again. INDESTRUCTIBLE overrides this for national crusade.
          emptyRounds++;
          if (strictRow && row != null && emptyRounds >= 6 && !neverStop) {
            break;
          }
          if (neverStop) {
            _set('حالت شکست‌ناپذیر: دور ${round + 1} • سطح $natLevel • '
                'جستجوی دوباره با همه منابع...');
            failed.clear();
            pending.clear();
            natRefetch = true;
            listTime = null;
            lastFetchTry = DateTime(2000);
            await _loadPending(bg: false, exhausted: true);
            _resInject();
          } else {
            _set('سرور سالم پیدا نشد؛ تست سریع دوباره...');
          }
          await Future.delayed(
              Duration(seconds: badPingRounds == 0 ? min(5, 1 + round) : 1));
          continue;
        }
      }
      if (!speedDone && list.length > 1 && !_ovMode && autoSpeed) {
        speedDone = true;
        await _speedTest(speedTopN, from: list);
        list = pickRow();
        if (list.isEmpty) continue;
      }
      emptyRounds = 0;
      // Always verify tunnel ping so apps (Telegram, …) really work.
      // trust:false = one quick ping through the tunnel before accepting.
      if (await _connectLoop(list, trust: false)) return true;
    }
    return false;
  }

  // true = battery optimization is already off for this app, or the user just
  // allowed it in the system dialog. (If the check itself fails on some
  // phone, the app is not locked out.)
  Future<bool> _ensureBattery() async {
    try {
      if (!Platform.isAndroid) return true;
      final st = Permission.ignoreBatteryOptimizations;
      if (await st.isGranted) return true;
      _set('لطفاً در پنجره‌ی باز شده روی «اجازه» بزن...');
      final r = await st.request();
      return r.isGranted;
    } catch (e) {
      logError(e);
      return true;
    }
  }

  Future<void> connect([Server? only, String? gid]) =>
      _doConnect(only: only, row: gid);

  // tap a row: connect to its best server, replacements prefer that row
  Future<void> connectRow(String gid) => _doConnect(row: gid);

  Future<void> _doConnect({Server? only, String? row}) async {
    // AD FIRST: the ad page opens right when the user taps connect
    // خلبان فقط با دکمه «خلبان» روشن می‌شود — اتصال عادی مستقل است
    unawaited(_prepNow()); // network detection runs while the ad is shown
    if (!await _ensureSession()) {
      _set('برای اتصال باید تبلیغ را کامل ببینید');
      return;
    }
    // Ask VPN permission once while Activity is alive (right after ad),
    // so later _start calls do not hit NO_ACTIVITY during the server loop.
    if (!proxyMode && inForeground) {
      try {
        final ok = await v2ray.requestPermission();
        if (ok) vpnPermOk = true;
        if (!ok) {
          _set('مجوز VPN داده نشد');
          errorLog.value = 'مجوز VPN را تأیید کنید و دوباره «اتصال» را بزنید';
          return;
        }
      } on PlatformException catch (e) {
        if (_isNoActivity(e)) {
          _set('Activity آماده نیست؛ یک لحظه صبر کنید و دوباره اتصال را بزنید');
          errorLog.value = 'مجوز VPN: Activity آماده نیست — دوباره تلاش کنید';
          return;
        }
        rethrow;
      }
    }
    await _haltAll(); // tapping while a search runs interrupts it
    await _runBusy(() async {
      if (natForce || _resNext) _resInject(); // NATRESPATCH
      _resNext = false;
      abort = false;
      await _prepNow();
      _prepFut = null;
      natLevel = natForce ? 2 : 0;
      natAll = natForce; // NATBTNPATCH: full search of ALL sources
      natForce = false;
      // Force PLAIN connect: no matrix, no ultra, no folder race
      if (!nationalMode && !indestructibleMode) {
        ultraMode = false;
        natLevel = 0;
        _resBusy = false;
        _resFull = false;
        fragEnabled = false;
        muxEnabled = true;
        muxConc = max(muxConc, 32); // concurrency بالا = سرعت بیشتر
        // اتصال سریع
        delayTimeout = Duration(seconds: min(max(delayTimeout.inSeconds, 5), 8));
        firstBatchSize = max(firstBatchSize, 40);
        batchSize = max(batchSize, 80);
        fastPickN = 2;
        fastPickMs = 8000;
        turboSpeed = true;
        autoSpeed = true;
        speedTopN = max(speedTopN, 3);
      }
      if (nationalMode || indestructibleMode) {
        autoCycle = true; // endless list cycling
        if (natLevel < 2) natLevel = 2;
        natWorkers = max(natWorkers, 8); // more parallel under national cut
        delayTimeout = Duration(
            seconds: max(delayTimeout.inSeconds, 16));
        tcpTimeout = Duration(
            milliseconds: max(tcpTimeout.inMilliseconds, 5500));
        // Prefer Iranian DNS + matrix from the first attempt
        try {
          natGrow(120);
        } catch (_) {}
      } else if (ultraMode) {
        // NORMAL: start light (level 1) so many servers get a quick ping first;
        // bestEffort in _acquire escalates 2→4 only if needed. No folder inject.
        if (natLevel < 1) natLevel = 1;
        natWorkers = max(natWorkers, 6);
        delayTimeout = Duration(
            seconds: max(delayTimeout.inSeconds, 12));
        tcpTimeout = Duration(
            milliseconds: max(tcpTimeout.inMilliseconds, 4000));
      }
      // NORMAL: Fragment always off (kills post-connect speed).
      // National mode may still use Fragment inside the variant matrix.
      if (!nationalMode) fragEnabled = false;
      // all throughput levers (Mux, no Fragment, speed-test top servers, ...)
      _applyTurboLevers();
      // Under national cut: always inject previously-successful folder servers
      // so we can connect with existing configs even when GitHub is unreachable.
      if (nationalMode || indestructibleMode) {
        _resInject();
        await _checkSaved(); // re-test known-good before searching new lists
      }
      // Fire-and-forget: keeps searching in background while connected/hunting
      if (nationalMode) unawaited(_natKeep());
      if (nationalMode) warm = null; // do not wait on blocked list downloads
      // the list download started at app launch is still running: wait for it
      // (it is nearly done, and the search then starts with a full queue)
      final w = warm;
      if (w != null) {
        _set('آماده‌سازی لیست سرورها...');
        try {
          await w.timeout(Duration(seconds: good.isNotEmpty ? 2 : 8));
        } catch (_swE) { _swl('_doConnect#1', _swE);}
      }
      // battery optimization must be OFF for this app, otherwise Android may
      // stop the background search / the VPN service. The system shows the
      // "allow always running in background" dialog; without "allow" the app
      // does not connect.
      if (!await _ensureBattery()) {
        _set('برای اتصال باید بهینه‌سازی باتری خاموش شود: دوباره «اتصال» را بزن و روی «اجازه» بزن');
        return;
      }
      await runPreflight();
      startNetWatch();
      switching = true;
      try {
        bgDisabled = false;
        tunFailRun = 0;
        bgTested = 0;
        bgOk = 0;
        if (connected) {
          await _stopV2();
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) setState(() => connected = false);
        }
        // tapping an OpenVPN server directly: replacements stay OpenVPN
        connRow = (row == null && only != null && only.ovpn) ? 'r:ovpn' : row;
        var ok = only != null
            ? await _connectLoop([only], trust: good.contains(only))
            : (row == 'f:mine')
                // "my configs" row: they are connected directly, no search
                ? await _connectLoop(_mineList())
                : await _acquire(strictRow: row != null, speed: autoSpeed);
        // AUTONET: the tapped mode found nothing -> the app picks the best
        // mode itself (all kinds of servers, the one that works best first)
        if (!ok &&
            !abort &&
            autoNetOn &&
            only == null &&
            row != null &&
            !row.startsWith('f:') &&
            row != 'r:ai' &&
            row != 'r:ovpn') {
          _set('این حالت جواب نداد؛ بهترین حالت را خودم انتخاب می‌کنم...');
          connRow = null;
          ok = await _acquire(strictRow: false, speed: autoSpeed);
        }
        if (ok) {
          _startWatch();
          _saveCache();
          _adAfterConnect();
        } else {
          // the personal server did not connect: tell the user why
          if (only?.personal == true && !abort) _checkPersonal(force: true);
          _set(abort
              ? 'لغو شد'
              : (only == null && row == 'r:ai')
                  ? 'هیچ سروری که Gemini را باز کند پیدا نشد؛ بعداً دوباره امتحان کن یا حالت دیگری را بزن'
                  : (only == null && row != null)
                  ? 'در این ردیف سرور سالمی پیدا نشد'
                  : 'هیچ سروری وصل نشد، دوباره تلاش کنید');
        }
      } finally {
        _unlockLater();
      }
    });
  }

  Future<void> disconnect() async {
    aiSession = false;
    aiLoop?.cancel();
    stopNetWatch();
    stopGrokPilot();
    stopLocalPilot();
    wantVpn = false;
    pendingFailover = false;
    switching = true;
    watch?.cancel();
    dropTimer?.cancel();
    try {
      await _stopV2();
      // ORPHANFIX: a stop sent right after the tunnel came up can be lost;
      // the core then stays CONNECTED with the app showing "disconnected"
      for (var i = 0; i < 3; i++) {
        await Future.delayed(const Duration(milliseconds: 1000));
        if (lastState != 'CONNECTED') break;
        try {
          await v2ray.stopV2Ray();
        } catch (_swE) { _swl('disconnect#orphan', _swE);}
      }
    } catch (e) {
      logError(e);
    }
    current = null;
    upServer = null;
    tunWarn = false;
    if (mounted) setState(() => connected = false);
    _saveCache(); // the healthy servers are kept for the next start
    _set('قطع شد');
    _chShown = false;
    _unlockLater();
  }

  // switch to the next best standby server (search only if none is ready).
  // Used immediately when the server is dead / broken / errors out: the
  // fastest known standby (by real speed) takes over, no timer is waited for.
  // STABLEPINGPATCH: always the lowest ping, without frequent cuts
  static const double _spRatio = 0.50; // باید حداقل ۵۰٪ بهتر باشد
  static const int _spMinGain = 80; // حداقل ۸۰ms اختلاف
  static const Duration _spHold = Duration(minutes: 10); // فاصله بیشتر
  static const Duration _spEvery = Duration(seconds: 75);
  static const Duration _spRefreshEvery = Duration(minutes: 5);
  static const Duration _spSkipFor = Duration(minutes: 20);
  static const int _spMaxPerHour = 2; // حداکثر ۲ بار در ساعت
  final List<int> _spWin = []; // live pings of the connected server
  Server? _spFor; // the server the window belongs to
  bool _spBusy = false;
  DateTime _spAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _spRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);
  final List<DateTime> _spSwaps = [];
  final Map<String, DateTime> _spSkip = {};

  int _spMedian(List<int> l) {
    final c = List<int>.from(l)..sort();
    return c[c.length ~/ 2];
  }

  // everything must still be calm and the same server must still be connected
  bool _spOk(Server cur) =>
      mounted &&
      connected &&
      wantVpn &&
      !busy &&
      !switching &&
      !searching &&
      !upBusy &&
      !appGone &&
      identical(current, cur);

  // standby servers that could replace the connected one (best ping first)
  List<Server> _spPool() {
    final row = connRow;
    final l = _usable()
        .where((c) =>
            !identical(c, current) &&
            !c.ovpn &&
            !c.personal &&
            c.miss == 0 &&
            c.ping != null &&
            !_spSkip.containsKey(c.key) &&
            _spSpeedOk(c) &&
            (row == null || inRowGid(c, row)))
        .toList()
      ..sort(byPing);
    return l;
  }

  // SPEEDKEEP: a lower ping must not bring a slower server. A candidate whose
  // real speed is known and clearly below the connected server's speed (or
  // zero = no data) is not used for a ping swap.
  bool _spSpeedOk(Server c) {
    final cs = c.speed;
    if (cs == null) return true; // unknown: allowed, checked after the swap
    if (cs <= 0) return false;
    final cur = current?.speed;
    if (cur == null || cur < 0.3) return true;
    return cs >= cur * 0.7;
  }

  // SPEEDKEEP: after a ping swap the real speed is measured (by
  // _measureCurrent). If it is clearly lower than the old server's speed,
  // the old server comes back and the new one is not tried again for a while.
  Future<void> _spCheckSpeed(Server t, Server old) async {
    try {
      final oldSp = old.speed ?? 0;
      if (oldSp < 0.3) return;
      final t0 = DateTime.now();
      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (!connected || !identical(t, current) || abort) return;
        final at = t.speedAt;
        if (at != null && at.isAfter(t0)) break;
      }
      final at = t.speedAt;
      if (at == null || !at.isAfter(t0)) return;
      final sp = t.speed ?? 0;
      if (sp <= 0) return; // no data: _measureCurrent handles it
      if (sp >= oldSp * 0.6) return;
      dbg('سرعت سرور جدید ${sp.toStringAsFixed(2)} MB/s کمتر از سرور قبلی '
          '(${oldSp.toStringAsFixed(2)} MB/s) بود؛ برگشت به سرور قبلی');
      _spSkip[t.key] = DateTime.now().add(const Duration(minutes: 20));
      await _stopCore();
      connected = false;
      if (mounted) setState(() {});
      if (await _connectLoop([old])) _saveCache();
    } catch (e) {
      logError(e);
    }
  }

  // called by the watchdog every tick with the live ping [p] (ms)
  void _stableTick(int p) {
    try {
      final cur = current;
      if (cur == null || !connected) return;
      if (!identical(cur, _spFor)) {
        _spFor = cur;
        _spWin.clear();
      }
      _spWin.add(p);
      if (_spWin.length > 12) _spWin.removeAt(0);
      if (cur.ovpn || _spBusy || !_spOk(cur)) return;
      if (_spWin.length < 8) return; // ~40 s of live pings first
      final now = DateTime.now();
      if (now.difference(lastSwitch) < _spHold) return;
      if (now.difference(_spAt) < _spEvery) return;
      _spAt = now;
      _stableCheck();
    } catch (e) {
      logError(e);
    }
  }

  Future<void> _stableCheck() async {
    if (_spBusy) return;
    _spBusy = true;
    try {
      final cur = current;
      if (cur == null) return;
      final curMed = _spMedian(_spWin);
      var now = DateTime.now();
      _spSwaps.removeWhere((x) => now.difference(x) > const Duration(hours: 1));
      _spSkip.removeWhere((k, x) => now.difference(x) > _spSkipFor);

      // keep the numbers of the best standbys fresh (the VPN is not touched)
      if (now.difference(_spRefreshAt) >= _spRefreshEvery) {
        _spRefreshAt = now;
        for (final c in _spPool().take(4).toList()) {
          if (!_spOk(cur)) return;
          final d = await _delayOf(c, t: _bgTimeout);
          c.checkedAt = DateTime.now();
          if (d == null) {
            if (++c.miss >= missLimit) {
              good.remove(c);
              failed[c.key] = DateTime.now();
            }
          } else {
            c.miss = 0;
            c.ping = d;
          }
        }
      }

      if (_spSwaps.length >= _spMaxPerHour) return;
      final cands = _spPool()
          .where((c) =>
              c.ping! < curMed * _spRatio && curMed - c.ping! >= _spMinGain)
          .toList();
      if (cands.isEmpty) return;
      final t = cands.first;

      // confirm: 3 fresh tests in a row, all of them must beat the current
      final r = <int>[];
      for (var i = 0; i < 3; i++) {
        if (!_spOk(cur)) return;
        final d = await _delayOf(t, t: _bgTimeout);
        if (d == null) break;
        r.add(d);
        if (i < 2) await Future.delayed(const Duration(seconds: 2));
      }
      t.checkedAt = DateTime.now();
      if (r.length < 3) {
        _spSkip[t.key] = DateTime.now();
        return;
      }
      final newMed = _spMedian(r);
      final worst = r.reduce(max);
      t.ping = newMed;
      if (!(newMed < curMed * _spRatio &&
          curMed - newMed >= _spMinGain &&
          worst < curMed)) {
        _spSkip[t.key] = DateTime.now();
        return;
      }

      // last checks, then switch
      if (!_spOk(cur)) return;
      now = DateTime.now();
      if (now.difference(lastSwitch) < _spHold) return;
      if (_spSwaps.length >= _spMaxPerHour) return;
      _spSwaps.add(now);
      await _stableSwap(t, cur, curMed, newMed);
    } catch (e) {
      logError(e);
    } finally {
      _spBusy = false;
    }
  }

  // switch to the lower-ping server; if it does not come up, go back to the
  // old one (the old one is NOT marked bad: it was working)
  Future<void> _stableSwap(Server t, Server old, int curMed, int newMed) async {
    if (busy) return;
    abort = false;
    await _runBusy(() async {
      switching = true;
      try {
        lastWhy = 'پینگ کمتر (${newMed}ms به‌جای ${curMed}ms)';
        _set('تعویض به سرور با پینگ کمتر (${newMed}ms)...');
        await _stopCore();
        connected = false;
        if (mounted) setState(() {});
        if (await _connectLoop([t])) {
          _saveCache();
          await _spCheckSpeed(t, old); // SPEEDKEEP
        } else if (!abort) {
          _spSkip[t.key] = DateTime.now();
          if (await _connectLoop([old])) {
            _saveCache();
          } else if (!abort && !await _acquire()) {
            if (!inForeground) pendingFailover = true;
            _set('سرور جایگزین پیدا نشد • تلاش دوباره...');
          }
        }
      } finally {
        lastSwitch = DateTime.now();
        _unlockLater();
      }
    });
  }

  Future<void> _failover() async {
    if (busy) return;
    abort = false;
    await _runBusy(() async {
      switching = true;
      try {
        final bad = current;
        if (bad != null) {
          bad.badAt = DateTime.now();
          // a broken server is deleted after two failures in a row
          // (pinned / manual configs are never deleted)
          if (++bad.miss >= 2 && !favs.containsKey(bad.key)) good.remove(bad);
        }
        await _stopCore(); // جدید: fully down before the replacement starts
        if (bad?.personal == true) {
          connRow = null; // the replacement comes from the whole list
          _checkPersonal(); // tell the user what is wrong with it
        }
        connected = false;
        if (mounted) setState(() {});
        _set('تعویض سرور (${lastWhy.isEmpty ? 'نامشخص' : lastWhy})...');
        if (await _acquire(strictRow: connRow == 'r:ai')) {
          _saveCache();
        } else if (abort) {
          wantVpn = false;
          watch?.cancel();
          current = null;
          _set('لغو شد');
        } else {
          // keep wantVpn: the watchdog tries again in a few seconds
          if (!inForeground) pendingFailover = true;
          _set('سرور جایگزین پیدا نشد • تلاش دوباره...');
        }
      } finally {
        lastSwitch = DateTime.now();
        _unlockLater();
      }
    });
  }

  // FASTPATCH: standby server that is clearly better than the connected
  // one. Same kind of ping on both sides (core delay test), at least 20%
  // and 30 ms lower, tested in the last 4 minutes, not slower in real
  // speed when both speeds are known.
  Server? _betterStandby() {
    final cur = current;
    final base = connBaseDelay;
    if (cur == null || cur.ovpn || cur.personal || base == null) {
      return null;
    }
    final now = DateTime.now();
    final limit = min((base * betterGain).floor(), base - betterMinGapMs);
    final cs = cur.speed ?? 0;
    Server? best;
    for (final c in _usable()) {
      if (identical(c, cur) || c.ovpn || c.personal || c.miss != 0) continue;
      final p = c.ping;
      final t = c.checkedAt;
      if (p == null || t == null || p > limit) continue;
      if (now.difference(t) > const Duration(minutes: 4)) continue;
      // جدید: both REAL speeds must be known and the standby clearly faster
      // (a lower delay-ping alone is not a reason to cut a working connection)
      if (cs <= 0 || (c.speed ?? 0) <= 0 || c.speed! < cs * 1.25) continue;
      if (best == null || p < best.ping!) best = c;
    }
    return best;
  }

  // FASTPATCH-AI: analyse, then apply the suggested settings by itself
  Future<void> _aiRunAuto() async {
    if (!mounted || !connected || aiLoading.value || geminiKey.isEmpty) {
      return;
    }
    if (DateTime.now().difference(_lastAutoAi) <
        const Duration(seconds: 90)) {
      return;
    }
    _lastAutoAi = DateTime.now();
    await aiAnalyze(auto: true);
    if (!mounted) return;
    // the assistant may raise the parallel-test counts but never lower them
    final fw = fastWorkers, bw = bgWorkers;
    applyAiSuggest();
    var fix = false;
    if (fastWorkers < fw) {
      fastWorkers = fw;
      fix = true;
    }
    if (bgWorkers < bw) {
      bgWorkers = bw;
      fix = true;
    }
    if (fix) _saveSettings();
  }

  // 6 s after a connection, then every aiEveryMin minutes while connected
  Future<void> _aiLoop(int gen) async {
    await Future.delayed(const Duration(seconds: 6));
    while (mounted && connected && gen == aiGen) {
      await _aiRunAuto();
      await Future.delayed(Duration(minutes: aiEveryMin));
    }
  }

  // the connected server still works but its ping is terrible: the standby
  // server with the lowest ping (and a ping better than [below]) or null
  Server? _bestPingStandby(int below) {
    final l = _usable()
        .where((s) =>
            !identical(s, current) &&
            s.ovpn == _ovMode &&
            !s.personal &&
            s.miss == 0 &&
            s.ping != null &&
            s.ping! < below)
        .toList()
      ..sort(byPing);
    final now = DateTime.now();
    final fresh = l
        .where((s) =>
            s.checkedAt != null &&
            now.difference(s.checkedAt!) < const Duration(minutes: 10))
        .toList();
    if (fresh.isNotEmpty) return fresh.first;
    return l.isEmpty ? null : l.first;
  }

  // fast switch to a chosen server (bad ping of the old one). If it does not
  // come up, the normal replacement search takes over.
  Future<void> _swapTo(Server t) async {
    if (busy) return;
    abort = false;
    await _runBusy(() async {
      switching = true;
      try {
        final old = current;
        // the slow one rests for a while, it is not deleted
        if (old != null && !old.personal) old.badAt = DateTime.now();
        _set('تعویض سرور (${lastWhy.isEmpty ? 'پینگ بد' : lastWhy})...');
        await _stopCore(); // جدید: fully down before the next start
        connected = false;
        if (mounted) setState(() {});
        if (await _connectLoop([t])) {
          _saveCache();
        } else if (!abort && !await _acquire(strictRow: connRow == 'r:ai')) {
          if (!inForeground) pendingFailover = true;
          _set('سرور جایگزین پیدا نشد • تلاش دوباره...');
        }
      } finally {
        lastSwitch = DateTime.now();
        _unlockLater();
      }
    });
  }

  // ---------- personal Cloudflare server ----------
  Future<void> connectPersonal() async {
    final s = personal;
    if (s == null) {
      _guideSheet();
      return;
    }
    final e = personalExpiry;
    if (e != null && e.isBefore(DateTime.now())) {
      _checkPersonal(force: true);
      return;
    }
    if (connected && identical(s, current)) return;
    await connect(s, 'p:personal');
  }

  void _deletePersonal() {
    personal = null;
    personalExpiry = null;
    personalMsg = '';
    errorLog.value = '';
    _savePersonal();
    if (mounted) setState(() {});
    _set('سرور شخصی حذف شد');
  }

  // finds out why the personal server does not work
  Future<String> _diagnosePersonal() async {
    final s = personal;
    if (s == null) return 'سرور شخصی هنوز ساخته نشده.';
    final e = personalExpiry;
    if (e != null && e.isBefore(DateTime.now())) {
      return '⏰ زمان تمام شده: مدت اعتبار سرور شخصی تمام شد. تمدید کن یا سرور جدید بساز.';
    }
    if (s.ovpn) {
      return '🔒 سرور OpenVPN شخصی وصل نشد: حساب‌های رایگان منقضی می‌شوند یا '
          'کانفیگ نام کاربری/رمز جدا می‌خواهد. کانفیگ تازه بگیر و دوباره ثبت کن.';
    }
    String? ip;
    try {
      final r = await InternetAddress.lookup(s.host)
          .timeout(const Duration(seconds: 5));
      if (r.isNotEmpty) ip = r.first.address;
    } catch (_swE) { _swl('_diagnosePersonal#1', _swE);}
    ip ??= await dohResolve(s.host);
    if (ip == null) {
      return '🗑 خراب شده: آدرس ${s.host} پیدا نشد. ورکر حذف شده، '
          'اسمش عوض شده یا آدرس اشتباه است. ورکر جدید بساز.';
    }
    final c = HttpClient()
      ..findProxy = ((_) => 'DIRECT')
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await c
          .getUrl(Uri.parse('https://${s.host}/'))
          .timeout(const Duration(seconds: 8));
      final res = await req.close().timeout(const Duration(seconds: 8));
      var body = '';
      try {
        body = await res
            .transform(const Utf8Decoder(allowMalformed: true))
            .join()
            .timeout(const Duration(seconds: 5));
      } catch (_swE) { _swl('_diagnosePersonal#2', _swE);}
      if (body.length > 4000) body = body.substring(0, 4000);
      final b = body.toLowerCase();
      final code = res.statusCode;
      bool has(String n) =>
          RegExp('(error code:?|error)\\s*$n').hasMatch(b);
      if (code == 429 ||
          has('1027') ||
          has('1015') ||
          b.contains('daily request limit')) {
        return '📊 حجم تمام شده: سقف درخواست روزانه‌ی پلن رایگان Cloudflare '
            '(۱۰۰ هزار) پر شده. ساعت ۰۳:۳۰ بامداد ایران دوباره پر می‌شود، '
            'یا پلن پولی بگیر.';
      }
      if (b.contains('nothing here yet') || has('1016') || has('1001')) {
        return '🗑 خراب شده: ورکر حذف شده یا هنوز Deploy نشده. دوباره بسازش.';
      }
      if (has('1101') || has('1102') || has('1042') || code >= 500) {
        return '🛠 خراب شده: کد ورکر خطا می‌دهد (کد $code). اسکریپت را '
            'دوباره Paste و Deploy کن.';
      }
      if (code == 403 && (has('1010') || has('1020'))) {
        return '🚫 مسدود شده: Cloudflare دسترسی را بسته است. ورکر جدید با '
            'اسم دیگر بساز.';
      }
      return '✅ ورکر سالم است (کد $code). اگر وصل نمی‌شود، UUID داخل '
          'برنامه را با UUID داخل ورکر یکی کن.';
    } catch (_swE) { _swl('_diagnosePersonal#3', _swE);
      return '🌐 اتصال به ورکر برقرار نشد: اینترنت قطع است، آدرس فیلتر شده '
          'یا ورکر خراب است.';
    } finally {
      c.close(force: true);
    }
  }

  Future<String> _checkPersonal({bool force = false}) async {
    final msg = await _diagnosePersonal();
    personalMsg = msg;
    if (mounted) setState(() {});
    final okMsg = msg.startsWith('✅');
    final now = DateTime.now();
    if (!okMsg) errorLog.value = msg;
    if (mounted &&
        (force ||
            (!okMsg &&
                now.difference(lastPAlert) > const Duration(minutes: 1)))) {
      lastPAlert = now;
      showDialog(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('🏠 سرور شخصی'),
            content: SelectableText(msg),
            actions: [
              if (!okMsg)
                TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deletePersonal();
                    },
                    child: const Text('حذف سرور',
                        style: TextStyle(color: Color(0xFFFF8A80)))),
              if (!okMsg)
                TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _guideSheet();
                    },
                    child: const Text('راهنمای ساخت')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('باشه')),
            ],
          ),
        ),
      );
    }
    return msg;
  }

  // page with the free providers (time / volume), each with its own steps
  void _guideSheet() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderListPage(
          onRegister: (d) =>
              Future.delayed(const Duration(milliseconds: 350), () {
            if (mounted) _personalSheet(defaultDays: d == 0 ? null : d);
          }),
        ),
      ),
    );
  }

  void _personalSheet({int? defaultDays}) {
    final host = TextEditingController(text: personal?.host ?? '');
    final uuid = TextEditingController(
        text: (personal == null || personal!.ovpn)
            ? ''
            : (Uri.tryParse(personal!.link)?.userInfo ?? ''));
    final days = TextEditingController(text: defaultDays?.toString() ?? '');
    final full = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _guideSheet();
                    },
                    child: const Text('📖 راهنمای ساخت سرور')),
                TextField(
                    controller: host,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                        labelText: 'آدرس ورکر (my-vpn.name.workers.dev)')),
                TextField(
                    controller: uuid,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'UUID')),
                TextField(
                    controller: days,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'مدت اعتبار به روز (اختیاری)')),
                TextField(
                    controller: full,
                    maxLines: 4,
                    minLines: 1,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                        labelText:
                            'یا لینک کامل (vless/vmess/...) یا متن کامل OpenVPN')),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        var link = full.text.trim();
                        Server? s;
                        if (link.isEmpty) {
                          if (host.text.trim().isEmpty ||
                              uuid.text.trim().isEmpty) {
                            _set('آدرس و UUID را کامل کن');
                            return;
                          }
                          link = buildPersonalLink(host.text, uuid.text);
                          s = Server.parse(link);
                        } else {
                          s = ovpnFromText(link, name: '🏠 OpenVPN شخصی') ??
                              Server.parse(link);
                        }
                        if (s == null) {
                          _set('لینک یا کانفیگ معتبر نیست');
                          return;
                        }
                        s.personal = true;
                        personal = s;
                        final d = int.tryParse(days.text.trim());
                        personalExpiry = d == null
                            ? null
                            : DateTime.now().add(Duration(days: d));
                        personalMsg = '';
                        _savePersonal();
                        Navigator.pop(ctx);
                        setState(() {});
                        _set('سرور شخصی ذخیره شد');
                      },
                      child: const Text('ذخیره'),
                    ),
                  ),
                  if (personal != null) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _checkPersonal(force: true);
                        },
                        child: const Text('بررسی')),
                    const SizedBox(width: 8),
                    OutlinedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _deletePersonal();
                        },
                        child: const Text('حذف')),
                  ],
                ]),
              ]),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      host.dispose();
      uuid.dispose();
      days.dispose();
      full.dispose();
    });
  }

  Widget _personalHeader() => InkWell(
        onTap: connectPersonal,
        child: Container(
          width: double.infinity,
          color: Color(0xFF34373E),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            Expanded(
                child: Text(
                    personal == null
                        ? '🏠 ساخت سرور شخصی (Cloudflare) • بزن تا راهنما باز شود'
                        : '🏠 سرور شخصی'
                            '${personalMsg.isEmpty ? '' : ' • $personalMsg'}',
                    maxLines: 4,
                    style: const TextStyle(fontWeight: FontWeight.bold))),
            IconButton(
                icon: const Icon(Icons.settings, size: 20),
                onPressed: _personalSheet),
            const Icon(Icons.play_circle_outline, size: 20),
          ]),
        ),
      );

  // Continuous real-speed policy:
  //  * every server that passed the ping test is speed-tested (never-tested
  //    ones first, then the oldest results);
  //  * a server faster than the connected one (by [upgradeGain]) takes over
  //    at once and the old one becomes a standby with its saved speed;
  //  * a server slower than the connected one but faster than a standby just
  //    ranks above it (standbys are always ordered by real speed);
  //  * if the connected server dies / errors, the fastest standby takes over
  //    immediately (see _failover).
  List<Server> _upgradeCandidates({int? n, bool force = false}) {
    final cur = current;
    if (cur == null || cur.ovpn) return [];
    final now = DateTime.now();
    final cs = cur.speed ?? 0;
    // a standby whose saved speed beats the connected one: verify it first,
    // however old its result is (the trial re-measures it before switching)
    bool better(Server s) =>
        (s.speed ?? 0) > 0 && (s.speed ?? 0) > cs * upgradeGain;
    final l = _usable().where((s) {
      if (identical(s, cur) || s.ovpn) return false;
      if (force || better(s)) return true;
      return s.speedAt == null || now.difference(s.speedAt!) > speedFresh;
    }).toList()
      ..sort((a, b) {
        final ab = better(a) ? 0 : 1, bb = better(b) ? 0 : 1;
        if (ab != bb) return ab - bb;
        if (ab == 0) return (b.speed ?? 0).compareTo(a.speed ?? 0);
        final an = a.speedAt == null ? 0 : 1, bn = b.speedAt == null ? 0 : 1;
        return an != bn ? an - bn : byPing(a, b);
      });
    return l.take(n ?? speedBatch).toList();
  }

  // ping every healthy server through the core's delay test (the VPN is never
  // touched); servers that no longer answer are deleted. Returns the
  // survivors, lowest ping first. Runs [bgWorkers] tests in parallel.
  Future<List<Server>> _pingRecheck() async {
    final list = _usable()
        .where((s) => !identical(s, current) && !s.ovpn)
        .toList();
    var i = 0;
    await pool<Server>(list, bgWorkers, (s) async {
      if (abort || !connected) return;
      i++;
      _set('تست پینگ سرورهای سالم $i/${list.length}...');
      final d = await _delayOf(s, t: _bgTimeout);
      s.checkedAt = DateTime.now();
      if (d == null) {
        s.badAt = DateTime.now();
        if (++s.miss >= 2) good.remove(s);
      } else {
        s.ping = d;
        s.miss = 0;
      }
      if (mounted) setState(() {});
    });
    final ok = _usable()
        .where((s) => !identical(s, current) && !s.ovpn)
        .toList()
      ..sort(byPing);
    return ok.take(manualSpeedMax).toList();
  }

  // manual = started by the user's button: pings all healthy servers, then speed-tests the survivors, never
  // switches by itself (the old server is reconnected afterwards)
  Future<void> _upgradeRun({bool manual = false}) async {
    if ((!autoUpgrade && !manual) || upBusy || busy || switching || !connected) return;
    if (!wantVpn || appGone) return;
    final now = DateTime.now();
    if (!manual &&
        (now.difference(lastUpgrade) < upgradeEvery ||
            now.difference(lastSwitch) < upgradeEvery)) {
      return;
    }
    final cands =
        manual ? _upgradeCandidates(n: manualSpeedMax, force: true) : _upgradeCandidates();
    final old = current;
    if (cands.isEmpty || old == null) return;
    upBusy = true;
    lastUpgrade = now;
    needTrial = false;
    try {
      await _haltAll(); // interrupt the standby search quickly
      if (!connected || !wantVpn || busy || switching) return;
      await _runBusy(() async {
        switching = true;
        var changed = false;
        try {
          var run = cands;
          if (manual) {
            // step 1: ping every healthy server (no cut), dead ones drop out
            run = await _pingRecheck();
            if (run.isEmpty) {
              _set('هیچ سرور سالم دیگری نمانده');
              return;
            }
            // ping only: the real speed test cuts the VPN, so it is skipped
            _set('تست پینگ تمام شد • ${run.length} سرور سالم • اتصال قطع نشد');
            return;
          }
          if (abort) {
            _set('تست متوقف شد');
            return; // stopped during the ping step: nothing was cut
          }
          var oldSp = old.speed ?? 0;
          final fresh = old.speedAt != null &&
              DateTime.now().difference(old.speedAt!) <
                  const Duration(minutes: 2);
          if (!fresh) {
            _set('اندازه‌گیری سرعت واقعی سرور فعلی...');
            oldSp = await measure(
                    win: const Duration(seconds: 3),
                    total: const Duration(seconds: 10),
                    direct: true) ??
                0;
            old.speed = oldSp;
            old.speedAt = DateTime.now();
          }
          changed = true;
          await _stopCore();
          if (mounted) setState(() => connected = false);

          Server best = old;
          double bestSp = oldSp;
          Server? live; // server whose core is running right now
          for (var i = 0; i < run.length; i++) {
            if (abort) break;
            final c = run[i];
            if (live != null) {
              await _stopCore();
              live = null;
            }
            _set('تست سرعت واقعی ${i + 1}/${run.length} • ${c.name}');
            var sp = 0.0;
            if (await _start(c)) {
              live = c;
              final p = await pingProxy(
                  total: const Duration(seconds: 5), direct: true);
              if (p != null) {
                sp = await measure(
                        win: const Duration(seconds: 2),
                        total: const Duration(seconds: 7),
                        direct: true) ??
                    0;
              }
            }
            c.speed = sp;
            c.speedAt = DateTime.now();
            if (sp == 0) {
              c.badAt = DateTime.now();
              if (++c.miss >= 2) good.remove(c); // no data twice: deleted
            }
            if (!manual && sp > bestSp * upgradeGain) {
              best = c;
              bestSp = sp; // keep its core running, no restart needed
            } else if (live != null) {
              await _stopCore();
              live = null;
            }
            if (mounted) setState(() {});
          }
          if (manual && abort) {
            // Stopped (or the user tapped a server): do not go back to the old
            // server and do not connect by itself. The VPN stays off, the list
            // is sorted by speed and the user taps the server he wants.
            if (live != null) await _stopCore();
            wantVpn = false;
            pendingFailover = false;
            watch?.cancel();
            dropTimer?.cancel();
            current = null;
            tunWarn = false;
            _set('تست متوقف شد • VPN قطع است • روی بالاترین سرور بزن');
            return;
          }
          if (!identical(best, old)) {
            lastWhy = 'سرور سریع‌تر (${bestSp.toStringAsFixed(1)} در برابر '
                '${oldSp.toStringAsFixed(1)} MB/s)';
          }
          if (live != null && identical(live, best)) {
            _onConnected(best); // already running
          } else {
            if (live != null) await _stopCore();
            if (await _start(best)) {
              _onConnected(best);
            } else if (!identical(best, old) && await _start(old)) {
              _onConnected(old);
            } else {
              current = null;
              await _acquire();
            }
          }
          if (manual && mounted) {
            _set('تست سرعت تمام شد • برای تعویض روی بالاترین سرور بزن');
          }
        } finally {
          if (changed) lastSwitch = DateTime.now();
          _unlockLater();
        }
      });
    } finally {
      upBusy = false;
      if (manual) abort = false;
    }
  }

  // rebuild the VPN tunnel on the current server (key icon missing)
  Future<void> _restartTunnel() async {
    final s = current;
    if (s == null || busy || switching) return;
    await _runBusy(() async {
      switching = true;
      try {
        _set('ساخت دوباره تونل VPN...');
        await _stopCore();
        if (mounted) setState(() => connected = false);
        if (await _start(s)) {
          _onConnected(s);
        } else {
          s.badAt = DateTime.now();
          current = null;
          await _acquire();
        }
      } finally {
        lastSwitch = DateTime.now();
        _unlockLater();
      }
    });
  }

  // GEMWATCH: in the Gemini row the connection must KEEP opening Gemini. Every
  // 3 minutes it is checked through the tunnel; two clear "no" answers in a
  // row mark the server and the next Gemini server takes over.
  DateTime _aiChkAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _aiChkBad = 0;
  bool _aiChkBusy = false;
  void _aiKeepCheck() {
    try {
      if (_aiChkBusy || connRow != 'r:ai' || busy || switching) return;
      final cur = current;
      if (cur == null || cur.ovpn || !connected) return;
      final now = DateTime.now();
      if (now.difference(_aiChkAt) < const Duration(minutes: 3)) return;
      if (now.difference(lastSwitch) < const Duration(seconds: 40)) return;
      _aiChkAt = now;
      _aiChkBusy = true;
      geminiOpens(direct: true).then((ok) {
        if (!mounted || !identical(current, cur) || busy || switching) return;
        if (ok) {
          _aiChkBad = 0;
          cur.ai = true;
        } else if (gemDefinite) {
          if (++_aiChkBad >= 2) {
            _aiChkBad = 0;
            cur.ai = false;
            lastWhy = 'Gemini روی این سرور باز نمی‌شود';
            _failover();
          } else {
            _aiChkAt = DateTime.now().subtract(const Duration(minutes: 2));
          }
        }
      }).catchError((_) {}).whenComplete(() => _aiChkBusy = false);
    } catch (e) {
      logError(e);
    }
  }

  // NETCHANGE: Wi-Fi <-> mobile data (or a new IP) while connected. The old
  // tunnel is often dead right after such a change, so the next failed check
  // switches server at once instead of waiting for several failures.
  String _netSig = '';
  bool netDown = false; // the phone has no network interface with an address
  DateTime netUpAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _netDownSince = DateTime.now();
  int _netDownRun = 0;
  Future<void> _netWatch() async {
    try {
      final l = await NetworkInterface.list(
          includeLoopback: false, includeLinkLocal: false);
      var anyUp = false;
      final parts = <String>[];
      for (final i in l) {
        final n = i.name.toLowerCase();
        if (n.startsWith('tun') || n.startsWith('dummy')) continue;
        if (i.addresses.isNotEmpty) anyUp = true;
        final ips = i.addresses
            .where((a) => a.type == InternetAddressType.IPv4)
            .map((a) => a.address)
            .toList();
        if (ips.isEmpty) continue;
        parts.add('${i.name}:${ips.join(',')}');
      }
      parts.sort();
      final sig = parts.join('|');
      if (_netSig.isNotEmpty && sig != _netSig && connected && wantVpn) {
        dbg('تغییر شبکه (وای‌فای/دیتا)؛ بررسی فوری اتصال');
        fails = max(fails, watchFailLimit - 1);
      }
      _netSig = sig;
      // two checks in a row (~10 s) without any real interface = no internet
      if (!anyUp) {
        if (++_netDownRun >= 2 && !netDown) {
          netDown = true;
          _netDownSince = DateTime.now();
          dbg('اینترنت گوشی قطع شد؛ VPN نگه داشته می‌شود');
        }
        // never hold forever: after 30 minutes the normal logic takes over
        if (netDown &&
            DateTime.now().difference(_netDownSince) >
                const Duration(minutes: 30)) {
          netDown = false;
          netUpAt = DateTime.fromMillisecondsSinceEpoch(0);
        }
      } else {
        _netDownRun = 0;
        if (netDown) {
          netDown = false;
          netUpAt = DateTime.now();
          fails = 0;
          badPingRun = 0;
          lowSpeed = 0;
          stallRun = 0;
          noData = 0;
          dbg('اینترنت گوشی برگشت؛ همان اتصال ادامه پیدا می‌کند');
        }
      }
    } catch (_) {}
  }

  void _startWatch() {
    watch?.cancel();
    Future.delayed(const Duration(seconds: 25), _standbyRun);
    watch = Timer.periodic(watchEvery, (_) async {
      // strong check: ask the native activity if it still exists. If it is
      // gone (swiped from recents) every background test is stopped.
      try {
        final alive = await bgChannel.invokeMethod<bool>('alive');
        if (alive == false && !appGone && !(wantVpn || connected)) {
          appGone = true;
          abort = true;
        }
      } catch (_swE) { _swl('_startWatch#1', _swE);}
      if (watchBusy &&
          !busy &&
          !switching &&
          DateTime.now().difference(_wbSince).inSeconds > 90) {
        // SELFHEALPATCH: a stuck check never blocks the watchdog
        watchBusy = false;
        dbg('همگام‌سازی خودکار: بررسی واچ‌داگ بیش از ۹۰s طول کشید؛ آزاد شد');
      }
      unawaited(_netWatch()); // NETCHANGE
      if (watchBusy || !wantVpn || busy || switching) return;
      if (_syncCore()) return; // SELFHEALPATCH
      // خودترمیمی اول اجرا شود؛ اگر وارد عمل شد واچ‌داگ این تیک را رد کند
      // تا دو موتور هم‌زمان تعویض نکنند
      await kingSelfHeal(reason: 'watch');
      if (busy || switching || !wantVpn) return;
      watchBusy = true;
      _wbSince = DateTime.now();
      try {
        if (!connected) {
          // connection lost and the last replacement attempt failed: retry
          if (DateTime.now().difference(lastSwitch) >
              const Duration(seconds: 10)) {
            await _failover();
          }
          return;
        }
        // internet check through the tunnel: the plain-http URL first, then
        // https (a slow server or one blocked URL must not count as dead)
        final p = await pingAny(total: const Duration(seconds: 6), direct: true);
        if (!connected || busy || switching) return;
        if (p != null) {
          fails = 0;
          current?.ping = p; // live ping of the connected server
          _aiKeepCheck(); // GEMWATCH
          _tgKeepCheck(); // TGWATCH
          // Tunnel guard: a "direct" ping also passes when the phone has NO
          // VPN tunnel (no key icon). If tun is missing twice in a row, the
          // VPN is rebuilt on the same server (max 2 tries per connection).
          // (not used in proxy mode: there is no tunnel on purpose)
          final tn = proxyMode ? null : await tunUp();
          if (tn == false) dbg('تونل VPN اندروید (tun) دیده نشد');
          if (!connected || busy || switching) return;
          if (tn == true) {
            tunBad = 0;
            tunFixes = 0;
            if (tunWarn) {
              tunWarn = false;
              if (mounted) setState(() {});
            }
          } else if (tn == false) {
            tunBad++;
            if (tunBad >= 2 &&
                tunFixes < 2 &&
                DateTime.now().difference(lastSwitch) >
                    const Duration(seconds: 12)) {
              tunBad = 0;
              tunFixes++;
              await _restartTunnel();
              return;
            }
          }
          // BAD PING: the server works but is very slow. After 2 bad checks
          // in a row (~10 s) the app jumps at once to the standby server with
          // the lowest ping (it must be clearly better than the current one).
          if (badPingSwitch && p > badPingMs) {
            badPingRun++;
          } else {
            badPingRun = 0;
          }
          if (badPingSwitch &&
              badPingRun >= badPingLimit &&
              DateTime.now().difference(lastSwitch) >
                  const Duration(seconds: 15)) {
            final t = _bestPingStandby(min(badPingMs, (p * 0.7).round()));
            if (t != null) {
              badPingRun = 0;
              lastWhy = 'پینگ بد (${p}ms)';
              await _swapTo(t);
              return;
            }
          }
          // FASTPATCH: a clearly better standby takes over (2 checks in a row)
          if (betterSwitch) {
            final bt = _betterStandby();
            betterRun = bt == null ? 0 : betterRun + 1;
            if (bt != null &&
                betterRun >= 2 &&
                DateTime.now().difference(lastSwitch) > betterEvery) {
              betterRun = 0;
              lastWhy = 'سرور بهتر (${bt.ping}ms)';
              await _swapTo(bt);
              return;
            }
          }
          // Slow / low speed only marks the server; the replacement happens in
          // the next speed window (_upgradeRun). A dead server is dropped at
          // once.
          // ~every 30 s: small download through the tunnel
          if (++speedTick >= 3) {
            speedTick = 0;
            final sp = await measure(
                url: smallSpeedUrl,
                win: const Duration(seconds: 3),
                total: const Duration(seconds: 8),
                direct: true);
            if (!connected || busy || switching) return;
            if (sp == null) {
              noData++;
            } else {
              noData = 0;
              // keep the real speed of the connected server up to date
              current?.speed = sp;
              current?.speedAt = DateTime.now();
              // فقط وقتی سرعت واقعاً نزدیک صفر است (زیر ۴۰ KB/s) حساب شود
              // ۱۰۰ یا ۲۰۰ کیلوبایت دیگر باعث تعویض نمی‌شود
              stallRun = (sp * 1024 < 40) ? stallRun + 1 : 0;
              if (minSpeedKB > 0 && sp * 1024 < minSpeedKB) {
                needTrial = true;
                lowSpeed++;
              } else {
                lowSpeed = 0;
              }
            }
            // فقط وقتی چند بار پشت‌سرهم هیچ داده‌ای نیامد
            if (noData >= 5) {
              noData = 0;
              lastWhy = 'دانلود از سرور صفر است';
              await _failover();
              return;
            }
            // قطع جریان: حداقل ۴ بار زیر ۴۰ KB/s + فاصله زمانی بیشتر
            if (stallRun >= 4 &&
                _ready() > 0 &&
                DateTime.now().difference(lastSwitch) >
                    const Duration(seconds: 45)) {
              stallRun = 0;
              lowSpeed = 0;
              lastWhy = 'قطع جریان داده';
              await _failover();
              return;
            }
            // SPEEDSWITCHPATCH: ping and speed pass but no real site opens
            final sitesOk = await _sitesOpen();
            if (!connected || busy || switching) return;
            // sitesOk == -1 یعنی پورت پروکسی آماده نبود → نادیده بگیر
            if (sitesOk < 0) {
              // تست نامعتبر؛ شمارنده‌ها را دست نزن
            } else if (sitesOk > 0) {
              siteSeen = true;
              siteFail = 0;
              siteNever = 0;
              siteNeverSwitches = 0;
            } else if (siteSeen) {
              siteFail++;
            } else {
              // SITENEVER: خیلی دیرتر و با محدودیت بیشتر تعویض می‌کند
              siteNever++;
              if (siteNever >= 6 &&
                  siteNeverSwitches < 2 &&
                  _ready() > 0 &&
                  DateTime.now().difference(lastSwitch) >
                      const Duration(seconds: 45)) {
                siteNever = 0;
                siteNeverSwitches++;
                current?.svc = 0;
                lastWhy = 'سایت‌ها از ابتدا باز نمی‌شوند';
                await _failover();
                return;
              }
            }
            if (sitesOk >= 0 &&
                siteFail >= 4 &&
                DateTime.now().difference(lastSwitch) >
                    const Duration(seconds: 40)) {
              siteFail = 0;
              lastWhy = 'سایت‌ها باز نمی‌شوند';
              await _failover();
              return;
            }
            // سرعت پایین: فقط بعد از مدت طولانی‌تر و با آستانه بالاتر
            if (lowSpeed >= 6 &&
                _ready() > 0 &&
                DateTime.now().difference(lastSwitch) >
                    const Duration(seconds: 90)) {
              lowSpeed = 0;
              lastWhy = 'سرعت پایین';
              await _failover();
              return;
            }
          }
          _stableTick(p); // STABLEPINGPATCH
          _standbyRun(); // keep searching / replacements topped up
          _refillRun(); // SPEEDSWITCHPATCH
          // no automatic speed trials: they would cut the VPN. Use the
          // speed button in the panel (_upgradeRun(manual: true)) instead.
          return;
        }
        // NETHOLD: the phone itself has no internet (or it just came back):
        // changing servers cannot help, so the VPN is kept and we wait
        if (netDown ||
            DateTime.now().difference(netUpAt) < const Duration(seconds: 15)) {
          _set(netDown
              ? 'اینترنت گوشی قطع است؛ VPN نگه داشته شد، منتظر بازگشت اینترنت...'
              : 'اینترنت برگشت؛ بررسی دوباره‌ی اتصال...');
          return;
        }
        fails++;
        if (fails >= watchFailLimit &&
            DateTime.now().difference(lastSwitch) > minHold) {
          fails = 0;
          final e = lastPingErr.length > 45
              ? lastPingErr.substring(0, 45)
              : lastPingErr;
          lastWhy = 'پینگ ناموفق ($e)';
          await _failover();
        }
      } catch (e) {
        logError(e);
      } finally {
        watchBusy = false;
      }
    });
  }

  double _rate(Server s) {
    final u = s.src;
    if (u == null) return 1.0; // favourites / cache / imported
    return srcRate[u] ?? 0.3;
  }

  bool _srcOk(Server s) {
    if (s.ovpn) return true;
    final u = s.src;
    if (nationalMode && (natAll || _natSrc(s))) return true; // NATIONALPATCH
    if (u == null || !onlyHealthySrc) return true;
    final r = srcRate[u];
    return r == null || r >= 0.25 || topSrc.contains(u);
  }

  // 5 = saved healthy, 4 = pinned, 3 = verified/fast sources, 2 = hot, 1 = rest
  int _tier(Server s) {
    if (warmKeys.contains(s.key)) return 5;
    if (favs.containsKey(s.key)) return 4;
    final o = ownerOf(s);
    if (speedOwners.contains(o)) return 3; // تست اول: کیفیت/سرعت بالا
    if (hotOwners.contains(o)) return 2;
    return 1;
  }

  int _cmpPending(Server a, Server b) {
    if (nationalMode) {
      final nx = _natRank(b) - _natRank(a); // NATIONALPATCH
      if (nx != 0) return nx;
    }
    if (selCountry != null) {
      final x = (b.country == selCountry ? 1 : 0) -
          (a.country == selCountry ? 1 : 0);
      if (x != 0) return x;
    }
    // AI row: healthy servers not yet tested for Gemini come first
    if (connRow == 'r:ai') {
      final z = ((b.ping != null && b.ai == null) ? 1 : 0) -
          ((a.ping != null && a.ai == null) ? 1 : 0);
      if (z != 0) return z;
    }
    if (connected) {
      // while connected only servers already seen alive are worth testing
      final y = (b.ping != null ? 1 : 0) - (a.ping != null ? 1 : 0);
      if (y != 0) return y;
    }
    final t = _tier(b) - _tier(a);
    if (t != 0) return t;
    final r = (_rate(b) * 10).round() - (_rate(a) * 10).round();
    if (r != 0) return r;
    if (smartOrder) {
      final q = (_profRate(b) * 20).round() - (_profRate(a) * 20).round();
      if (q != 0) return q;
    }
    return b.score.compareTo(a.score);
  }

  // real results of a source replace the quick TCP estimate
  void _srcRecord(Server s, bool ok) {
    final u = s.src;
    if (u == null || s.ovpn) return;
    srcTested[u] = (srcTested[u] ?? 0) + 1;
    if (ok) srcOkN[u] = (srcOkN[u] ?? 0) + 1;
    if (srcTested[u]! >= 5) {
      srcRate[u] = (srcOkN[u] ?? 0) / srcTested[u]!;
      srcAt[u] = DateTime.now().millisecondsSinceEpoch;
      srcReal.add(u);
    }
  }

  // quick health check of every list: TCP-probe a random sample of each
  Future<void> _rankSources() async {
    final bySrc = <String, List<Server>>{};
    for (final s in fetchedAll) {
      final u = s.src;
      if (u != null && !s.ovpn) (bySrc[u] ??= []).add(s);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final todo = bySrc.keys.where((u) {
      final age = now - (srcAt[u] ?? 0);
      return srcReal.contains(u) ? age > 6 * 3600000 : age > 30 * 60000;
    }).toList();
    if (todo.isEmpty) return;
    _set('بررسی سلامت ${todo.length} منبع...');
    await pool<String>(todo, 8, (u) async {
      if (abort) return;
      final sample = (bySrc[u]!.toList()..shuffle()).take(14).toList();
      var ok = 0;
      await pool<Server>(sample, 14, (s) async {
        final pg = await probe(s);
        if (pg != null && pg >= 12) ok++;
      });
      srcRate[u] = sample.isEmpty ? 0.0 : ok / sample.length;
      srcAt[u] = now;
      srcReal.remove(u);
      srcTested.remove(u);
      srcOkN.remove(u);
    });
    _saveSrc();
  }

  Future<void> _saveSrc() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          'src_scores',
          jsonEncode({
            for (final k in srcRate.keys)
              k: [srcRate[k], srcAt[k] ?? 0, srcReal.contains(k) ? 1 : 0]
          }));
      await p.setString(
          'prof',
          jsonEncode({
            for (final k in profTested.keys) k: [profTested[k], profOk[k] ?? 0]
          }));
    } catch (e) {
      logError(e);
    }
  }

  // INSPECTORPATCH: self-check every 3 s (only changes / problems are logged)
  Timer? _insT;
  final Map<String, DateTime> _insSince = {};
  final Map<String, DateTime> _insLogged = {};
  String _insSnap = '', _insCnt = '';
  DateTime _insPrev = DateTime.now();
  DateTime _insHb = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _insUpAt;
  DateTime _insBgAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _insBgFreeze = 0;
  int _insOrphan = 0;
  final Map<String, int> _insPrevCnt = {};

  void _inspectStart() {
    _insT?.cancel();
    _insPrev = DateTime.now();
    _insT = Timer.periodic(const Duration(seconds: 3), (_) {
      try {
        _inspect();
      } catch (e) {
        dbg('بازرس: خطا $e');
      }
    });
  }

  // logs [msg] when [cond] has been true for [secs] seconds (and then at
  // most once per [every] seconds)
  void _insWarn(String key, bool cond, int secs, String msg,
      {int every = 120}) {
    final now = DateTime.now();
    if (!cond) {
      _insSince.remove(key);
      return;
    }
    final since = _insSince.putIfAbsent(key, () => now);
    final held = now.difference(since).inSeconds;
    if (held < secs) return;
    final last = _insLogged[key];
    if (last != null && now.difference(last).inSeconds < every) return;
    _insLogged[key] = now;
    dbg('⚠ $msg (${held}s)');
  }

  void _inspect() {
    if (!mounted) return;
    final now = DateTime.now();
    String b(bool v) => v ? '1' : '0';
    final ov = current?.ovpn == true || ovpnActive;

    // the app loop itself was frozen (this timer fires every 3 s)
    final gap = now.difference(_insPrev).inSeconds;
    _insPrev = now;
    if (!inForeground) _insBgAt = now;
    if (gap >= 8) {
      // background (or just resumed): Android slows the timers, NOT a code
      // error -> only counted, not listed as a problem
      if (!inForeground || now.difference(_insBgAt).inSeconds < 15) {
        _insBgFreeze++;
      } else {
        _insBgFreeze++; // only counted, not listed as a problem
      }
    }

    // 1) every change of the main flags (shows the ORDER of events)
    final snap = 'متصل=${b(connected)} هسته=${lastState.isEmpty ? '-' : lastState} '
        'میخواهم=${b(wantVpn)} مشغول=${b(busy)} جستجو=${b(searching)} '
        'تعویض=${b(switching)} لغو=${b(abort)}';
    if (snap != _insSnap) {
      _insSnap = snap;
      dbg('حالت: $snap');
    }

    // 2) watchdog counters
    final cnt = 'پینگ‌ناموفق=$fails tun‌بد=$tunBad تعمیرتونل=$tunFixes '
        'بدون‌داده=$noData کندی=$lowSpeed پینگ‌بد=$badPingRun';
    if (cnt != _insCnt) {
      _insCnt = cnt;
      dbg('شمارنده: $cnt');
    }
    // every counter that went UP is a (tiny) problem of its own
    for (final m in RegExp(r'([^\s=]+)=(-?\d+)').allMatches(cnt)) {
      final k = m.group(1)!;
      final v = int.tryParse(m.group(2)!) ?? 0;
      final o = _insPrevCnt[k] ?? 0;
      if (v > o && v >= 2) {
        dbg('شمارنده‌ی $k بالا رفت ($o → $v)'); // info only, not a problem
      }
      _insPrevCnt[k] = v;
    }

    // 3) how long every connection lasted
    if (connected && _insUpAt == null) _insUpAt = now;
    if (!connected && _insUpAt != null) {
      final d = now.difference(_insUpAt!).inSeconds;
      _insUpAt = null;
      dbg('اتصال ≈${d}s دوام داشت • علت تعویض: '
          '${lastWhy.isEmpty ? '-' : lastWhy} • آخرین خطای شروع: '
          '${lastFail.isEmpty ? '-' : lastFail}');
      if (d < 300 && wantVpn && !switching) {
        dbg('⚠ اتصال زود قطع شد: ${d}s • علت: '
            '${lastWhy.isEmpty ? '-' : lastWhy}');
      }
    }

    // 4) heartbeat once a minute
    if ((wantVpn || connected) && now.difference(_insHb).inSeconds >= 60) {
      _insHb = now;
      final up = _insUpAt == null ? 0 : now.difference(_insUpAt!).inSeconds;
      // اگر بیش از ۳ دقیقه پایدار بود، محدودیت تعویض سایت‌ها را ریست کن
      if (up >= 180 && siteNeverSwitches > 0) {
        siteNeverSwitches = 0;
        siteNever = 0;
      }
      // سیاه‌لیست خیلی بزرگ → پاک‌سازی نرم خودکار (جلوگیری از قفل شدن سرورهای خوب)
      if (failed.length > 80) {
        final cut = now.subtract(const Duration(minutes: 15));
        failed.removeWhere((_, t) => t.isBefore(cut));
        if (failed.length > 120) {
          final keys = failed.keys.toList();
          final n = (keys.length * 0.4).round();
          for (var i = 0; i < n && i < keys.length; i++) {
            failed.remove(keys[i]);
          }
        }
      }
      dbg('♥ متصل ${up}s • ${current?.name ?? '-'} • پینگ ${current?.ping ?? '-'}'
          ' • سرعت ${current?.speed ?? '-'} • سالم ${good.length}'
          ' (آماده ${_ready()}) • صف ${pending.length}'
          ' • سیاه ${failed.length} • جستجو ${b(searching)}');
    }

    // 5) problems
    _insWarn('busy', busy && !searching && !_acquiring && !switching, 330, 'پرچم «مشغول» گیر کرده');
    _insWarn('sw', switching && !busy && !searching && !_acquiring, 60, 'پرچم «تعویض» گیر کرده');
    _insWarn('watchBusy', watchBusy && !busy && !switching && !searching &&
        inForeground, 90, 'واچ‌داگ در یک بررسی گیر کرده');
    _insWarn('upBusy', upBusy, 120, 'تست سرعت/ارتقا گیر کرده');
    _insWarn('rechk', rechecking, 240, 'بازبینی سرورهای سالم گیر کرده');
    // ORPHANFIX: core CONNECTED but the app neither is connected nor wants
    // a VPN (stop was lost): stop the core again so the key icon goes away
    if (lastState == 'CONNECTED' &&
        !wantVpn &&
        !connected &&
        !busy &&
        !switching &&
        !searching &&
        !startAdopt &&
        !ov) {
      if (++_insOrphan >= 2) {
        _insOrphan = 0;
        dbg('هسته‌ی بی‌صاحب خاموش شد (CONNECTED بدون اتصال اپ)');
        try {
          unawaited(v2ray.stopV2Ray().catchError((_) {}));
        } catch (_swE) { _swl('_inspect#orphan', _swE);}
      }
    } else {
      _insOrphan = 0;
    }
    _insWarn('mm1', lastState == 'CONNECTED' && !connected && !busy &&
        !switching && !searching && !ov, 12,
        'هسته CONNECTED است ولی اپ «متصل» نمی‌داند');
    _insWarn('mm2', connected && lastState.isNotEmpty &&
        lastState != 'CONNECTED' && !searching && !ov, 12,
        'اپ «متصل» می‌داند ولی هسته $lastState است');
    final orphaned = wantVpn && !connected && !busy && !switching &&
        !(dropTimer?.isActive ?? false) && !_acquiring && !searching;
    _insWarn('orph', orphaned, 20,
        'اتصال خواسته شده ولی هیچ کاری برای آن در حال انجام نیست');
    // E-ORPHAN self-heal: after ~20s still wanting VPN with nothing running → failover
    if (orphaned && now.difference(_insSince['orph'] ?? now).inSeconds >= 20) {
      _insSince.remove('orph');
      dbg('خودترمیمی: اتصال یتیم >20s؛ _failover()');
      if (inForeground) {
        unawaited(_failover());
      } else {
        pendingFailover = true;
      }
    }
    final dogOff = wantVpn && connected && !busy && !switching &&
        !(watch?.isActive ?? false);
    _insWarn('dog', dogOff, 10, 'واچ‌داگ خاموش است');
    if (dogOff && now.difference(_insSince['dog'] ?? now).inSeconds >= 10) {
      _insSince.remove('dog');
      dbg('همگام‌سازی خودکار: واچ‌داگ خاموش بود؛ دوباره روشن شد');
      _startWatch();
    }
    _insWarn('tunw', connected && tunWarn && !proxyMode, 6,
        'تونل VPN اندروید (tun) دیده نمی‌شود');
    _insWarn('noready', connected && _ready() == 0 && !searching, 60,
        'سرور آماده‌ی جایگزین نیست و جستجویی هم در کار نیست');
    _insWarn('tunfail', tunFailRun >= 6, 0,
        'اندروید پشت‌سرهم تونل نساخته (tunFailRun=$tunFailRun)', every: 600);
    _insWarn('bgdis', bgDisabled, 0,
        'جستجوی پس‌زمینه خودکار غیرفعال شد (تست‌های بی‌نتیجه)', every: 3600);
    _insWarn('fastoff', !fastDelay, 0,
        'تست سریع خاموش شد (جواب نداده بود)', every: 3600);
    final pg = num.tryParse('${current?.ping ?? ''}');
    _insWarn('pingHigh', connected && pg != null && pg > max(5000, badPingMs * 2), 60,
        'پینگ سرور بالاست (${pg ?? '-'} ms)', every: 900);
    final upAge = _insUpAt == null ? 0 : now.difference(_insUpAt!).inSeconds;
    _insWarn('standby', connected && autoUpgrade && !bgDisabled && upAge > 360 &&
        now.difference(lastStandby).inSeconds > 360 && !searching, 0,
        'جستجوی پس‌زمینه بیش از ۶ دقیقه اجرا نشده', every: 600);
  }

  // ERRLOGPATCH
  String _dbgSummary() {
    String yn(bool b) => b ? 'روشن' : 'خاموش';
    return 'اتصال: ${yn(connected)} • مشغول: ${yn(busy)} • در حال جستجو: ${yn(searching)}\n'
        'جستجوی سریع: ${yn(fastDelay)} • تست همزمان: $fastWorkers • تایم‌اوت: ${delayTimeout.inSeconds}s\n'
        'تست سریع: $fastOk/$fastTested موفق • کل: $totalOk/$totalTested\n'
        'سالم: ${good.length} • در صف: ${pending.length} • لیست سیاه: ${failed.length}\n'
        'وضعیت هسته: ${lastState.isEmpty ? '-' : lastState}\n'
        'آخرین خطای شروع: ${lastFail.isEmpty ? '-' : lastFail}\n'
        'تونل ساخته نشد: $tunFailRun • پورت باز نشد: $portFailRun • تست بی‌صدا: ${yn(!viaVpn)}\n'
        'خطاهای شبکه (بی‌اهمیت): $dbgNet\n'
        'همگام‌سازی خودکار هسته/اپ: $_syncFixes بار\n'
        'خطاهای بلعیده‌شده: $_swCount (در $_swSites جای مختلف)';
  }

  void _logSheet() {
    final prev = List<String>.of(dbgPrev);
    var copied = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setS) {
            final cur = dbgLines.reversed.toList();
            final text = '${_dbgProbText()}\n\n${_dbgSummary()}\n\n${cur.join('\n')}'
                '${prev.isEmpty ? '' : '\n\n--- اجرای قبلی ---\n${prev.reversed.join('\n')}'}';
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.85,
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(children: [
                      const Expanded(
                          child: Text('گزارش خطاها',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold))),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: text));
                          copied = true;
                          setS(() {});
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: Text(copied ? 'کپی شد' : 'کپی همه'),
                      ),
                      TextButton(
                        onPressed: () {
                          dbgLines.clear();
                          dbgNet = 0;
                          dbgProbs.clear(); // DIAGPATCH
                          prev.clear();
                          _dbgClearAll();
                          setS(() {});
                        },
                        child: const Text('پاک کردن'),
                      ),
                    ]),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(text,
                          style: const TextStyle(fontSize: 12, height: 1.5)),
                    ),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }

  void _sourcesSheet() {
    final l = srcRate.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: ListView(shrinkWrap: true, children: [
            if (l.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('هنوز منبعی بررسی نشده')),
            for (final e in l)
              ListTile(
                dense: true,
                title: Text(
                    e.key.replaceFirst(_gh, '').split('/').take(2).join('/'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                subtitle:
                    Text(srcReal.contains(e.key) ? 'تست واقعی' : 'تست TCP'),
                trailing: Text('${(e.value * 100).round()}%',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: e.value >= 0.25 ? Color(0xFF86E39A) : Color(0xFFFF8A80))),
              ),
          ]),
        ),
      ),
    );
  }

  // find the country of healthy servers whose name has no country info
  Future<void> _geoFill() async {
    final todo = good.where((s) => s.country == null && !s.geoTried).toList();
    await pool<Server>(todo, 4, (s) async {
      s.geoTried = true;
      try {
        var ip = s.host;
        if (InternetAddress.tryParse(ip) == null) {
          final r = await InternetAddress.lookup(ip)
              .timeout(const Duration(seconds: 3));
          if (r.isEmpty) return;
          ip = r.first.address;
        }
        final res = await http
            .get(Uri.parse('https://ipwho.is/$ip?fields=country_code'))
            .timeout(const Duration(seconds: 4));
        final c = jsonDecode(res.body)['country_code'];
        if (c is String && c.length == 2) s.country = c;
      } catch (_swE) { _swl('_geoFill#1', _swE);}
    });
  }

  void _pickCountry(String? c, BuildContext ctx) {
    Navigator.pop(ctx);
    setState(() {
      selCountry = c;
      pending = [];
    });
    SharedPreferences.getInstance().then((p) {
      if (c == null) {
        p.remove('country');
      } else {
        p.setString('country', c);
      }
    });
    // Rebuild the queue for the new country filter so the next connect/search
    // does not sit on an empty pending until the user taps something else.
    if (!connected && !busy && !searching) {
      unawaited(_loadPending(bg: true));
    }
    _set(c == null
        ? 'فیلتر کشور: همه کشورها'
        : 'فیلتر کشور: ${flagOf(c)} ${countryFa[c] ?? c}');
  }

  void _countrySheet() {
    final cnt = <String, int>{};
    for (final s in fetchedAll) {
      final c = s.country;
      if (c != null) cnt[c] = (cnt[c] ?? 0) + 1;
    }
    // every known country is listed (also the ones with no server yet)
    final keys = countryFa.keys.toList()
      ..sort((a, b) => (cnt[b] ?? 0).compareTo(cnt[a] ?? 0));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: ListView(shrinkWrap: true, children: [
            ListTile(
                title: const Text('🌍 همه کشورها'),
                selected: selCountry == null,
                onTap: () => _pickCountry(null, ctx)),
            for (final c in keys)
              ListTile(
                title: Text('${flagOf(c)} ${countryFa[c] ?? c}'),
                trailing: Text('${cnt[c] ?? 0}'),
                selected: selCountry == c,
                onTap: () => _pickCountry(c, ctx),
              ),
          ]),
        ),
      ),
    );
  }

  // download test of the best [n] servers (VPN must be off). [from] = the
  // candidates in the wanted order (the saved-speed order of _pickList);
  // servers measured in the last 2 minutes are not measured again.
  Future<void> _speedTest(int n, {List<Server>? from}) async {
    final base = from ??
        _usable().where((s) => !identical(s, current) && !s.ovpn).toList();
    final list = base.where((s) => !s.ovpn).take(n).toList();
    var i = 0;
    for (final s in list) {
      if (abort) break;
      i++;
      if (s.speedAt != null &&
          (s.speed ?? 0) > 0 &&
          DateTime.now().difference(s.speedAt!) < const Duration(minutes: 2)) {
        continue;
      }
      _set('تست سرعت $i/${list.length} • ${s.name}');
      var sp = 0.0;
      var tunnel = viaVpn;
      var ok = await _start(s, proxyOnly: !tunnel);
      if (ok && !tunnel) {
        if (!await waitProxyPort(max: const Duration(seconds: 4))) {
          await _stopV2();
          await Future.delayed(const Duration(milliseconds: 350));
          tunnel = true;
          ok = await _start(s);
        }
      }
      if (ok) {
        sp = await measure(
                win: const Duration(milliseconds: 1500),
                total: const Duration(seconds: 7),
                direct: tunnel) ??
            0;
      }
      s.speed = sp;
      s.speedAt = DateTime.now();
      if (sp == 0) s.badAt = DateTime.now();
      await _stopV2();
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) setState(() {});
    }
    sortSpeed = true;
    _set('تست سرعت تمام شد');
  }

  Future<void> _copyGood() async {
    final u = _usable();
    await Clipboard.setData(
        ClipboardData(text: u.map((s) => s.link).join('\n')));
    _set('${u.length} سرور کپی شد');
  }

  void _importDialog() {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('افزودن کانفیگ'),
          content: TextField(
            controller: c,
            maxLines: 6,
            decoration: const InputDecoration(
                hintText:
                    'هر خط یک کانفیگ (vmess / vless / trojan / ss)\nمتن اضافه دور لینک مهم نیست\nیا متن کامل یک فایل OpenVPN'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('لغو')),
            FilledButton(
              onPressed: () {
                final added = <Server>[];
                final whole = ovpnFromText(c.text, name: '🔒 OpenVPN دستی');
                if (whole != null) {
                  added.add(whole);
                } else {
                  for (final l in npvSplit(c.text)) {
                    final s = Server.parse(l);
                    if (s != null) added.add(s);
                  }
                }
                for (final s in added) {
                  // the cleaned link is saved
                  favs[s.key] = s.link;
                  favObj.remove(s.key);
                  if (!good.any((g) => g.key == s.key) &&
                      !pending.any((p) => p.key == s.key)) {
                    pending.insert(0, s);
                  }
                }
                _saveFavs();
                Navigator.pop(ctx);
                setState(() {});
                _set(added.isEmpty
                    ? 'کانفیگ معتبر پیدا نشد'
                    : '${added.length} کانفیگ اضافه شد • در بخش «📌 کانفیگ‌های من» است');
              },
              child: const Text('افزودن'),
            ),
          ],
        ),
      ),
    ).whenComplete(() => c.dispose());
  }

  // choose the apps that do NOT go through the VPN
  Future<void> _appsSheet() async {
    List<AppInfo> apps = [];
    try {
      apps = await InstalledApps.getInstalledApps(false, false);
    } catch (e) {
      logError(e);
      return;
    }
    apps.removeWhere((a) => '${a.packageName}' == ownPkg);
    apps.sort((a, b) =>
        '${a.name}'.toLowerCase().compareTo('${b.name}'.toLowerCase()));
    if (!mounted) return;
    final before = bypassApps.toSet();
    var q = '';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {
        final list = apps
            .where((a) =>
                q.isEmpty ||
                '${a.name}'.toLowerCase().contains(q) ||
                '${a.packageName}'.toLowerCase().contains(q))
            .toList();
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.8,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: const InputDecoration(
                        hintText: 'جستجوی برنامه',
                        prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setS(() => q = v.toLowerCase()),
                  ),
                ),
                Text('تیک‌خورده‌ها از VPN رد نمی‌شوند (${bypassApps.length})',
                    style: const TextStyle(fontSize: 12)),
                Expanded(
                  child: ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final a = list[i];
                      final pk = '${a.packageName}';
                      return CheckboxListTile(
                        dense: true,
                        title: Text('${a.name}',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle:
                            Text(pk, style: const TextStyle(fontSize: 12)),
                        value: bypassApps.contains(pk),
                        onChanged: (v) => setS(() {
                          if (v == true) {
                            if (!bypassApps.contains(pk)) bypassApps.add(pk);
                          } else {
                            bypassApps.remove(pk);
                          }
                        }),
                      );
                    },
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('bypass', bypassApps);
    } catch (e) {
      logError(e);
    }
    // while connected the tunnel is rebuilt on the same server, so the new
    // choice applies at once
    final now = bypassApps.toSet();
    final changed = before.length != now.length || !before.containsAll(now);
    if (connected && changed) _restartTunnel();
    if (mounted) setState(() {});
  }

  void _settingsSheet() {
    final pmBefore = proxyMode;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {
        Widget row(String t, String label, double v, double mn, double mx,
                int div, void Function(double) f) {
          final bad = t.startsWith('پینگ بد');
          final speed = t.startsWith('تعویض اگر سرعت');
          final lo = (t.startsWith('حداقل پینگ') || speed) ? 0 : (bad ? 70 : 1);
          final hi = bad ? 7000 : (speed ? 50000 : 1000);
          final smn = bad ? 70.0 : mn, smx = bad ? 7000.0 : mx;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$t: $label'),
            Slider(
                value: v.clamp(smn, smx).toDouble(),
                min: smn,
                max: smx,
                divisions: (bad || div <= 0) ? null : div,
                onChanged: (x) => setS(() => f(x))),
            Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: TextFormField(
                  key: ValueKey('$t|${v.round()}'),
                  initialValue: '${v.round()}',
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      helperText: 'عدد دلخواه: $lo تا $hi'),
                  onChanged: (txt) {
                    final n = int.tryParse(txt.trim());
                    if (n == null) return;
                    f(n.clamp(lo, hi).toDouble());
                  },
                ),
              ),
          ]);
        }
        Widget sw(String t, bool v, void Function(bool) f, {String? sub}) =>
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t),
              subtitle: sub == null ? null : Text(sub),
              value: v,
              onChanged: (x) => setS(() => f(x)),
            );
        Widget head(String t) => Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: Text(t,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.deepPurple)),
            );
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    head('🤖 تنظیم خودکار'),
                    sw('تنظیم خودکار بر اساس سرعت اینترنت', autoTune, (v) {
                      autoTune = v;
                      autoTuneSave();
                      if (v && !connected) autoTuneNow(force: true);
                    },
                        sub: tuneInfo.isEmpty
                            ? 'اسلایدرهای سرعت و تعویض خودکار تنظیم می‌شوند؛ برای دستی نگه داشتن، خاموش کن'
                            : tuneInfo),
                    head('🧩 نوع اتصال'),
                    sw('حالت پروکسی (بدون VPN)', proxyMode,
                        (v) => proxyMode = v,
                        sub:
                            'فقط یک پروکسی محلی روشن می‌شود: SOCKS روی 127.0.0.1:10808 و HTTP روی 127.0.0.1:10809. آیکن کلید VPN نمی‌آید و برنامه‌های دیگر خودکار رد نمی‌شوند؛ باید در آن‌ها (یا در تنظیم پروکسی Wi-Fi) این آدرس را بدهی'),
                    this.resetNumButton(setS),
                    head('⚡ سرعت تست'),
                    row('تست همزمان (جستجوی اول)', '$fastWorkers',
                        fastWorkers.toDouble(), 1, 100, 99,
                        (x) => fastWorkers = x.round()),
                    row('تست همزمان (وقتی وصل است)', '$bgWorkers',
                        bgWorkers.toDouble(), 1, 6, 5,
                        (x) {
                          bgWorkers = x.round();
                          natWorkers = bgWorkers; // NATWORKERSPATCH
                        }),
                    row('تایم‌اوت هر تست', '${delayTimeout.inSeconds} ثانیه',
                        delayTimeout.inSeconds.toDouble(), 3, 10, 7,
                        (x) => delayTimeout = Duration(seconds: x.round())),
                    row('اندازه دسته', '$batchSize', batchSize.toDouble(), 50,
                        1000, 0, (x) => batchSize = x.round()),
                    row('حداقل پینگ معتبر (۰ = خاموش، سرعت واقعی تصمیم می‌گیرد)',
                        '$minPingMs ms', minPingMs.toDouble(), 0, 300, 12,
                        (x) => minPingMs = x.round()),
                    head('🔎 پیدا کردن سرور سالم'),
                    sw('تست سرورهای ذخیره‌شده اول', savedFirst,
                        (v) => savedFirst = v,
                        sub:
                            'سرورهای سالمِ دفعه قبل اول تست می‌شوند، بعد لیست جدید'),
                    sw('ترتیب هوشمند تست', smartOrder, (v) => smartOrder = v,
                        sub:
                            'نوعی که روی این اینترنت جواب می‌دهد اول؛ منبع بی‌نتیجه رد می‌شود'),
                    sw('چرخش خودکار لیست', autoCycle, (v) => autoCycle = v,
                        sub:
                            'وقتی همه تست شد، لیست جدید گرفته می‌شود و ادامه دارد'),
                    sw('حالت فوق‌العاده (ماتریس حالت‌ها)', ultraMode,
                        (v) => ultraMode = v,
                        sub:
                            'حتی در اتصال عادی هر سرور با ده‌ها حالت (Fragment، fingerprint، ALPN، DNS، Mux، Noise، پورت CDN، IP تمیز و ...) تست می‌شود — هیچ اپ تجاری این کار را نمی‌کند'),
                    sw('حالت شکست‌ناپذیر (جستجوی بی‌نهایت)', indestructibleMode,
                        (v) => indestructibleMode = v,
                        sub:
                            'در نت ملی یا وقتی دکمه نت ملی زده شود جستجو هرگز متوقف نمی‌شود؛ سطح را بالا می‌برد، لیست را تازه می‌کند و تا پیدا شدن کانفیگ وصل‌شدنی ادامه می‌دهد'),
                    sw('توربو سرعت بعد از اتصال', turboSpeed,
                        (v) => turboSpeed = v,
                        sub:
                            'بعد از وصل شدن، Fragment/Noise خاموش و Mux با concurrency بالا روشن می‌شود؛ چند حالت سبک تست می‌شود و سرعت واقعی اندازه‌گیری می‌شود تا دانلود چند برابر شود'),
                    sw('فقط از منابع سالم سرور بردار', onlyHealthySrc,
                        (v) => onlyHealthySrc = v),
                    sw('اتصال با IP (حل دامنه با DoH)', ipMode,
                        (v) => ipMode = v),
                    sw('جستجوی سریع (تست موازی)', fastDelay, (v) {
                      fastDelay = v;
                      fastTested = 0;
                      fastOk = 0;
                    },
                        sub:
                            'چند سرور همزمان و بدون روشن/خاموش کردن VPN تست می‌شوند'),
                    sw('جستجوی مداوم سرور جدید (بدون قطع)', autoUpgrade,
                        (v) => autoUpgrade = v,
                        sub:
                            'وقتی وصل هستی، سرورهای جدید با پینگ تست می‌شوند'),
                    row('هر چند دقیقه لیست جدید (وقتی همه تست شد هم عوض می‌شود)',
                        '$listRefreshMin دقیقه',
                        listRefreshMin.toDouble(), 2, 240, 0,
                        (x) => listRefreshMin = x.round()),
                    row('سرور خراب تا چند دقیقه تست نشود', '$failMin دقیقه',
                        failMin.toDouble(), 5, 120, 23, (x) {
                      failMin = x.round();
                      failWindow = Duration(minutes: failMin);
                    }),
                    row('بررسی دوباره سرورهای سالم', 'هر $recheckMin دقیقه',
                        recheckMin.toDouble(), 2, 30, 28, (x) {
                      recheckMin = x.round();
                      recheckAfter = Duration(minutes: recheckMin);
                    }),
                    ...iranSettingsItems(head, sw),
                    ...npvAmSettingsItems(head, sw, () => ipMode = true),
                    ...numSettingsItems(head, row),
                    head('🚀 اتصال و تعویض'),
                    sw('تست سرعت چند سرور برتر قبل از اتصال', autoSpeed,
                        (v) => autoSpeed = v,
                        sub: 'به سریع‌ترین سرور وصل می‌شود'),
                    row('تعداد سرور برای تست سرعت', '$speedTopN',
                        speedTopN.toDouble(), 1, 8, 7,
                        (x) => speedTopN = x.round()),
                    sw('تعویض سریع وقتی پینگ خیلی بد شد', badPingSwitch,
                        (v) => badPingSwitch = v,
                        sub: 'به سروری با کمترین پینگ می‌رود'),
                    row('پینگ بد از', '$badPingMs ms', badPingMs.toDouble(),
                        500, 5000, 18, (x) => badPingMs = x.round()),
                    row(
                        'تعویض اگر سرعت کمتر از',
                        minSpeedKB == 0 ? 'خاموش' : '$minSpeedKB KB/s',
                        minSpeedKB.toDouble(),
                        0,
                        1000,
                        20,
                        (x) => minSpeedKB = x.round()),
                    ...ultimateSettingsItems(setS),
                    SizedBox(height: MediaQuery.of(ctx).viewInsets.bottom + 60),
                  ]),
            ),
          ),
        );
      }),
    ).then((_) {
      _saveSettings();
      if (mounted) setState(() {});
      // the connection type changed while connected: rebuild it right away
      if (connected && pmBefore != proxyMode && !busy) _restartTunnel();
    });
  }

  String _ago(DateTime? t) {
    if (t == null) return 'تست نشده';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return '${d.inSeconds} ثانیه پیش';
    if (d.inMinutes < 60) return '${d.inMinutes} دقیقه پیش';
    return '${d.inHours} ساعت پیش';
  }

  // speed monitor: connected server + the fastest standbys, with real speed,
  // ping and the time of the last speed test
  Widget _speedPanel(List<Server> u) {
    final list = <Server>[];
    if (connected && current != null) list.add(current!);
    final others = u
        .where((s) => !(connected && identical(s, current)))
        .toList()
      ..sort(bySpeedThenPing);
    list.addAll(others);
    if (list.isEmpty) return const SizedBox.shrink();
    const nextTxt = '';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
          color: Color(0xFF2A2D33),
          border: Border.all(color: const Color(0x66D9AE55)),
          borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => showPanel = !showPanel),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(children: [
              Expanded(
                  child: Text('📊 سرعت واقعی سرورها$nextTxt',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12))),
              if (connected || upBusy)
                TextButton(
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: upBusy
                      ? () => abort = true
                      : busy
                          ? null
                          : () => _upgradeRun(manual: true),
                  child: Text(upBusy ? 'توقف' : 'تست پینگ',
                      style: const TextStyle(fontSize: 12)),
                ),
              Icon(showPanel ? Icons.expand_less : Icons.expand_more,
                  size: 18),
            ]),
          ),
        ),
        if (showPanel)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 230),
            child: SingleChildScrollView(
              child: Column(children: [
          for (final s in list)
            InkWell(
              onTap: (connected && identical(s, current))
                  ? null
                  : () => connect(s),
              child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(children: [
                SizedBox(
                  width: 56,
                  child: Text(
                      connected && identical(s, current)
                          ? 'متصل'
                          : 'سالم',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: connected && identical(s, current)
                              ? Color(0xFF86E39A)
                              : Color(0xFF8CCBFF))),
                ),
                Expanded(
                    child: Text(s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12))),
                SizedBox(
                  width: 62,
                  child: Text(
                      (s.speed ?? 0) > 0
                          ? '${s.speed!.toStringAsFixed(1)} MB/s'
                          : '—',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                SizedBox(
                  width: 50,
                  child: Text('${s.ping ?? '-'}ms',
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(fontSize: 12, color: Color(0xFFCDD1D8))),
                ),
                SizedBox(
                  width: 66,
                  child: Text(_ago(s.speedAt),
                      textAlign: TextAlign.end,
                      style:
                          const TextStyle(fontSize: 12, color: Color(0xFFCDD1D8))),
                ),
              ]),
            ),
            ),
              ]),
            ),
          ),
        const SizedBox(height: 4),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = _usable();
    final uSet = u.toSet();
    // one group per row / country / source, best server first inside each
    final groups = <String, List<Server>>{}; // row id -> servers
    final titles = <String, String>{};
    // fixed first lines (every display mode):
    // 1) personal server, 2) my own configs, 3) AI servers (Gemini opens)
    groups['p:personal'] = personal == null ? [] : [personal!];
    titles['p:personal'] = '🏠 سرور شخصی';
    groups['f:mine'] = _mineList();
    titles['f:mine'] = '📌 کانفیگ‌های من';
    groups['r:ai'] = u.where((s) => s.ai == true && s.ping != null).toList();
    titles['r:ai'] = '🤖 سرورهای مخصوص هوش مصنوعی (Gemini)';
    if (groupMode == 'country') {
      for (final s in u) {
        final c = s.country ?? '??';
        (groups['c:$c'] ??= []).add(s);
        titles['c:$c'] =
            c == '??' ? '🌐 نامشخص' : '${flagOf(c)} ${countryFa[c] ?? c}';
      }
    } else if (groupMode == 'source') {
      final owners = <String>{};
      for (final s in fetchedAll) {
        final o = ownerOf(s);
        if (o != null) owners.add(o);
      }
      final tmp = <String, List<Server>>{
        for (final o in owners) o: u.where((s) => ownerOf(s) == o).toList()
      };
      final keys = tmp.keys.toList()
        ..sort((a, b) => tmp[b]!.length.compareTo(tmp[a]!.length));
      for (final o in keys) {
        groups['s:$o'] = tmp[o]!;
        titles['s:$o'] = '📚 $o';
      }
    } else {
      // every row is always shown, even before it has a healthy server
      final used = <Server>{};
      for (final d in rowDefs) {
        if (d.id == 'ai') continue; // already shown as the second line
        final l = u.where(d.test).toList();
        groups['r:${d.id}'] = l;
        titles['r:${d.id}'] = d.title;
        used.addAll(l);
      }
      groups['r:other'] = u.where((s) => !used.contains(s)).toList();
      titles['r:other'] = '📦 سایر';
    }
    Widget header(String t) => Container(
          width: double.infinity,
          color: Color(0xFF2A2D33),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
        );
    Widget rowHeader(String gid, String t) => InkWell(
          onTap: () => connectRow(gid),
          child: Container(
            width: double.infinity,
            color: Color(0xFF2A2D33),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Expanded(
                  child: Text(t,
                      style: const TextStyle(fontWeight: FontWeight.bold))),
              const Icon(Icons.play_circle_outline, size: 20),
            ]),
          ),
        );
    final rows = <Object>[];
    rows.add(searchAllRow(() => connect()));
    groups.forEach((g, l) {
      if (g == 'p:personal') {
        rows.add(_personalHeader());
        rows.add(tgProxyRow(context));
      } else if (g == 'f:mine') {
        rows.add(rowHeader(
            g,
            '${titles[g]} • '
            '${l.isEmpty ? 'خالی — از منو «افزودن کانفیگ» را بزن' : '${l.length} کانفیگ • بزن تا مستقیم وصل شود'}'));
      } else {
        rows.add(rowHeader(
            g,
            '${titles[g]} • '
            '${l.isEmpty ? 'سالمی نیست — بزن تا همین‌جا جستجو کنه' : '${l.length} سرور • بهترین: ${l.first.ping ?? '-'}ms'}'));
      }
      for (final s in l) {
        rows.add(MapEntry(s, g));
      }
    });
    // the pinned configs are already shown in their own row
    final waiting = pending.where((s) => !favs.containsKey(s.key)).toList();
    if (waiting.isNotEmpty) {
      rows.add(header('تست‌نشده'));
      rows.addAll(waiting.take(30));
    }
    final el = (searchSw?.elapsedMilliseconds ?? 0) / 1000;
    final rate = el > 0 ? totalTested / el : 0.0;
    final okPct = totalTested > 0 ? 100 * totalOk / totalTested : 0.0;
    final best =
        u.isEmpty ? '-' : '${u.map((s) => s.ping ?? 99999).reduce(min)}ms';
    Widget stat(String l, String v) {
      if (l == 'دسته' || l == 'تست/ثانیه' || l == 'موفقیت' || l == 'بهترین') {
        return const SizedBox.shrink();
      }
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          decoration: BoxDecoration(
              color: const Color(0xFF2A2D33),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x66D9AE55))),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(children: [
              Text(v,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFFD9AE55))),
              Text(l,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFFCDD1D8))),
            ]),
          ),
        ),
      );
    }
    return PopScope(
      // while the VPN is on, "back" only minimizes the app: the process and
      // the standby search keep running
      canPop: !(connected || wantVpn),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        try {
          await bgChannel.invokeMethod('back');
        } catch (_swE) { _swl('build#3', _swE);
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          Text('VPN', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD9AE55))),
          SizedBox(width: 8),
          Icon(Icons.workspace_premium, color: Color(0xFFD9AE55), size: 22),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.speed),
            onPressed: (busy || connected || u.isEmpty)
                ? null
                : () {
                    abort = false;
                    _runBusy(() async {
                      switching = true;
                      try {
                        await _speedTest(5);
                        await _saveCache();
                      } finally {
                        _unlockLater();
                      }
                    });
                  },
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'set') _settingsSheet();
              if (v == 'apps') _appsSheet();
              if (v == 'add') _importDialog();
              if (v == 'cleanip') cleanIpDialog();
              if (v == 'npvadv') npvAdvDialog();
              if (v == 'sub') subDialog();
              if (v == 'copy') _copyGood();
              if (v == 'src') _sourcesSheet();
              if (v == 'log') _logSheet();
              if (v == 'diag') netDiagDialog();
              if (v == 'dna') _plusDnaBoard();
              if (v == 'diagfull') exportFullDiag();
              if (v == 'panic') panicNow();
              if (v == 'offline') connectBestCached();
              if (v == 'plus') plusSheet();
              if (v == 'donate') donateSheet(context);
              if (v == 'shop') serverShopOpen(context);
              if (v == 'tgch') telegramChannelsOpen(context);
              if (v == 'admin') _uiOpenAdmin(context);
              if (v == 'reset') resetAllServers();
              if (v == 'clear') {
                setState(() {
                  failed.clear();
                  for (final g in good) {
                    g.badAt = null;
                    g.miss = 0;
                  }
                });
                // Persist so blacklist does not come back after app restart
                unawaited(_saveCache());
                _set('لیست سیاه پاک شد');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'apps', child: Text('برنامه‌های خارج از VPN')),
              PopupMenuItem(value: 'set', child: Text('تنظیمات تست')),
              PopupMenuItem(value: 'add', child: Text('افزودن کانفیگ')),
              PopupMenuItem(value: 'cleanip', child: Text('IP تمیز (AM)')),
              PopupMenuItem(value: 'npvadv', child: Text('تنظیمات پیشرفته NPV/AM')),
              PopupMenuItem(value: 'sub', child: Text('افزودن لینک اشتراک')),
              PopupMenuItem(value: 'copy', child: Text('کپی سرورهای سالم')),
              PopupMenuItem(value: 'src', child: Text('وضعیت منابع')),
              PopupMenuItem(value: 'clear', child: Text('پاک کردن لیست سیاه')),
              PopupMenuItem(value: 'diag', child: Text('تشخیص شبکه')),
              PopupMenuItem(
                  value: 'dna', child: Text('جدول DNA اپراتور / برندگان')),
              PopupMenuItem(
                  value: 'diagfull', child: Text('گزارش کامل تشخیص (کپی)')),
              PopupMenuItem(
                  value: 'offline', child: Text('وصل فقط از سرورهای ذخیره‌شده')),
              PopupMenuItem(
                  value: 'panic', child: Text('⚠ حالت اضطراری (قطع + پاکسازی)')),
              PopupMenuItem(value: 'plus', child: Text('ابزارهای بیشتر')),
              PopupMenuItem(value: 'admin', child: Text('ارتباط با ادمین 💬')),
              PopupMenuItem(value: 'shop', child: Text('خرید سرور شخصی 🛒')),
              PopupMenuItem(value: 'tgch', child: Text('کانال‌های تلگرامی 📢')),
              PopupMenuItem(value: 'donate', child: Text('حمایت از ما ❤️')),
              PopupMenuItem(value: 'log', child: Text('گزارش خطاها')),
              PopupMenuItem(
                  value: 'reset',
                  child: Text('پاک کردن همه سرورها و جستجو از نو')),
            ],
          ),
          // مداد جادویی: تنظیم خودکار سرعت/پینگ/تعداد worker بر اساس اینترنت
          IconButton(
            tooltip: autoTune
                ? 'مداد جادویی روشن — لمس = خاموش'
                : 'مداد جادویی خاموش — لمس = روشن (تنظیم خودکار)',
            icon: Icon(
                autoTune ? Icons.auto_fix_high : Icons.auto_fix_off_outlined,
                color: autoTune ? const Color(0xFFFFC107) : null),
            onPressed: () {
              setState(() => autoTune = !autoTune);
              autoTuneSave();
              if (autoTune && !connected) {
                unawaited(autoTuneNow(force: true));
              }
              _set(autoTune
                  ? '✨ مداد جادویی روشن — عددها با سرعت اینترنت تنظیم می‌شوند'
                  : 'مداد جادویی خاموش — عددها دستی می‌مانند');
            },
          ),
          // refresh = search again and connect. The healthy servers are NOT
          // deleted: they are only marked "unchecked" and tested first.
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: (busy || connected)
                ? null
                : () {
                    for (final g in good) {
                      g.checkedAt = null;
                    }
                    pending = [];
                    failed.clear();
                    listTime = null;
                    viaVpn = true;
                    portFailRun = 0;
                    pxTested = 0;
                    pxOk = 0;
                    fastDelay = true;
                    fastTested = 0;
                    fastOk = 0;
                    connect();
                  },
          ),
        ],
      ),
      bottomNavigationBar: UiNav(items: [
        UiNavItem(Icons.person_outline, 'پروفایل', () => _importDialog()),
        UiNavItem(Icons.settings_outlined, 'تنظیمات', () => _settingsSheet()),
        UiNavItem(Icons.dns_outlined, 'سرورها', busy ? null : () => _countrySheet()),
      ]),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: rows.length + 1,
              itemBuilder: (_, i0) {
                if (i0 == 0) {
                  return UiKeep(child: Column(children: [
UiHero(
            on: connected,
            busy: busy,
            label: connected
                    ? 'قطع اتصال'
                    : busy
                        ? 'لغو'
                        : 'اتصال',
            ping: (connected && current != null && current!.ping != null)
                ? '${current!.ping}'
                : '-',
            speed: (connected && current != null && (current!.speed ?? 0) > 0)
                ? current!.speed!.toStringAsFixed(1)
                : '-',
            onTap: connected
                    ? () => disconnect()
                    : busy
                        ? () => abort = true
                        : () {
                          aiSession = false;
                          connect();
                        },
          ),
          if (busy)
            LinearProgressIndicator(
                value: realTotal > 0 && searchSw?.isRunning == true
                    ? (realTested / realTotal).clamp(0.0, 1.0)
                    : null),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                stat('لیست', '$total'),
                stat('سالم', '${u.length}'),
                stat('در صف', '${pending.length}'),
                stat('دسته', '$batchNo'),
                stat('تست/ثانیه', rate.toStringAsFixed(1)),
                stat('موفقیت', '${okPct.toStringAsFixed(1)}%'),
                stat('بهترین', best),
              ],
            ),
          ),
          UiStatus(text: status, on: connected),
          ValueListenableBuilder<bool>(
            valueListenable: autoTestRunning,
            builder: (_, running, __) {
              if (!running) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ValueListenableBuilder<String>(
                      valueListenable: autoTestText,
                      builder: (_, t, __) => Text(
                        '🧪 $t',
                        style: const TextStyle(fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ValueListenableBuilder<double>(
                      valueListenable: autoTestProgress,
                      builder: (_, p, __) => LinearProgressIndicator(value: p),
                    ),
                    TextButton(
                      onPressed: stopAutoTest,
                      child: const Text('توقف تست خودکار'),
                    ),
                  ],
                ),
              );
            },
          ),
          const OnlineBadge(),
          _speedPanel(u),
          aiBar(),
          Padding( // NATBTNPATCH
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: OutlinedButton.icon(
              onPressed: (busy || connected)
                  ? null
                  : () {
                      natForce = true;
                      connect();
                    },
              icon: const Icon(Icons.public_off),
              label: const Text('جستجوی سرور با نت ملی'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: const StadiumBorder()),
            ),
          ),
          Padding( // NATRESPATCH
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: OutlinedButton.icon(
              onPressed: _resMenu,
              icon: const Icon(Icons.folder_special_outlined),
              label: Text('پوشه‌ی سرورهای سالم (${_resMap.length})'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder()),
            ),
          ),
          UiTools(items: [
            UiTool(Icons.support_agent, 'ارتباط با ادمین', () => _uiOpenAdmin(context)),
            UiTool(Icons.tune, 'پروفایل‌ها', () => _profilesSheet()),
            UiTool(
                Icons.auto_fix_high,
                autoNetOn ? 'حالت شبکه: خودکار ✓' : 'حالت شبکه: دستی',
                () {
                  setState(() => autoNetOn = !autoNetOn);
                  autoNetSave();
                  _set(autoNetOn
                      ? 'حالت شبکه خودکار روشن شد؛ هر بار قبل از اتصال شبکه را می‌سنجد'
                      : 'حالت شبکه خودکار خاموش شد؛ تنظیمات دستی می‌مانند');
                }),
            UiTool(Icons.add_home_outlined, 'ساخت سرور شخصی', () => connectPersonal()),
            UiTool(Icons.shopping_cart_outlined, 'خرید سرور شخصی', () => serverShopOpen(context)),
            UiTool(Icons.campaign_outlined, 'کانال‌های تلگرامی', () => telegramChannelsOpen(context)),
            UiTool(Icons.cleaning_services_outlined, 'IP تمیز (AM)', () => cleanIpDialog()),
            UiTool(Icons.rocket_launch_outlined, 'سرور Hiddify', () => vsOpen(context, VsKind.hiddify)),
            UiTool(Icons.dns_outlined, 'سرور SlipNet', () => vsOpen(context, VsKind.slipnet)),
            UiTool(Icons.vpn_lock_outlined, 'سرور VPN Client Pro', () => vsOpen(context, VsKind.vpnclient)),
            UiTool(Icons.vaccines_outlined, 'سرور HTTP Injector', () => vsOpen(context, VsKind.injector)),
            UiTool(Icons.send_outlined, 'پروکسی تلگرام', () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => SafeArea(
                    child: SingleChildScrollView(child: tgProxyRow(context))))),
            UiTool(Icons.push_pin_outlined, 'کانفیگ‌های من', () => connectRow('f:mine')),
            UiTool(Icons.auto_awesome, 'سرورهای AI', () => connectRow('r:ai')),
            UiTool(Icons.pin_outlined, 'اتصال با IP', () => connectRow('r:ip')),
            UiTool(Icons.cloud_outlined, 'CDN / کلودفلر', () => connectRow('r:cdn')),
            UiTool(Icons.shield_outlined, 'Reality', () => connectRow('r:reality')),
            UiTool(Icons.power_outlined, 'WebSocket', () => connectRow('r:ws')),
            UiTool(Icons.favorite_border, 'حمایت از ما', () => donateSheet(context)),
            UiTool(Icons.bug_report_outlined, 'تست خودکار ۲۰ دقیقه', () {
              if (isAutoTesting) {
                stopAutoTest();
              } else {
                startAutoTest20();
              }
            }),
            UiTool(Icons.menu_book_outlined, 'راهنما', () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const HelpPage()))),
          ]),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              // connection type: VPN (tunnel + key icon) or only a local proxy
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ActionChip(
                  label: Text(proxyMode ? '🧩 حالت: پروکسی' : '🔐 حالت: VPN'),
                  onPressed: busy
                      ? null
                      : () {
                          setState(() => proxyMode = !proxyMode);
                          _saveSettings();
                          if (connected) {
                            _restartTunnel();
                          } else {
                            _set(proxyMode
                                ? 'حالت پروکسی: بعد از اتصال، SOCKS روی 127.0.0.1:10808 و HTTP روی 127.0.0.1:10809 است'
                                : 'حالت VPN');
                          }
                        },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ActionChip(
                  label: Text(selCountry == null
                      ? '🌍 کشور'
                      : '${flagOf(selCountry!)} ${countryFa[selCountry] ?? selCountry}'),
                  onPressed: busy ? null : _countrySheet,
                ),
              ),
              for (final pr in ['all', 'vmess', 'vless', 'trojan', 'ss'])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    label: Text(pr == 'all'
                        ? 'همه'
                        : pr == 'ovpn'
                            ? 'OpenVPN'
                            : pr),
                    selected: pr == 'all' ? protoSel.isEmpty : protoSel.contains(pr),
                    onSelected: busy
                        ? null
                        : (_) => setState(() {
                              if (pr == 'all') {
                                protoSel.clear();
                              } else if (!protoSel.remove(pr)) {
                                protoSel.add(pr);
                              }
                              pending = [];
                            }),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ActionChip(
                  label: Text(groupMode == 'type'
                      ? 'نمایش: دسته‌ها'
                      : groupMode == 'country'
                          ? 'نمایش: کشورها'
                          : 'نمایش: منابع'),
                  onPressed: () => setState(() => groupMode =
                      groupMode == 'type'
                          ? 'country'
                          : groupMode == 'country'
                              ? 'source'
                              : 'type'),
                ),
              ),
              ChoiceChip(
                label: Text(sortSpeed ? 'مرتب: سرعت' : 'مرتب: پینگ'),
                selected: sortSpeed,
                onSelected: (v) => setState(() => sortSpeed = v),
              ),
            ]),
          ),
          
                  ]));
                }
                final i = i0 - 1;
                final r0 = rows[i];
                if (r0 is Widget) return r0;
                String? gid;
                final Server s;
                if (r0 is MapEntry<Server, String>) {
                  s = r0.key;
                  gid = r0.value;
                } else {
                  s = r0 as Server;
                }
                final isCur = connected && identical(s, current);
                final standby = !isCur && uSet.contains(s);
                final spd = (s.speed ?? 0) > 0
                    ? '${s.speed!.toStringAsFixed(1)} MB/s'
                    : null;
                return uiCard(isCur: isCur, child: ListTile(
                  leading: UiCc(s.country, isCur),
                  title: Text('${favs.containsKey(s.key) ? '★ ' : ''}${s.host}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  subtitle: isCur
                      ? Text('متصل${spd == null ? '' : ' • $spd'}')
                      : standby
                          ? Text(
                              '${s.checkedAt == null ? 'ذخیره‌شده (هنوز تست نشده)' : 'سالم'}'
                              '${spd == null ? '' : ' • $spd'}')
                          : Text(s.personal
                              ? (personalMsg.isEmpty
                                  ? 'سرور شخصی'
                                  : personalMsg)
                              : 'تست نشده'),
                  trailing: UiMs(standby || isCur ? s.ping : null, isCur),
                  // tapping works even during a search: it interrupts it
                  onTap: isCur
                      ? null
                      : (s.personal
                          ? () => connectPersonal()
                          : () => connect(s, gid)),
                  onLongPress: () => _toggleFav(s),
                ));
              },
            ),
          ),
          ValueListenableBuilder<String>(
            valueListenable: errorLog,
            builder: (_, v, __) => v.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(v,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: Color(0xFFFF8A80), fontSize: 12)),
                  ),
          ),
        ],
      ),
    ));
  }
}


// UITHEMEPATCH ---- appearance only, no logic ----
const Color _uiGold = Color(0xFFD9AE55);
const Color _uiBg = Color(0xFF1F2328);
const Color _uiBar = Color(0xFF0F233E);
const Color _uiCard = Color(0xFF2A2D33);
const Color _uiText = Color(0xFFF2F0EB);
const Color _uiSub = Color(0xFFCDD1D8);

ThemeData uiTheme() {
  final cs = ColorScheme.fromSeed(
          seedColor: _uiGold, brightness: Brightness.dark)
      .copyWith(
          primary: _uiGold,
          onPrimary: Colors.black,
          secondary: _uiGold,
          onSecondary: Colors.black,
          surface: _uiCard,
          onSurface: _uiText,
          onSurfaceVariant: _uiSub,
          surfaceContainerHighest: const Color(0xFF34373E),
          surfaceContainerHigh: const Color(0xFF34373E),
          surfaceContainer: _uiCard,
          surfaceContainerLow: _uiCard,
          secondaryContainer: const Color(0xFF3A3F47),
          onSecondaryContainer: _uiText);
  final base = ThemeData(
      brightness: Brightness.dark, useMaterial3: true, colorScheme: cs);
  return base.copyWith(
    scaffoldBackgroundColor: _uiBg,
    canvasColor: _uiBg,
    cardColor: _uiCard,
    textTheme: base.textTheme.apply(bodyColor: _uiText, displayColor: _uiText),
    iconTheme: const IconThemeData(color: _uiGold),
    appBarTheme: const AppBarTheme(
        backgroundColor: _uiBar,
        foregroundColor: _uiGold,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false),
    listTileTheme: const ListTileThemeData(
        textColor: _uiText,
        iconColor: _uiGold,
        subtitleTextStyle: TextStyle(color: _uiSub, fontSize: 13)),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: _uiCard,
      disabledColor: _uiCard,
      selectedColor: _uiGold,
      showCheckmark: false,
      labelStyle: const TextStyle(color: _uiText),
      secondaryLabelStyle:
          const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
      shape: const StadiumBorder(side: BorderSide(color: Color(0x66D9AE55))),
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            backgroundColor: _uiGold, foregroundColor: Colors.black)),
    textButtonTheme:
        TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: _uiGold)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(foregroundColor: _uiGold)),
    popupMenuTheme: const PopupMenuThemeData(
        color: _uiCard, textStyle: TextStyle(color: _uiText)),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: _uiCard),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: _uiGold),
    dividerColor: const Color(0x44D9AE55),
    dividerTheme: const DividerThemeData(color: Color(0x44D9AE55)),
    inputDecorationTheme: const InputDecorationTheme(
        labelStyle: TextStyle(color: _uiSub),
        hintStyle: TextStyle(color: _uiSub),
        helperStyle: TextStyle(color: _uiSub),
        enabledBorder:
            UnderlineInputBorder(borderSide: BorderSide(color: Color(0x88D9AE55))),
        focusedBorder:
            UnderlineInputBorder(borderSide: BorderSide(color: _uiGold))),
    textSelectionTheme: const TextSelectionThemeData(
        cursorColor: _uiGold, selectionHandleColor: _uiGold),
    switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? _uiGold : _uiSub),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? const Color(0x66D9AE55)
                : const Color(0xFF3A3F47))),
    checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? _uiGold : null),
        checkColor: const WidgetStatePropertyAll(Colors.black),
        side: const BorderSide(color: _uiSub, width: 1.5)),
    snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF3A3F47),
        contentTextStyle: TextStyle(color: _uiText, fontSize: 14)),
  );
}

Widget uiCard({required bool isCur, required Widget child}) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: _uiCard,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: isCur ? _uiGold : const Color(0x77D9AE55),
              width: isCur ? 1.4 : 1),
        ),
        child: child,
      ),
    );

// keeps the top part alive while the list scrolls
class UiKeep extends StatefulWidget {
  final Widget child;
  const UiKeep({super.key, required this.child});
  @override
  State<UiKeep> createState() => _UiKeepState();
}

class _UiKeepState extends State<UiKeep> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class UiTool {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const UiTool(this.icon, this.label, this.onTap);
}

class UiTools extends StatelessWidget {
  final List<UiTool> items;
  const UiTools({super.key, required this.items});

  Widget _tile(UiTool t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: _uiCard,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0x77D9AE55))),
          child: InkWell(
            onTap: t.onTap,
            child: SizedBox(
              height: 84,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(t.icon, color: _uiGold, size: 26),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(t.label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: _uiText)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 3) {
      final cells = <Widget>[];
      for (var j = i; j < i + 3; j++) {
        cells.add(Expanded(
            child: j < items.length ? _tile(items[j]) : const SizedBox.shrink()));
      }
      rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 8), child: Row(children: cells)));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Text('ابزارها',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: _uiGold)),
        ),
        ...rows,
      ]),
    );
  }
}

class UiStatus extends StatelessWidget {
  final String text;
  final bool on;
  const UiStatus({super.key, required this.text, required this.on});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: _uiCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? _uiGold : const Color(0x88D9AE55))),
        child: Row(children: [
          Icon(on ? Icons.verified_user_outlined : Icons.shield_outlined,
              color: _uiGold, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: _uiText)),
          ),
        ]),
      );
}

class UiNavItem {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const UiNavItem(this.icon, this.label, this.onTap);
}

class UiNav extends StatelessWidget {
  final List<UiNavItem> items;
  const UiNav({super.key, required this.items});
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
            color: _uiBar,
            border: Border(top: BorderSide(color: Color(0x66D9AE55)))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(children: [
              for (final it in items)
                Expanded(
                  child: InkWell(
                    onTap: it.onTap,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(it.icon,
                            size: 26,
                            color: it.onTap == null ? _uiSub : const Color(0xFFF0C766)),
                        const SizedBox(height: 3),
                        Text(it.label,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFFF3D6))),
                      ],
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
}

String _uiFa(String t) {
  const en = '0123456789';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final c in t.split('')) {
    final i = en.indexOf(c);
    b.write(i >= 0 ? fa[i] : c);
  }
  return b.toString();
}

const String _uiChannelUrl = 'https://t.me/kingvpnn57';
const String _uiAdminUrl = 'https://t.me/Kingg_vpnn';
const String _uiAdminTg = 'tg://resolve?domain=Kingg_vpnn';

// contact the admin: opens the Telegram chat directly
Future<void> _uiOpenAdmin(BuildContext ctx) async {
  for (final u in [_uiAdminTg, _uiAdminUrl]) {
    try {
      if (await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_swE) { _swl('_uiOpenAdmin#1', _swE);}
  }
  await Clipboard.setData(const ClipboardData(text: '@Kingg_vpnn'));
  if (ctx.mounted) {
    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('تلگرام باز نشد؛ آیدی @Kingg_vpnn کپی شد.')));
  }
}
bool _uiJoinShown = false;

Future<void> _uiOpenChannel(BuildContext ctx) async {
  try {
    if (await launchUrl(Uri.parse(_uiChannelUrl),
        mode: LaunchMode.externalApplication)) {
      return;
    }
  } catch (_swE) { _swl('_uiOpenChannel#1', _swE);}
  await Clipboard.setData(const ClipboardData(text: _uiChannelUrl));
  if (ctx.mounted) {
    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('باز نشد؛ لینک کپی شد. در تلگرام Paste کن.')));
  }
}

// shown once per app launch, right after the VPN connects
void uiJoinPrompt(BuildContext context) {
  if (_uiJoinShown) return;
  _uiJoinShown = true;
  Future.delayed(const Duration(milliseconds: 800), () {
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: _uiCard,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: Color(0x88D9AE55))),
          title: const Row(children: [
            Icon(Icons.send_rounded, color: _uiGold, size: 26),
            SizedBox(width: 10),
            Expanded(
                child: Text('کانال تلگرام ما',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: _uiGold))),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'برای اتصال بهتر و دریافت آپدیت‌های بعدی به کانال تلگرام ما بپیوندید.',
                style: TextStyle(fontSize: 15, height: 1.7, color: _uiText)),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _uiOpenChannel(ctx),
              child: const Text(_uiChannelUrl,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontSize: 14,
                      color: _uiGold,
                      decoration: TextDecoration.underline)),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('بعداً')),
            FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _uiOpenChannel(context);
                },
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('ورود به کانال')),
          ],
        ),
      ),
    );
  });
}

class UiCc extends StatelessWidget {
  final String? cc;
  final bool cur;
  const UiCc(this.cc, this.cur, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: cur ? _uiGold : const Color(0x88D9AE55),
                width: cur ? 1.6 : 1)),
        child: Text((cc == null || cc!.isEmpty) ? '--' : cc!.toUpperCase(),
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cur ? _uiGold : _uiText)),
      );
}

class UiMs extends StatelessWidget {
  final int? ms;
  final bool cur;
  const UiMs(this.ms, this.cur, {super.key});
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(ms == null ? '-' : _uiFa('$ms'),
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cur ? _uiGold : _uiText)),
          const Text('ms', style: TextStyle(fontSize: 13, color: _uiSub)),
        ],
      );
}

class UiHero extends StatelessWidget {
  final bool on;
  final bool busy;
  final String label;
  final String ping;
  final String speed;
  final VoidCallback? onTap;
  const UiHero(
      {super.key,
      required this.on,
      required this.busy,
      required this.label,
      required this.ping,
      required this.speed,
      required this.onTap});

  Widget _side(IconData ic, Widget v, String cap) => Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(ic, color: _uiGold, size: 26),
          const SizedBox(height: 8),
          v,
          const SizedBox(height: 2),
          Text(cap, style: const TextStyle(fontSize: 13, color: _uiSub)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final big = on ? 'متصل' : (busy ? 'در حال کار' : 'غیرمتصل');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(children: [
        _side(
            Icons.network_check,
            Text(_uiFa(ping),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: _uiGold)),
            'پینگ (ms)'),
        GestureDetector(
          onTap: onTap,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF352919),
                border: Border.all(
                    color: on ? _uiGold : const Color(0x88D9AE55), width: 4),
                boxShadow: on
                    ? const [BoxShadow(color: Color(0x77D9AE55), blurRadius: 24)]
                    : null,
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(big,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _uiGold)),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(fontSize: 13, color: _uiSub)),
              ]),
            ),
            if (busy)
              const SizedBox(
                  width: 160,
                  height: 160,
                  child: CircularProgressIndicator(
                      strokeWidth: 3, color: _uiGold)),
          ]),
        ),
        _side(
            Icons.speed,
            Text(_uiFa(speed),
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _uiGold)),
            'MB/s'),
      ]),
    );
  }
}


class OpenVPN {
  final Function? onVpnStageChanged;
  final Function? onVpnStatusChanged;
  OpenVPN({this.onVpnStageChanged, this.onVpnStatusChanged});
  Future<void> initialize({String? localizedDescription}) async {}
  Future<void> connect(String config, String name,
      {String? username,
      String? password,
      List<String>? bypassPackages,
      bool certIsRequired = false}) async {
    // OpenVPN engine was intentionally removed. Fail cleanly so the UI
    // shows a clear message instead of a red PlatformException / stack.
    try {
      onVpnStageChanged?.call('error', 'OpenVPN removed');
    } catch (_) {}
  }
  Future<void> disconnect() async {}
}

final List<String> _morePaths = [
  'MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/super-sub.txt',
  for (var i = 1; i <= 4; i++)
    'MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub$i.txt',
  'Epodonios/v2ray-configs/main/Splitted-By-Protocol/vless.txt',
  'Epodonios/v2ray-configs/main/Splitted-By-Protocol/vmess.txt',
  'ebrasha/free-v2ray-public-list/refs/heads/main/ss_configs.txt',
  // NEW sources (dead links are skipped automatically)
  for (final p in ['trojan', 'ss'])
    'barry-far/V2ray-Config/main/Splitted-By-Protocol/$p.txt',
  for (final p in ['trojan', 'ss'])
    'Epodonios/v2ray-configs/main/Splitted-By-Protocol/$p.txt',
  for (final p in ['vless', 'vmess', 'trojan'])
    'ebrasha/free-v2ray-public-list/main/${p}_configs.txt',
  'mahdibland/V2RayAggregator/master/sub/sub_merge_base64.txt',
  'mahdibland/V2RayAggregator/master/Eternity.txt',
  'Pawdroid/Free-servers/main/sub',
  'ermaozi/get_subscribe/main/subscribe/v2ray.txt',
  'aiboboxx/v2rayfree/main/v2',
  'freefq/free/master/v2',
  'mfuu/v2ray/master/v2ray',
  'ripaojiedian/freenode/main/sub',
  'vpei/Free-Node-Merge/main/o/node.txt',
  'w1770946466/Auto_proxy/main/Long_term_subscription_num',
  'liketolivefree/kobabi/main/sub.txt',
  'Everyday-VPN/Everyday-VPN/main/subscription/main.txt',
  'free18/v2ray/main/v2ray.txt',
  'tbbatbb/Proxy/master/dist/v2ray.config.txt',
  'ts-sf/fly/main/v2',
  'Jsnzkpg/Jsnzkpg/Jsnzkpg/Jsnzkpg',
  'HosseinKoofi/GO_V2rayCollector/main/mixed_iran.txt',
  'ALIILAPRO/v2rayNG-Config/main/server.txt',
  'soroushmirzaei/telegram-configs-collector/main/protocols/vless',
  'soroushmirzaei/telegram-configs-collector/main/protocols/vmess',
  'soroushmirzaei/telegram-configs-collector/main/protocols/trojan',
  // Iran-exit / intranet servers (used first in national-network mode)
  'mmbateni/iran-intranet-access/main/outputs/ir_exit_configs.txt',
  'mmbateni/iran-intranet-access/main/outputs/ir_reality_configs.txt',
  'mmbateni/iran-intranet-access/main/outputs/ir_mobile_exit_configs.txt',
  'mmbateni/iran-intranet-access/main/outputs/armenian_bridge_configs.txt',
  'mmbateni/iran-intranet-access/main/outputs/passing_intranet_configs.txt',
  // ---- NEW 2026 sources (fresh + Iran-oriented) ----
  'Alirewa/V2ray-Configs/main/config.txt',
  'Alirewa/V2ray-Configs/main/sub1.txt',
  'Alirewa/V2ray-Configs/main/sub2.txt',
  '0xRadikal/Free-v2ray-Configs/main/top100.txt',
  '0xRadikal/Free-v2ray-Configs/main/verified/configs.txt',
  '0xRadikal/Free-v2ray-Configs/main/fast/configs.txt',
  // ایران / ایرانسل‌محور (برای فیلتر و نت ملی بهتر از لیست عمومی خام)
  'ZendanTeam/SS44-sub/main/SS44-gold.txt',
  'ZendanTeam/SS44-sub/main/SS44.txt',
  'miladtahanian/Config-Collector/main/mixed_iran.txt',
  'morpheusadam/v2ray-config/main/subs/bundles/iran.txt',
  'morpheusadam/v2ray-config/main/subs/bundles/best.txt',
  'Delta-Kronecker/V2ray-Config/main/config/protocols/trojan.txt',
  'Delta-Kronecker/V2ray-Config/main/config/protocols/ss.txt',
];

final List<String> _extraUrls = [
  // Telegram public channels (web preview page)
  for (final c in [
    'v2ray_configs_pool',
    'V2rayNG3',
    'PrivateVPNs',
    'DirectVPN',
    'mypremium98',
    'Free_HTTPCustom',
    'vmessorg',
    'v2rayng_org',
    'ConfigsHUB',
    'v2ray_free_conf',
    'Configforvpn01',
    'msv2ray',
    'v2box_free',
    'soonteam',
    'FreakConfig',
    'free2config',
    'vip_fragment_v2ray',
  ])
    'https://t.me/s/$c',
  // full links (dead ones are skipped)
  'https://raw.githubusercontent.com/awesome-vpn/awesome-vpn/master/all',
  'https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/refs/heads/main/config/protocols/vmess.txt',
  'https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/refs/heads/main/config/protocols/vless.txt',
  'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/all_extracted_configs.txt',
  'https://raw.githubusercontent.com/3inker/v2ray-subscription/main/subs/all_not_ru.txt',
  'https://raw.githubusercontent.com/free-nodes/v2rayfree/main/sub',
  'https://raw.githubusercontent.com/Au1rxx/free-vpn-subscriptions/main/output/v2ray-base64.txt',
  // Iran-focused full URLs
  'https://raw.githubusercontent.com/ZendanTeam/SS44-sub/main/SS44-gold.txt',
  'https://raw.githubusercontent.com/liketolivefree/kobabi/main/sub.txt',
];


// RESETALL ================================================================
extension ResetAllExt on _HomePageState {
  Future<void> resetAllServers() async {
    await _haltAll(); // stop a running search
    final cur = current;
    good.clear();
    warmKeys.clear();
    pending = [];
    bgAlive = [];
    failed.clear();
    fetchedAll = [];
    listTime = null;
    lastFetchTry = DateTime.fromMillisecondsSinceEpoch(0);
    srcTested.clear();
    srcOkN.clear();
    srcRate.clear();
    totalTested = 0;
    totalOk = 0;
    batchNo = 0;
    dTcp = 0;
    dFake = 0;
    fastTested = 0;
    fastOk = 0;
    aiFastOn = true;
    aiTried = 0;
    aiHit = 0;
    // Full wipe of national folder / learned variants too (user asked "از نو")
    natGood.clear();
    natVar.clear();
    _resMap.clear();
    _natCursor.clear();
    // the connection that is running right now stays
    if (connected && cur != null) good.add(cur);
    try {
      final p = await SharedPreferences.getInstance();
      for (final k in [
        'cache', 'failed2', 'list_cache', 'list_time',
        'nat_var', 'nat_wins', 'nat_res', 'nat_good',
      ]) {
        await p.remove(k);
      }
    } catch (e) {
      logError(e);
    }
    _set('🗑 همه‌ی سرورهای پیداشده + پوشه + لیست سیاه پاک شد • «اتصال» را بزن تا از نو جستجو کند');
  }
}

// SPEEDSWITCHPATCH

// QUIETPATCH

// RETRYPATCH


// ADPAGE ---- in-app ad page shown before connecting ----
const String _adUrl = 'https://motionless-bus.com/bteyn5';
List<String> _adUrls = [_adUrl];
String _adFallbackUrl = _adUrl;
int _adSeconds = 10;
const int _adWebTries = 2;
const bool _adEveryConnect = true;
const Color _adBg = Color(0xFF1A1710);
const Color _adGold = Color(0xFFE0B656);
const String _adUA =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

enum _AdMode { web, browser }

// true = the ad was really watched => connect. false = cancelled.
Future<bool> showAdPage(BuildContext context) async {
  final r = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true, builder: (_) => const AdPage()));
  return r == true;
}

class AdPage extends StatefulWidget {
  const AdPage({super.key});
  @override
  State<AdPage> createState() => _AdPageState();
}

class _AdPageState extends State<AdPage> with WidgetsBindingObserver {
  late final WebViewController _c;
  Timer? _count;
  Timer? _loadTimeout;
  _AdMode _mode = _AdMode.web;
  int _vid = 0;
  int _left = _adSeconds;
  int _tries = 0;
  int _urlIx = 0;
  bool _loaded = false;
  bool _clicked = false;
  bool _external = false;
  String _pageHost = '';
  DateTime? _extStart;
  String? _msg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_adBg)
      ..setUserAgent(_adUA)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (_mode == _AdMode.web && !_loaded) _verify();
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true) _onFail();
        },
        onNavigationRequest: (req) {
          if (!_loaded || !req.isMainFrame) return NavigationDecision.navigate;
          final u = Uri.tryParse(req.url);
          if (u == null || u.host.isEmpty || u.host == _pageHost) {
            return NavigationDecision.navigate;
          }
          _onClick(req.url);
          return NavigationDecision.prevent;
        },
      ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _count?.cancel();
    _loadTimeout?.cancel();
    _vid++;
    super.dispose();
  }

  void _load() {
    _count?.cancel();
    _loadTimeout?.cancel();
    _vid++;
    setState(() {
      _loaded = false;
      _left = _adSeconds;
      _msg = null;
    });
    _loadTimeout = Timer(const Duration(seconds: 20), () {
      if (!_loaded) _onFail();
    });
    final cur = _adUrls[_urlIx % _adUrls.length];
    if (cur.startsWith('<')) {
      _c.loadHtmlString(cur);
    } else {
      _c.loadRequest(Uri.parse(cur));
    }
  }

  // true when the page really shows something (text, image, frame, video...)
  Future<bool> _hasContent() async {
    try {
      final r = await _c.runJavaScriptReturningResult(
          "(function(){var b=document.body;if(!b)return 0;"
          "var n=(b.innerText||'').trim().length;"
          "n+=b.querySelectorAll('img,iframe,video,canvas,svg').length*100;"
          "return n;})()");
      final n = double.tryParse(r.toString().replaceAll('"', '')) ?? 1;
      return n > 0;
    } catch (_) {
      return true;
    }
  }

  // after a page finished loading: wait up to ~7 s for real content. Only
  // then the dark cover is removed and the countdown starts.
  Future<void> _verify() async {
    final id = ++_vid;
    for (var i = 0; i < 5; i++) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted || id != _vid || _loaded || _mode != _AdMode.web) return;
      if (await _hasContent()) {
        if (!mounted || id != _vid || _loaded) return;
        try {
          final cu = await _c.currentUrl();
          _pageHost = Uri.tryParse(cu ?? '')?.host ?? '';
        } catch (_) {}
        _onLoaded();
        return;
      }
    }
    if (mounted && id == _vid && !_loaded) _onFail();
  }

  void _onLoaded() {
    if (_loaded || !mounted) return;
    _loadTimeout?.cancel();
    setState(() => _loaded = true);
    _count = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_left <= 1) {
        t.cancel();
        setState(() => _left = 0);
      } else {
        setState(() => _left--);
      }
    });
  }

  // blank / failed / timed out: next link, then browser mode
  void _onFail() {
    if (!mounted || _loaded || _mode != _AdMode.web) return;
    _loadTimeout?.cancel();
    _vid++;
    _tries++;
    if (_tries >= _adWebTries) {
      setState(() => _mode = _AdMode.browser);
      return;
    }
    _urlIx++;
    _load();
  }

  // tapping the ad: the target opens in the browser, but the connection does
  // NOT start; the user comes back and must finish the countdown
  Future<void> _onClick(String url) async {
    if (_clicked) return;
    _clicked = true;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
    Future.delayed(const Duration(seconds: 3), () => _clicked = false);
  }

  // browser mode: real Chrome tab (not a WebView)
  Future<void> _openInBrowser() async {
    setState(() => _msg = null);
    _extStart = DateTime.now();
    _external = true;
    final raw = _adUrls[_urlIx % _adUrls.length];
    final uri = Uri.parse(raw.startsWith('<') ? _adFallbackUrl : raw);
    try {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        _external = false;
        if (mounted) setState(() => _msg = 'مرورگر باز نشد، دوباره تلاش کن');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_external || !mounted) return;
    _external = false;
    final el = DateTime.now().difference(_extStart ?? DateTime.now()).inSeconds;
    if (el >= _adSeconds) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _msg =
          'تبلیغ را کامل ندیدی. باید حداقل $_adSeconds ثانیه تبلیغ را ببینی؛ دوباره بزن.');
    }
  }

  Future<void> _exit() async {
    if (_mode == _AdMode.web && _loaded && _left == 0) {
      Navigator.of(context).pop(true);
      return;
    }
    final cancel = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تبلیغ هنوز تمام نشده'),
          content: const Text(
              'برای برقراری اتصال حتماً باید تبلیغ را تا آخر ببینید.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('انصراف از اتصال')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ادامه تبلیغ')),
          ],
        ),
      ),
    );
    if (cancel == true && mounted) Navigator.of(context).pop(false);
  }

  Widget _cover(Widget child) => Container(
      color: _adBg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: child);

  Widget _body() {
    if (_mode == _AdMode.browser) {
      return _cover(Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.open_in_browser, color: _adGold, size: 42),
        const SizedBox(height: 12),
        Text(
            'برای ادامه، تبلیغ را در مرورگر ببین (حداقل $_adSeconds ثانیه) '
            'و بعد به برنامه برگرد.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        if (_msg != null) ...[
          const SizedBox(height: 12),
          Text(_msg!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: 16),
        FilledButton(
            onPressed: _openInBrowser, child: const Text('مشاهده تبلیغ')),
      ]));
    }
    return Stack(children: [
      WebViewWidget(controller: _c),
      if (!_loaded)
        Positioned.fill(
          child: _cover(Column(mainAxisSize: MainAxisSize.min, children: const [
            CircularProgressIndicator(color: _adGold),
            SizedBox(height: 16),
            Text('در حال آماده‌سازی تبلیغ...',
                style: TextStyle(color: Colors.white70)),
          ])),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final done = _mode == _AdMode.web && _loaded && _left == 0;
    final title = _mode == _AdMode.browser
        ? 'مشاهده تبلیغ در مرورگر'
        : (done
            ? 'تبلیغ تمام شد'
            : (_loaded ? 'تبلیغ • $_left ثانیه' : 'در حال بارگذاری تبلیغ...'));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Column(children: [
              Container(
                color: _adBg,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            color: _adGold, fontWeight: FontWeight.bold)),
                  ),
                  FilledButton.icon(
                    onPressed: _exit,
                    style: FilledButton.styleFrom(
                        backgroundColor:
                            done ? _adGold : const Color(0xFF403824),
                        foregroundColor:
                            done ? Colors.black : const Color(0xFFE2D8BF)),
                    icon: Icon(done ? Icons.check : Icons.lock_outline,
                        size: 18),
                    label: Text(done ? 'خروج و اتصال' : 'خروج'),
                  ),
                ]),
              ),
              if (_mode == _AdMode.web && _loaded && !done)
                LinearProgressIndicator(
                    value: 1 - _left / _adSeconds,
                    color: _adGold,
                    backgroundColor: const Color(0xFF2A251A)),
              Expanded(child: _body()),
            ]),
          ),
        ),
      ),
    );
  }
}

// NATIONALPATCH
bool nationalMode = false; // international internet cut, national network works
final Set<String> natGood = {}; // keys of servers that worked in national mode

// منابع مناسب فیلتر / نت ملی (ایران‌محور + تست‌شده)
bool _natSrc(Server s) {
  final u = (s.src ?? '').toLowerCase();
  if (u.isEmpty) return false;
  return u.contains('iran-intranet') ||
      u.contains('zendenteam') ||
      u.contains('ss44') ||
      u.contains('mixed_iran') ||
      u.contains('miladtahanian') ||
      u.contains('kobabi') ||
      u.contains('mahsanet') ||
      u.contains('hosseinkoofi') ||
      u.contains('mmbateni') ||
      (u.contains('morpheusadam') && u.contains('iran')) ||
      u.contains('delta-kronecker');
}

// رتبه نت ملی: برندگان قبلی > منبع ایران‌محور > Reality > IR > CDN
int _natRank(Server s) {
  if (natGood.contains(s.key)) return 5;
  if (_natSrc(s)) return 4;
  if (s.reality) return 3;
  if (s.country == 'IR') return 2;
  if (s.cdn) return 1;
  return 0;
}

Future<void> _natAdd(Server s) async {
  natGood.add(s.key); // FOLDERONLY: the folder keeps them, no file
}

// NATBTNPATCH
bool natRefetch = false; // NATESCALATE: download the lists again even in national mode
bool natForce = false; // the national-network button was tapped
bool natAll = false; // button session: search ALL sources, skip none

// NATWORKERSPATCH
int natWorkers = 4; // locked parallel tests in national mode

// NATRESPATCH
class _NatResItem {
  final String link;
  final Server s;
  final DateTime added;
  DateTime? checked;
  int miss = 0;
  _NatResItem(this.link, this.s, this.added);
}
