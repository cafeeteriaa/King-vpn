package com.kingvpn.king_vpn;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.VpnService;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.net.ConnectException;
import java.net.HttpURLConnection;
import java.net.InetSocketAddress;
import java.net.NoRouteToHostException;
import java.net.Proxy;
import java.net.SocketTimeoutException;
import java.net.URL;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

import dev.amirzr.flutter_v2ray_client.v2ray.core.V2rayCoreManager;
import dev.amirzr.flutter_v2ray_client.v2ray.interfaces.V2rayServicesListener;
import dev.amirzr.flutter_v2ray_client.v2ray.utils.V2rayConfig;

// KINGVPN: سرویس VPN خود برنامه.
// هسته (libv2ray) را از پلاگین استفاده می‌کند، اما چرخه‌ی سرویس VPN دست خودمان است.
//
// KINGFAILOVER: این سرویس حتی وقتی خود برنامه (Flutter) بسته شده باشد، سلامت
// سرور فعال را بررسی می‌کند (همان روش v2rayNG: درخواست HTTP 204 از داخل تونل).
// اگر سرور خراب شد یا هسته بالا نیامد، به سرور بعدی از لیست پشتیبان می‌رود.
// لیست پشتیبان از Dart با extra «backups» می‌آید و در SharedPreferences هم ذخیره
// می‌شود تا اگر اندروید سرویس را دوباره راه انداخت (START_STICKY) همان ادامه یابد.
//
// RELIABILITY-PASS (handoff Group A1/A2/A4 for the native layer — the Dart side
// already has rich scoring/backoff/self-healing; this service runs even when the
// Flutter isolate is dead, so it keeps its own small, independent copy):
//   A1 — exponential backoff: a flat 30s probe stays the same while things are
//        healthy, but if EVERY server in the list fails in one pass, the service no
//        longer gives up; it retries the whole list again after 2,4,8,16,32,60s
//        (capped), instead of calling stopEverything() the first time everyone fails.
//   A2 — failure classification: a probe that fails FAST with a clear "nobody is
//        listening" error (connection refused / no route to host) is treated as a
//        hard block and switches at once; a probe that only times out is treated as
//        a soft/ambiguous failure and still waits for FAILS_BEFORE_SWITCH in a row,
//        since that is more likely a transient network hiccup than a dead server.
//   A4 — success-weighted backup order: a tiny persisted win/loss score per
//        "addr:port" (same idea as the Dart side's _HealMemory) is kept across
//        service restarts. The PRIMARY server Dart chose (index 0) is never
//        reordered — Dart's own scoring already picked it deliberately — but the
//        backup list (index 1..n) is sorted so a backup with a better recent track
//        record is tried before one that has repeatedly failed.
// None of this changes behaviour unless kOwnVpnService = true (lib/own_vpn.dart),
// which is still off by default until tested on a real device.
public class KingVpnService extends VpnService implements V2rayServicesListener {

    private static final String TAG = "KingVpnService";
    public static final String ACTION_START = "com.kingvpn.king_vpn.VPN_START";
    public static final String ACTION_STOP = "com.kingvpn.king_vpn.VPN_STOP";
    public static final String EXTRA_CONFIG = "config";
    public static final String EXTRA_REMARK = "remark";
    public static final String EXTRA_ADDR = "addr";
    public static final String EXTRA_PORT = "port";
    // JSON array: [{"config":"...","remark":"...","addr":"...","port":"..."}, ...]
    public static final String EXTRA_BACKUPS = "backups";

    private static final int NOTIF_ID = 42;
    private static final String CHANNEL_ID = "king_vpn";
    private static final int MTU = 1500;

    // همان پورت HTTP هسته که در کانفیگ Dart ساخته می‌شود (httpProxyPort)
    private static final int LOCAL_HTTP_PORT = 10809;
    // همان آدرسی که v2rayNG برای تست «real ping» استفاده می‌کند
    private static final String CHECK_URL = "https://www.google.com/generate_204";
    private static final int CHECK_EVERY_SEC = 30;
    private static final int CHECK_TIMEOUT_MS = 8000;
    // چند بررسی ناموفق پشت‌سرهم قبل از تعویض سرور (شکست نرم/مبهم؛ شکست سخت فوری است)
    private static final int FAILS_BEFORE_SWITCH = 2;
    private static final int MAX_BACKUPS = 8;

