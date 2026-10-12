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
part 'iran_ai_extras.dart';
part 'npv_am_extras.dart';
part 'nat_ultra.dart';
part 'net_diag.dart';
part 'extras_plus.dart';
part 'donate.dart';
part 'ads_remote.dart';
part 'online.dart';
part 'server_shop.dart';

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
int bgWorkers = 1; // RETRYPATCH
// FAST SEARCH: parallel ping tests (core delay test, no VPN toggling) used
// when looking for the first healthy server (settings 1..8).
int fastWorkers = 50; // FASTSET: 50 parallel tests (fixed default)
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
};
// below this download speed (KB/s) the connected server is replaced (0 = off)
int minSpeedKB = 0; // LOWDATA: speed-based switching off (no download tests)

// ---- settings ----
// user-adjustable (saved in settings)
int batchSize = 500; // servers tested per batch (fixed 500)
int delayWorkers = 20; // (kept for settings compatibility)
Duration delayTimeout = const Duration(seconds: 6);
int goodWant = 3; // (kept for settings compatibility, not used any more)
bool autoSpeed = false; // LOWDATA // speed-test the best few servers before connecting
int speedTopN = 1; // LOWDATA // how many top servers are speed-tested before connecting
bool autoUpgrade = false; // LOWDATA // keep searching for new servers while connected
// real pings below this are fake -> server counts as bad / hidden.
// 0 = off: the real speed test decides (done right after connecting).
int minPingMs = 0;
// connected server has a terrible ping -> jump at once to the best-ping server
bool badPingSwitch = false; // LOWDATA
int badPingMs = 3000;
// the healthy servers of the last session are tested first
bool savedFirst = true;
// learn what works on this network (protocol / transport / port / source) and
// test the most likely servers first; skip lists that never give a server
bool smartOrder = true;
// when every server was tested: download a new list and go on, forever
bool autoCycle = false; // LOWDATA: no endless list re-downloads
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
int firstBatchSize = 50; // small first batch: the first test starts sooner
int fetchWorkers = 4;
Duration fetchDeadline = const Duration(seconds: 20);
int tcpWorkers = 50;
int maxPerSource = 100;
Duration tcpTimeout = const Duration(milliseconds: 3000);
// TLS handshakes in the prefilter leaked sockets (crash, instant failures)
const probeTls = false;
const speedUrl = 'https://speed.cloudflare.com/__down?bytes=10000000';
const smallSpeedUrl = 'https://speed.cloudflare.com/__down?bytes=1000000';
const httpProxyPort = 10809;
// anti-flapping / watchdog
// A dead / broken server is replaced right away: 2 failed checks (~10 s),
// no waiting for the 10 minute speed-trial timer.
Duration watchEvery = const Duration(seconds: 60);
int watchFailLimit = 3; // consecutive failed checks before switching
int badPingLimit = 3; // consecutive bad pings (~10 s) before a ping switch
const minHold = Duration(seconds: 5); // min time between two switches
// FASTPATCH ----------------------------------------------------
int fastPickN = 4; // healthy servers collected before choosing
int fastPickMs = 3500; // never wait longer than this once one works
bool betterSwitch = true; // swap to a clearly better standby server
const betterGain = 0.8; // ping must be <= 80% of the connected one
const betterMinGapMs = 30; // ...and at least this many ms lower
const betterEvery = Duration(minutes: 4); // min gap between swaps (was 90 s)
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
const upgradeGain = 1.1; // replacement must be 10% faster (real speed)
const manualSpeedMax = 1000; // no real limit: all healthy servers are tested
const speedBatch = 1; // servers speed-tested per trial
const speedFresh = Duration(minutes: 15); // older than this -> test again
const delayTestUrl = 'https://www.gstatic.com/generate_204';
// internet check through the tunnel: the plain-http URL goes first (fewer
// round trips, so slow servers also pass), then the https ones
const _pingUrls = [
  'http://cp.cloudflare.com/generate_204',
  delayTestUrl,
  'https://www.google.com/generate_204',
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
    batchSize = 500;
    minSpeedKB = 0;
    badPingMs = 5000;
    badPingLimit = 3;
    watchFailLimit = 4;
  } else if (lv == 2) {
    // fast network: more parallel tests, strict about slow servers
    // fastWorkers stays 50 (FASTSET)
    bgWorkers = 1;
    delayTimeout = const Duration(seconds: 5);
    batchSize = 500;
    minSpeedKB = 0;
    badPingMs = 3000;
    badPingLimit = 3;
    watchFailLimit = 3;
  } else {
    // normal = the app's own defaults
    // fastWorkers stays 50 (FASTSET)
    bgWorkers = 1;
    delayTimeout = const Duration(seconds: 6);
    batchSize = 500;
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
int dbgNet = 0; // harmless network errors (counted, not listed)
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
    'ناموفق', 'نشد', 'نیامد', 'خطا', 'شکست', 'خراب', 'گیر',
    'Exception', 'xception', 'imeout', 'timeout', 'Error', 'error', 'failed'
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
List<String>? _dbgHelpOf(String m) {
  List<String> h(String c, String w, String a, String f) => [c, w, a, f];
  bool has(String k) => m.contains(k);
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
        'اگر تکرار می‌شود sort و jsonEncode در _saveList / _loadPending را با compute() به isolate ببر و _saveSoon را کندتر کن (jsonEncode داخل _saveCache از قبل در isolate است).');
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
        'هشدار فقط وقتی searching خاموش است؛ و داخل _runBusy برای f یک .timeout(Duration(minutes: 5)) بگذار تا busy همیشه آزاد شود.');
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
        'خودکار اصلاح می‌شود (patch_selfheal.py → _syncCore: ۳ ثانیه بعد از هر تعویض و در هر تیک واچ‌داگ؛ connected=true و _startWatch). اگر عدد «بار» خیلی بالاست، ریشه‌اش رویداد گمشده‌ی هسته در حین busy/switching است؛ متن و ساعت‌ها را برای Claude بفرست.');
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
          'سروری که کانفیگش خراب است رد شود؛ اگر برای همه رخ می‌دهد منبع لیست را چک کن. محل دقیق را برای Claude بفرست.');
    }
    if (has('PlatformException') || has('MissingPluginException')) {
      return h('E-ERR-PLATFORM',
          'محل ثبت: بعد از «@» همین خط',
          'خطای بخش native (هسته v2ray، OpenVPN یا کانال vpn/bg).',
          'متن خطا و محل را برای Claude بفرست؛ معمولاً به نسخه‌ی پلاگین یا مجوز اندروید مربوط است.');
    }
    if (has('NoSuchMethodError') ||
        has('RangeError') ||
        has('type ') ||
        has('Null check')) {
      return h('E-ERR-BUG',
          'محل ثبت: بعد از «@» همین خط (تابع:شماره‌ی خط در main.dart پیوست Release)',
          'باگ کد (مقدار null، اندیس بیرون از لیست یا نوع اشتباه).',
          'تابع و خط بعد از «@» را برای Claude بفرست تا شرط null/اندیس درست شود.');
    }
    return h('E-ERR-OTHER',
        'محل ثبت: بعد از «@» همین خط (تابع:شماره‌ی خط در main.dart پیوست Release)',
        'استثنای غیرمنتظره در یکی از try/catch ها.',
        'نوع خطا + محل را برای Claude بفرست.');
  }
  return null;
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
  b.write('شماره‌ی خط‌ها: main.dart پیوست همین Release\n');
  if (l.isEmpty) b.write('هیچ مشکلی ثبت نشده\n');
  final shown = <String>{};
  var i = 0;
  for (final p in l) {
    i++;
    b.write('$i) ${p.msg} • اولین ${_dbgStamp(p.first)} • '
        'آخرین ${_dbgStamp(p.last)} • ${p.n} بار\n');
    final h = _dbgHelpOf(p.msg);
    if (h == null) {
      b.write('   ❓ برای این مشکل هنوز راه حل ثبت نشده؛ کل گزارش را برای Claude بفرست\n');
    } else {
      b.write('   کد: ${h[0]}\n');
      if (shown.add(h[0])) {
        b.write('   📍 کجا: ${h[1]}\n');
        b.write('   🔎 علت: ${h[2]}\n');
        b.write('   🛠 راه حل: ${h[3]}\n');
      } else {
        b.write('   (کجا / علت / راه حل همین کد بالاتر آمده)\n');
      }
    }
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

void logError(Object e) {
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
};
const countryWords = {
  'germany': 'DE', 'united states': 'US', 'netherlands': 'NL',
  'france': 'FR', 'finland': 'FI', 'united kingdom': 'GB', 'singapore': 'SG',
  'japan': 'JP', 'turkey': 'TR', 'canada': 'CA', 'sweden': 'SE',
  'hong kong': 'HK', 'russia': 'RU', 'poland': 'PL',
};

String flagOf(String c) =>
    String.fromCharCodes(c.codeUnits.map((u) => u - 65 + 0x1F1E6));

// country from the config name: flag emoji, "DE |" prefix or a country word
String? detectCountry(String name) {
  final r = name.runes.toList();
  for (var i = 0; i + 1 < r.length; i++) {
    if (r[i] >= 0x1F1E6 &&
        r[i] <= 0x1F1FF &&
        r[i + 1] >= 0x1F1E6 &&
        r[i + 1] <= 0x1F1FF) {
      return String.fromCharCodes(
          [r[i] - 0x1F1E6 + 65, r[i + 1] - 0x1F1E6 + 65]);
    }
  }
  final m = RegExp(r'^\W*([A-Z]{2})\s*[|\-_:]').firstMatch(name);
  if (m != null && countryFa.containsKey(m.group(1))) return m.group(1);
  final l = name.toLowerCase();
  for (final e in countryWords.entries) {
    if (l.contains(e.key)) return e.value;
  }
  return null;
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
        final pm =
            RegExp(r'^\s*proto\s+(\w+)', multiLine: true).firstMatch(cfg);
        final sv = Server(link, nm.isEmpty ? rm.group(1)! : nm,
            rm.group(1)!, int.parse(rm.group(2)!));
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
        final sv = Server(link, j['ps']?.toString() ?? j['add'].toString(),
            j['add'].toString(), int.parse(j['port'].toString()));
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
  final it = items.iterator;
  // UI-FREEZE FIX: 50 workers used to start in the same millisecond (50 config
  // builds + 50 native calls on the UI thread). Starts are staggered and each
  // worker gives the UI a chance to draw a frame between two items.
  Future<void> worker(int idx) async {
    if (workers > 8) {
      await Future<void>.delayed(Duration(milliseconds: (idx % 25) * 12));
    }
    var n = 0;
    while (it.moveNext()) {
      try {
        await fn(it.current);
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

// direct = true: no local proxy port, the request goes through the VPN tunnel
// (in proxy mode there is no tunnel, so the local proxy port is used)
Future<double?> measure(
    {String url = speedUrl,
    Duration win = const Duration(milliseconds: 1500),
    Duration total = const Duration(seconds: 10),
    int maxBytes = 0,
    bool direct = false}) async {
  final c = HttpClient()
    ..findProxy = ((_) =>
        (direct && !proxyMode) ? 'DIRECT' : 'PROXY 127.0.0.1:$httpProxyPort')
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
Future<bool> _siteOpens(String url) async {
  final c = HttpClient()
    ..findProxy = ((_) =>
        !proxyMode ? 'DIRECT' : 'PROXY 127.0.0.1:$httpProxyPort')
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
      return n.startsWith('tun') || n.startsWith('ppp');
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
    String url = delayTestUrl}) async {
  final c = HttpClient()
    ..findProxy = ((_) =>
        (direct && !proxyMode) ? 'DIRECT' : 'PROXY 127.0.0.1:$httpProxyPort')
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
    int tries = 2}) async {
  for (final u in _pingUrls.take(tries)) {
    final p = await pingProxy(total: total, direct: direct, url: u);
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
      for (final l in lines.take(maxPerSource)) {
        final s = Server.parse(l);
        if (s != null) {
          s.src = u;
          all.putIfAbsent(s.key, () => s);
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

String? ownerOf(Server s) {
  final u = s.src;
  if (u == null) return null;
  if (!u.startsWith(_gh)) {
    final x = Uri.parse(u);
    if (x.host == 't.me' && x.pathSegments.length > 1) {
      return 't.me/${x.pathSegments[1]}';
    }
    return x.host;
  }
  return u.replaceFirst(_gh, '').split('/').first;
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
  if (l.toLowerCase().sta
