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

import java.net.HttpURLConnection;
import java.net.InetSocketAddress;
import java.net.Proxy;
import java.net.URL;
import java.util.ArrayList;
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
    // چند بررسی ناموفق پشت‌سرهم قبل از تعویض سرور
    private static final int FAILS_BEFORE_SWITCH = 2;
    private static final int MAX_BACKUPS = 8;

    private static final String PREFS = "king_vpn_state";

    private final Object lock = new Object();
    private final List<Srv> servers = new ArrayList<>();
    private ParcelFileDescriptor tun = null;
    private ScheduledExecutorService watchdog = null;
    private int currentIdx = 0;
    private int fails = 0;
    // true وقتی سرویس واقعاً وصل است (بین شروع موفق و توقف)
    private volatile boolean active = false;
    private volatile boolean stopping = false;
    // TEST-FIX: true only while a core (re)start is in progress. The core's own
    // stopService() callback fired by that restart must not kill the new service.
    private volatile boolean starting = false;

    private static class Srv {
        final String config, remark, addr, port;

        Srv(String config, String remark, String addr, String port) {
            this.config = config;
            this.remark = remark;
            this.addr = addr;
            this.port = port;
        }
    }

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

        startForegroundSafe(first.remark);
        synchronized (lock) {
            stopWatchdog();
            servers.clear();
            servers.add(first);
            for (Srv b : backups) {
                if (servers.size() > MAX_BACKUPS) break;
                if (!b.config.equals(first.config)) servers.add(b);
            }
            if (connectFrom(0)) {
                saveState();
                startWatchdog();
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
                startWatchdog();
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
    private void startWatchdog() {
        stopWatchdog();
        watchdog = Executors.newSingleThreadScheduledExecutor();
        watchdog.scheduleWithFixedDelay(this::checkOnce,
                CHECK_EVERY_SEC, CHECK_EVERY_SEC, TimeUnit.SECONDS);
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
            if (coreUp && probe()) {
                fails = 0;
                return;
            }
            if (coreUp) {
                fails++;
                Log.w(TAG, "health check failed (" + fails + "/" + FAILS_BEFORE_SWITCH + ")");
                if (fails < FAILS_BEFORE_SWITCH) return;
            }
            // هسته مرده یا چند بار پاسخ نداده: سرور بعدی
            fails = 0;
            if (servers.size() < 2) {
                // سرور پشتیبانی نیست؛ اگر هسته مرده، سرویس را جمع کن
                if (!coreUp) stopEverything();
                return;
            }
            Log.w(TAG, "switching to next server");
            int next = (currentIdx + 1) % servers.size();
            if (connectFrom(next)) {
                saveState();
            } else {
                Log.e(TAG, "all servers failed");
                stopEverything();
            }
        }
    }

    // درخواست HTTP از پورت محلی هسته: یعنی ترافیک واقعی از داخل تونل
    private boolean probe() {
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
            return code == 204 || code == 200;
        } catch (Exception e) {
            return false;
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
                    .setContentText(remark == null || remark.isEmpty() ? "متصل است" : remark)
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
                stopWatchdog();
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