    // BACKOFF (A1): وقتی کل لیست در یک دور شکست خورد، به‌جای توقف کامل، با این
    // فاصله‌ها دوباره کل لیست را امتحان می‌کن (سقف ۶۰ ثانیه). عدد آخر برای همیشه تکرار می‌شود.
    private static final int[] BACKOFF_SEC = {2, 4, 8, 16, 32, 60};

    // SCORE (A4): بازه‌ی امتیاز ماندگار هر سرور، تا در طول زمان بی‌نهایت رشد/افت نکند.
    private static final int SCORE_MIN = -20;
    private static final int SCORE_MAX = 20;
    // یک سرور فقط بعد از این‌همه بررسی سالم پشت‌سرهم امتیاز می‌گیرد (صرفاً بالا آمدن
    // کافی نیست؛ باید واقعاً مدتی پایدار مانده باشد).
    private static final int SCORE_WIN_AFTER_CHECKS = 2;

    private static final String PREFS = "king_vpn_state";
    private static final String SCORE_PREFS = "king_vpn_scores";

    private final Object lock = new Object();
    private final List<Srv> servers = new ArrayList<>();
    private ParcelFileDescriptor tun = null;
    private ScheduledExecutorService watchdog = null;
    private int currentIdx = 0;
    private int fails = 0;
    // BACKOFF: پشت‌سرهم چند دور کامل لیست شکست خورده (برای محاسبه‌ی تأخیر بعدی)
    private int listExhaustedStreak = 0;
    // SCORE: چند بررسی سالم پشت‌سرهم روی سرور فعال (برای اعطای امتیاز فقط بعد از پایداری)
    private int healthyStreak = 0;
    // true وقتی سرویس واقعاً وصل است (بین شروع موفق و توقف)
    private volatile boolean active = false;
    private volatile boolean stopping = false;
    // TEST-FIX: true only while a core (re)start is in progress. The core's own
    // stopService() callback fired by that restart must not kill the new service.
    private volatile boolean starting = false;
    // BACKOFF: true در فاصله‌ی انتظار بین دورهای کامل شکست (برای اینکه probe چرخه‌ی
    // عادی با این انتظار تداخل نکند)
    private volatile boolean retryWaiting = false;

    private static class Srv {
        final String config, remark, addr, port;

        Srv(String config, String remark, String addr, String port) {
            this.config = config;
            this.remark = remark;
            this.addr = addr;
            this.port = port;
        }

        String scoreKey() {
            return addr + ":" + port;
        }
    }

    // A2: نوع نتیجه‌ی یک بررسی سلامت.
    //   OK        — جواب سالم گرفت
    //   SOFT_FAIL — timeout یا خطای نامشخص؛ ممکن است موقتی باشد، با backoff رفتار شود
    //   HARD_FAIL — connection refused / no route؛ یعنی چیزی آن‌طرف گوش نمی‌دهد،
    //               به احتمال زیاد سرور خراب یا مسدود است؛ فوری تعویض کن
    private enum ProbeResult { OK, SOFT_FAIL, HARD_FAIL }

    @Override
    public void onCreate() {
        super.onCreate();
        V2rayCoreManager.getInstance().setUpListener(this);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) {
            // Android راه‌اندازی مجدد کرده (START_STICKY): از آخرین وضعیت ادامه بده
            return resumeSaved();
        }
        String action = intent.getAction();
        if (ACTION_STOP.equals(action)) {
            stopEverything();
            return START_NOT_STICKY;
        }
        if (!ACTION_START.equals(action)) {
            return START_NOT_STICKY;
        }

        String json = intent.getStringExtra(EXTRA_CONFIG);
        if (json == null || json.isEmpty()) {
            Log.e(TAG, "start without config");
            stopEverything();
            return START_NOT_STICKY;
        }

        Srv first = new Srv(
                json,
                orEmpty(intent.getStringExtra(EXTRA_REMARK)),
                orEmpty(intent.getStringExtra(EXTRA_ADDR)),
                orEmpty(intent.getStringExtra(EXTRA_PORT)));
        List<Srv> backups = parseBackups(intent.getStringExtra(EXTRA_BACKUPS));
        // A4: فقط لیست پشتیبان بر اساس امتیاز مرتب می‌شود؛ انتخاب اول (first) همان چیزی
        // است که Dart با منطق امتیازدهی خودش از قبل انتخاب کرده و دست نمی‌خورد.
        sortByScoreDesc(backups);

        startForegroundSafe(first.remark);
        synchronized (lock) {
            stopWatchdog();
            listExhaustedStreak = 0;
            healthyStreak = 0;
            servers.clear();
            servers.add(first);
            for (Srv b : backups) {
                if (servers.size() > MAX_BACKUPS) break;
                if (!b.config.equals(first.config)) servers.add(b);
            }
            if (connectFrom(0)) {
                saveState();
                startWatchdog(CHECK_EVERY_SEC);
            } else {
                Log.e(TAG, "no server could be started");
                stopEverything();
            }
        }
        return START_STICKY;
    }

    // بازیابی بعد از راه‌اندازی مجدد توسط اندروید
    private int resumeSaved() {
        synchronized (lock) {
            if (!loadState()) {
                stopSelf();
                return START_NOT_STICKY;
            }
            startForegroundSafe(servers.get(currentIdx).remark);
            if (connectFrom(currentIdx)) {
                saveState();
                startWatchdog(CHECK_EVERY_SEC);
                return START_STICKY;
            }
            stopEverything();
            return START_NOT_STICKY;
        }
    }

    // سرورهای servers را از همین اندیس به بعد امتحان می‌کند؛ اولین سالم انتخاب می‌شود
    private boolean connectFrom(int first) {
        int n = servers.size();
        for (int k = 0; k < n; k++) {
            int idx = (first + k) % n;
            Srv s = servers.get(idx);
            Log.i(TAG, "starting server " + idx + "/" + n + " " + s.remark);
            if (bringUp(s)) {
                currentIdx = idx;
                fails = 0;
                healthyStreak = 0;
                active = true;
                startForegroundSafe(s.remark);
                return true;
            }
            Log.w(TAG, "server failed to start: " + s.remark);
        }
        return false;
    }

    // یک سرور را بالا می‌آورد: TUN جدید + هسته
    private boolean bringUp(Srv s) {
        starting = true;
        try {
            V2rayConfig cfg = new V2rayConfig();
            cfg.V2RAY_FULL_JSON_CONFIG = s.config;
            cfg.REMARK = s.remark;
            cfg.CONNECTED_V2RAY_SERVER_ADDRESS = s.addr;
            cfg.CONNECTED_V2RAY_SERVER_PORT = s.port;
            cfg.APPLICATION_NAME = "King VPN";
            cfg.NOTIFICATION_DISCONNECT_BUTTON_NAME = "قطع";
            cfg.ENABLE_TRAFFIC_STATICS = true;

            V2rayCoreManager core = V2rayCoreManager.getInstance();
            core.setUpListener(this);
            if (core.isV2rayCoreRunning()) {
                core.stopCore();
            }

            // TEST-FIX: a previous TUN must be closed before a new one is opened
            closeTun();
            tun = establish(cfg);
            if (tun == null) {
                Log.e(TAG, "VPN interface not established (permission missing?)");
                return false;
            }

            boolean ok;
            try {
                ok = core.startCore(cfg, tun.getFd());
            } catch (Exception e) {
                Log.e(TAG, "startCore threw", e);
                ok = false;
            }
            if (!ok) {
                closeTun();
            }
            return ok;
        } finally {
            starting = false;
        }
    }

    // ---- نگهبان: هر CHECK_EVERY_SEC ثانیه سلامت سرور فعال ----
    // BACKOFF: دیگر scheduleWithFixedDelay نیست؛ هر دور خودش دور بعدی را با فاصله‌ی
    // لازم (عادی یا backoff) زمان‌بندی می‌کند تا فاصله‌ی بین تلاش‌ها بتواند تغییر کند.
    private void startWatchdog(int delaySec) {
        stopWatchdog();
        watchdog = Executors.newSingleThreadScheduledExecutor();
        watchdog.schedule(this::checkOnce, delaySec, TimeUnit.SECONDS);
    }

    // shutdown (نه shutdownNow) تا اگر از داخل خود نگهبان صدا زده شد، ترد خودش قطع نشود
    private void stopWatchdog() {
        if (watchdog != null) {
            watchdog.shutdown();
            watchdog = null;
        }
    }

    private void checkOnce() {
        synchronized (lock) {
            if (!active || stopping || starting) return;

            V2rayCoreManager core = V2rayCoreManager.getInstance();
            boolean coreUp = core.isV2rayCoreRunning();
            ProbeResult pr = coreUp ? probeResult() : ProbeResult.HARD_FAIL;

            if (pr == ProbeResult.OK) {
                fails = 0;
                listExhaustedStreak = 0; // یک سرور سالم یعنی لیست دیگر «همه خراب» نیست
                healthyStreak++;
                if (healthyStreak == SCORE_WIN_AFTER_CHECKS) {
                    bumpScore(servers.get(currentIdx), +1);
                }
                rescheduleNormal();
                return;
            }

            // A2: شکست سخت (کسی آن‌طرف گوش نمی‌دهد) فوری تعویض می‌کند؛ شکست نرم
            // (timeout/مبهم) طبق قبل چند بار صبر می‌کند، چون می‌تواند موقتی باشد.
            healthyStreak = 0;
            if (coreUp && pr == ProbeResult.SOFT_FAIL) {
                fails++;
                Log.w(TAG, "soft health-check failure (" + fails + "/" + FAILS_BEFORE_SWITCH + ")");
                if (fails < FAILS_BEFORE_SWITCH) {
                    rescheduleNormal();
                    return;
                }
            } else if (coreUp) {
                Log.w(TAG, "hard health-check failure (connection refused / no route); switching now");
            }

            // هسته مرده یا سرور فعلی مسدود/خراب تشخیص داده شد: سرور بعدی
            fails = 0;
            if (coreUp) bumpScore(servers.get(currentIdx), -2);
            if (servers.size() < 2) {
                // سرور پشتیبانی نیست؛ اگر هسته مرده، با backoff همان یک سرور را دوباره امتحان کن
                if (!coreUp) {
                    retryWholeListLater();
                } else {
                    rescheduleNormal();
                }
                return;
            }
            Log.w(TAG, "switching to next server");
            int next = (currentIdx + 1) % servers.size();
            if (connectFrom(next)) {
                saveState();
                rescheduleNormal();
            } else {
                // BACKOFF (A1): قبلاً اینجا stopEverything() صدا زده می‌شد. حالا، چون این
                // سرویس دقیقاً برای وقتی طراحی شده که خود اپ بسته است، به‌جای تسلیم فوری
                // دوباره با تأخیر فزاینده کل لیست را امتحان می‌کند؛ قطع واقعی فقط با
                // ACTION_STOP / onRevoke (دست کاربر) اتفاق می‌افتد.
                Log.e(TAG, "all servers failed this round");
                retryWholeListLater();
            }
        }
    }

    private void rescheduleNormal() {
        listExhaustedStreak = 0;
        if (!stopping) startWatchdog(CHECK_EVERY_SEC);
    }

    // BACKOFF (A1): کل لیست یک دور کامل شکست خورد؛ با تأخیر فزاینده (۲،۴،۸،۱۶،۳۲،۶۰ ثانیه،
    // بعد همیشه ۶۰) دوباره از سرور اول امتحان کن. سرویس زنده می‌ماند (آیکون/نوتیف باقی
    // می‌ماند) تا شبکه برگردد؛ این دقیقاً شکلی از خودترمیمی است که بقیه‌ی اپ هم دارد.
    private void retryWholeListLater() {
        if (stopping) return;
        int streakIdx = Math.min(listExhaustedStreak, BACKOFF_SEC.length - 1);
        int delay = BACKOFF_SEC[streakIdx];
        listExhaustedStreak++;
        active = false; // probe بعدی تا وصل مجدد واقعی دخالت نکند
        retryWaiting = true;
        Log.w(TAG, "all servers down; retrying whole list in " + delay + "s (streak="
                + listExhaustedStreak + ")");
        updateNotification("در حال تلاش برای اتصال مجدد… (" + delay + "s)");
        // LEAKFIX: the previous executor must be shut down (same self-shutdown-from-
        // within pattern as stopWatchdog()'s own comment) before it is replaced, or
        // every exhausted round leaks one non-daemon thread that never gets collected.
        stopWatchdog();
        watchdog = Executors.newSingleThreadScheduledExecutor();
        watchdog.schedule(this::retryWholeListNow, delay, TimeUnit.SECONDS);
    }

    private void retryWholeListNow() {
        synchronized (lock) {
            retryWaiting = false;
            if (stopping || servers.isEmpty()) return;
            Log.i(TAG, "retrying full server list after backoff");
            if (connectFrom(0)) {
                saveState();
                rescheduleNormal();
            } else {
                retryWholeListLater();
            }
        }
    }

    // درخواست HTTP از پورت محلی هسته: یعنی ترافیک واقعی از داخل تونل. A2: نوع خطا هم
    // برمی‌گردد (refused/no-route = سخت، timeout/نامشخص = نرم).
    private ProbeResult probeResult() {
        HttpURLConnection c = null;
        try {
            Proxy p = new Proxy(Proxy.Type.HTTP,
                    new InetSocketAddress("127.0.0.1", LOCAL_HTTP_PORT));
            c = (HttpURLConnection) new URL(CHECK_URL).openConnection(p);
            c.setConnectTimeout(CHECK_TIMEOUT_MS);
            c.setReadTimeout(CHECK_TIMEOUT_MS);
            c.setUseCaches(false);
            c.setInstanceFollowRedirects(false);
            int code = c.getResponseCode();
            return (code == 204 || code == 200) ? ProbeResult.OK : ProbeResult.SOFT_FAIL;
        } catch (ConnectException | NoRouteToHostException e) {
            // چیزی روی آن پورت/آدرس گوش نمی‌دهد (مثلاً هسته‌ی محلی خودش بالا نیامده
            // یا پراکسی محلی رد کرد) — این را سخت در نظر می‌گیریم چون عملاً بار اول هم
            // محتمل است دوباره تکرار شود.
            return ProbeResult.HARD_FAIL;
        } catch (SocketTimeoutException e) {
            // بسته‌ها می‌روند ولی جواب نمی‌آید؛ می‌تواند فیلترینگ موقتی یا کندی شبکه باشد
            return ProbeResult.SOFT_FAIL;
        } catch (Exception e) {
            // خطای نامشخص؛ محتاطانه نرم در نظر بگیر تا یک بار عجیب سرور را فوری قربانی نکند
            return ProbeResult.SOFT_FAIL;
        } finally {
            if (c != null) c.disconnect();
        }
    }

    private ParcelFileDescriptor establish(V2rayConfig cfg) {
        try {
            Builder b = new Builder();
            b.setSession(cfg.REMARK.isEmpty() ? "King VPN" : cfg.REMARK);
            b.setMtu(MTU);
            b.addAddress("26.26.26.1", 30);
            try {
                b.addAddress("fd00:1:fd00:1:fd00:1:fd00:1", 126);
                b.addRoute("::", 0);
            } catch (Exception e) {
                Log.w(TAG, "ipv6 sinkhole not supported", e);
            }
            b.addRoute("0.0.0.0", 0);
            try {
                // برنامه‌ی خودمان بیرون VPN بماند تا سوکت‌های هسته حلقه نشوند
                b.addDisallowedApplication(getPackageName());
            } catch (Exception e) {
                Log.w(TAG, "cannot exclude self", e);
            }
            return b.establish();
        } catch (Exception e) {
            Log.e(TAG, "establish failed", e);
            return null;
        }
    }

    private void startForegroundSafe(String remark) {
        updateNotification(remark == null || remark.isEmpty() ? "متصل است" : remark);
    }

    private void updateNotification(String text) {
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
                NotificationChannel ch = new NotificationChannel(
                        CHANNEL_ID, "King VPN", NotificationManager.IMPORTANCE_LOW);
                nm.createNotificationChannel(ch);
            }
            Notification.Builder nb = Build.VERSION.SDK_INT >= 26
                    ? new Notification.Builder(this, CHANNEL_ID)
                    : new Notification.Builder(this);
            nb.setContentTitle("King VPN")
                    .setContentText(text)
                    .setSmallIcon(android.R.drawable.ic_lock_lock)
                    .setOngoing(true);
            startForeground(NOTIF_ID, nb.build());
        } catch (Exception e) {
            Log.w(TAG, "foreground notification failed", e);
        }
    }

    // توقف کامل: از ACTION_STOP، onRevoke، یا وقتی همه‌ی سرورها خراب باشند
    private void stopEverything() {
        synchronized (lock) {
            if (stopping) return;
            stopping = true;
            try {
                active = false;
                retryWaiting = false;
                // SHUTDOWNFIX: a plain shutdown() does not cancel a pending ONE-SHOT
                // delayed task (Java's default ExecuteExistingDelayedTasksAfterShutdown
                // policy is true for `schedule`, unlike for `scheduleWithFixedDelay`,
                // where it defaults to false) — so a queued checkOnce()/retryWholeListNow()
                // could still fire minutes later. It would be a harmless no-op either way
                // (checkOnce/retryWholeListNow both bail out immediately once `stopping`
                // is true), but shutdownNow() here cancels it outright instead of relying
                // on that. This is safe ONLY because stopEverything() is never called from
                // inside the watchdog's own thread (always from onStartCommand/onRevoke,
                // i.e. the main thread) — stopWatchdog()'s plain shutdown() stays as-is for
                // every self-reschedule call site that DOES run on the watchdog thread.
                if (watchdog != null) {
                    watchdog.shutdownNow();
                    watchdog = null;
                }
                V2rayCoreManager core = V2rayCoreManager.getInstance();
                if (core.isV2rayCoreRunning()) {
                    core.stopCore();
                }
            } catch (Exception e) {
                Log.e(TAG, "stopCore failed", e);
            }
            closeTun();
            clearState();
            servers.clear();
            try {
                stopForeground(true);
            } catch (Exception ignored) {
            }
            stopSelf();
            stopping = false;
        }
    }

    private void closeTun() {
        try {
            if (tun != null) {
                tun.close();
            }
        } catch (Exception ignored) {
        }
        tun = null;
    }

    // ---- ذخیره و بازیابی وضعیت (برای START_STICKY) ----
    private void saveState() {
        try {
            JSONArray arr = new JSONArray();
            for (Srv s : servers) {
                JSONObject o = new JSONObject();
                o.put("config", s.config);
                o.put("remark", s.remark);
                o.put("addr", s.addr);
                o.put("port", s.port);
                arr.put(o);
            }
            SharedPreferences sp = getSharedPreferences(PREFS, MODE_PRIVATE);
            sp.edit().putString("list", arr.toString())
                    .putInt("idx", currentIdx)
                    .apply();
        } catch (Exception e) {
            Log.w(TAG, "saveState failed", e);
        }
    }

    private boolean loadState() {
        try {
            SharedPreferences sp = getSharedPreferences(PREFS, MODE_PRIVATE);
            String raw = sp.getString("list", "");
            if (raw == null || raw.isEmpty()) return false;
            JSONArray arr = new JSONArray(raw);
            servers.clear();
            for (int i = 0; i < arr.length(); i++) {
                JSONObject o = arr.getJSONObject(i);
                servers.add(new Srv(o.optString("config"), o.optString("remark"),
                        o.optString("addr"), o.optString("port")));
            }
            currentIdx = Math.max(0, Math.min(sp.getInt("idx", 0), servers.size() - 1));
            listExhaustedStreak = 0;
            healthyStreak = 0;
            return !servers.isEmpty();
        } catch (Exception e) {
            Log.w(TAG, "loadState failed", e);
            return false;
        }
    }

    private void clearState() {
        try {
            getSharedPreferences(PREFS, MODE_PRIVATE).edit().clear().apply();
        } catch (Exception ignored) {
        }
    }

    // ---- A4: امتیاز ماندگار هر سرور (برد/باخت)، فقط برای مرتب‌سازی لیست پشتیبان ----
    private int getScore(Srv s) {
        try {
            SharedPreferences sp = getSharedPreferences(SCORE_PREFS, MODE_PRIVATE);
            return sp.getInt(s.scoreKey(), 0);
        } catch (Exception e) {
            return 0;
        }
    }

    private void bumpScore(Srv s, int delta) {
        try {
            String key = s.scoreKey();
            if (key.equals(":")) return; // addr/port خالی: کلید معنی‌دار نیست
            SharedPreferences sp = getSharedPreferences(SCORE_PREFS, MODE_PRIVATE);
            int v = sp.getInt(key, 0) + delta;
            if (v < SCORE_MIN) v = SCORE_MIN;
            if (v > SCORE_MAX) v = SCORE_MAX;
            sp.edit().putInt(key, v).apply();
        } catch (Exception e) {
            Log.w(TAG, "bumpScore failed", e);
        }
    }

    // لیست پشتیبان (servers.subList منهای اندیس ۰) را نزولی بر اساس امتیاز مرتب می‌کند.
    // پایدار (stable sort): بین دو امتیاز مساوی، ترتیب اصلی Dart حفظ می‌شود.
    private void sortByScoreDesc(List<Srv> backups) {
        try {
            Collections.sort(backups, new Comparator<Srv>() {
                @Override
                public int compare(Srv a, Srv b) {
                    return Integer.compare(getScore(b), getScore(a));
                }
            });
        } catch (Exception e) {
            Log.w(TAG, "sortByScoreDesc failed (keeping original order)", e);
        }
    }

    private static List<Srv> parseBackups(String raw) {
        List<Srv> out = new ArrayList<>();
        if (raw == null || raw.isEmpty()) return out;
        try {
            JSONArray arr = new JSONArray(raw);
            for (int i = 0; i < arr.length() && out.size() < MAX_BACKUPS; i++) {
                JSONObject o = arr.getJSONObject(i);
                String cfg = o.optString("config", "");
                if (!cfg.isEmpty()) {
                    out.add(new Srv(cfg, o.optString("remark"),
                            o.optString("addr"), o.optString("port")));
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "bad backups list", e);
        }
        return out;
    }

    @Override
    public void onRevoke() {
        stopEverything();
    }

    @Override
    public void onDestroy() {
        stopWatchdog();
        closeTun();
        super.onDestroy();
    }

    private static String orEmpty(String s) {
        return s == null ? "" : s;
    }

    // ---- V2rayServicesListener ----
    @Override
    public boolean onProtect(int socket) {
        return protect(socket);
    }

    @Override
    public Service getService() {
        return this;
    }

    @Override
    public void startService() {
        // نیازی نیست: شروع با ACTION_START یا بازیابی انجام می‌شود
    }

    @Override
    public void stopService() {
        // TEST-FIX: ignore the stop callback caused by our own core restart
        if (starting || stopping || !active) return;
        // KINGFAILOVER: هسته خودش مرده؛ نگهبان در بررسی بعدی سرور بعدی را بالا می‌آورد
        Log.w(TAG, "core stopped by itself; watchdog will fail over");
    }
}
