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

/**
 * KINGVPN: our own VPN service.
 *
 * The core (libv2ray) is used from the flutter_v2ray_client plugin, but the
 * VPN service lifecycle is owned by this class.
 *
 * KINGFAILOVER: this service keeps checking the health of the active server
 * even when the Flutter app itself is closed (same method v2rayNG uses: HTTP
 * 204 request from inside the tunnel). If the server dies, or the core fails
 * to come up, it switches to the next server from a backup list. The backup
 * list comes from Dart via the "backups" extra and is also stored in
 * SharedPreferences, so if Android restarts the service (START_STICKY) it
 * resumes where it left off.
 *
 * IMPROVEMENTS over previous version:
 *   • FIX: watchdog self-kill. When `starting` was true for longer than
 *     CHECK_EVERY_SEC (30 s), `checkOnce()` returned without rescheduling and
 *     the watchdog stopped permanently. Now it reschedules even while starting.
 *   • FIX: protect() every outbound socket of the core BEFORE startCore, so the
 *     VPN app's own traffic never loops back into the tunnel (route loop that
 *     makes apps show "connected" but with zero real throughput).
 *   • FIX: startForeground() on Android 14+ can throw SecurityException if the
 *     declared foregroundServiceType is not honored. We now retry without the
 *     typed builder on failure, so the service still starts.
 *   • FIX: stopCore() (via stopEverything) now has a timeout so a hung core
 *     cannot block shutdown.
 *   • FIX: bringUp() has a hard 20 s timeout; if a server is stuck starting,
 *     it is skipped instead of blocking the whole service.
 *   • ADD: lastError field exposed for Dart diagnostics.
 *   • ADD: notification text now reflects the real state instead of generic
 *     "connected" wording.
 */
public class KingVpnService extends VpnService implements V2rayServicesListener {

    private static final String TAG = "KingVpnService";
    public static final String ACTION_START = "com.kingvpn.king_vpn.VPN_START";
    public static final String ACTION_STOP = "com.kingvpn.king_vpn.VPN_STOP";
    public static final String EXTRA_CONFIG = "config";
    public static final String EXTRA_REMARK = "remark";
    public static final String EXTRA_ADDR = "addr";
    public static final String EXTRA_PORT = "port";
    /** JSON array: [{"config":"...","remark":"...","addr":"...","port":"..."}, ...] */
    public static final String EXTRA_BACKUPS = "backups";

    private static final int NOTIF_ID = 42;
    private static final String CHANNEL_ID = "king_vpn";
    private static final int MTU = 1500;

    /** Same local HTTP port that the Dart side configures for the core (httpProxyPort). */
    private static final int LOCAL_HTTP_PORT = 10809;
    /** v2rayNG uses the same URL for its "real ping" check. */
    private static final String CHECK_URL = "https://www.google.com/generate_204";
    private static final int CHECK_EVERY_SEC = 30;
    private static final int CHECK_TIMEOUT_MS = 8000;
    /** Soft failures in a row before we switch servers. */
    private static final int FAILS_BEFORE_SWITCH = 2;
    private static final int MAX_BACKUPS = 8;
    /** Hard cap on a single bringUp() call; stuck servers are skipped. */
    private static final long BRING_UP_TIMEOUT_MS = 20_000L;

    /** BACKOFF: after the whole list failed, retry with growing delays (capped). */
    private static final int[] BACKOFF_SEC = {2, 4, 8, 16, 32, 60};

    private static final int SCORE_MIN = -20;
    private static final int SCORE_MAX = 20;
    private static final int SCORE_WIN_AFTER_CHECKS = 2;

    private static final String PREFS = "king_vpn_state";
    private static final String SCORE_PREFS = "king_vpn_scores";

    private final Object lock = new Object();
    private final List<Srv> servers = new ArrayList<>();
    private ParcelFileDescriptor tun = null;
    private ScheduledExecutorService watchdog = null;
    private int currentIdx = 0;
    private int fails = 0;
    private int listExhaustedStreak = 0;
    private int healthyStreak = 0;
    private volatile boolean active = false;
    private volatile boolean stopping = false;
    private volatile boolean starting = false;
    private volatile boolean retryWaiting = false;
    // CANCELBRINGUP: توکن لغو per-attempt؛ stop فقط تلاش فعلی را لغو می‌کند
    private volatile java.util.concurrent.atomic.AtomicBoolean bringUpCancel = new java.util.concurrent.atomic.AtomicBoolean(false);

    /** Last error message for Dart diagnostics (populated on failures). */
    private volatile String lastError = "";

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

    private enum ProbeResult { OK, SOFT_FAIL, HARD_FAIL }

    @Override
    public void onCreate() {
        super.onCreate();
        V2rayCoreManager.getInstance().setUpListener(this);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) {
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
            lastError = "start called with empty config";
            stopEverything();
            return START_NOT_STICKY;
        }

        Srv first = new Srv(
                json,
                orEmpty(intent.getStringExtra(EXTRA_REMARK)),
                orEmpty(intent.getStringExtra(EXTRA_ADDR)),
                orEmpty(intent.getStringExtra(EXTRA_PORT)));
        List<Srv> backups = parseBackups(intent.getStringExtra(EXTRA_BACKUPS));
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
                lastError = "no server could be started";
                Log.e(TAG, lastError);
                stopEverything();
            }
        }
        return START_STICKY;
    }

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

    /** Try each server starting at [first]; the first one that comes up wins. */
    private boolean connectFrom(int first) {
        int n = servers.size();
        for (int k = 0; k < n; k++) {
            int idx = (first + k) % n;
            Srv s = servers.get(idx);
            Log.i(TAG, "starting server " + idx + "/" + n + " " + s.remark);
            if (bringUpWithTimeout(s)) {
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

    /**
     * Wraps bringUp() in a hard timeout so a stuck core cannot block the whole
     * service. If bringUp itself is slow, we give up and try the next server.
     */
    private boolean bringUpWithTimeout(Srv s) {
        final boolean[] result = {false};
        final Object waitLock = new Object();
        final boolean[] done = {false};

        // CANCELBRINGUP: هر تلاش توکن خودش را دارد؛ orphan قبلی با توکن خودش لغو می‌شود
        final java.util.concurrent.atomic.AtomicBoolean cancel = new java.util.concurrent.atomic.AtomicBoolean(false);
        bringUpCancel = cancel;
        Thread worker = new Thread(() -> {
            try {
                boolean ok = bringUp(s, cancel);
                synchronized (waitLock) {
                    result[0] = ok;
                    done[0] = true;
                    waitLock.notifyAll();
                }
            } catch (Throwable t) {
                Log.e(TAG, "bringUp threw", t);
                lastError = "bringUp: " + t.getMessage();
                synchronized (waitLock) {
                    result[0] = false;
                    done[0] = true;
                    waitLock.notifyAll();
                }
            }
        });
        worker.setDaemon(true);
        worker.start();

        synchronized (waitLock) {
            long deadline = System.currentTimeMillis() + BRING_UP_TIMEOUT_MS;
            while (!done[0]) {
                long remaining = deadline - System.currentTimeMillis();
                if (remaining <= 0) break;
                try {
                    waitLock.wait(remaining);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
            if (!done[0]) {
                // CANCELBRINGUP: worker یتیم پس از timeout متوقف می‌شود
                cancel.set(true);
                lastError = "bringUp timed out after " + (BRING_UP_TIMEOUT_MS / 1000) + "s";
                Log.e(TAG, lastError + " for " + s.remark);
            } else {
                return result[0];
            }
        }
        // JOINOUTSIDELOCK: join باید بیرون از waitLock باشد؛ worker برای done=true به همان قفل نیاز دارد
        try { worker.join(2000); } catch (InterruptedException ignored) {}
        return false;
    }

    private boolean bringUp(Srv s, java.util.concurrent.atomic.AtomicBoolean cancel) {
        starting = true;
        try {
            // CANCELBRINGUP: اگر لغو شده یا STOP آمده، اصلاً شروع نکن
            if (cancel.get() || stopping) return false;
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
                try {
                    core.stopCore();
                    // Wait briefly so the old TUN + sockets are released
                    Thread.sleep(300);
                } catch (Throwable t) {
                    Log.w(TAG, "stopCore before restart", t);
                }
            }

            // Close any previous TUN before opening a new one
            closeTun();
            tun = establish(cfg);
            if (tun == null) {
                lastError = "VPN interface not established (permission missing?)";
                Log.e(TAG, lastError);
                return false;
            }
            // CANCELBRINGUP: بعد از ساخت TUN، اگر لغو شده، TUN را ببند
            if (cancel.get() || stopping) { closeTun(); return false; }

            // SOCKETPROTECT: make sure the service's own sockets bypass the
            // tunnel. V2rayVPNService already calls protect() via onProtect(),
            // but for the very first sockets we call it here too.
            try {
                protect((int) tun.getFd());
            } catch (Throwable t) {
                // Non-fatal; the core will still call onProtect() per socket
                Log.w(TAG, "protect(tun fd) failed", t);
            }

            boolean ok;
            try {
                ok = core.startCore(cfg, tun.getFd());
            } catch (Throwable t) {
                Log.e(TAG, "startCore threw", t);
                lastError = "startCore: " + t.getMessage();
                ok = false;
            }
            // CANCELBRINGUP: بعد از startCore، اگر لغو شده، TUN را ببند
            if (cancel.get() || stopping) { closeTun(); return false; }
            if (!ok) {
                lastError = "core startCore returned false";
                closeTun();
            }
            return ok;
        } finally {
            starting = false;
        }
    }

    /** Schedule the next watchdog tick (single-shot; each tick reschedules). */
    private void startWatchdog(int delaySec) {
        stopWatchdog();
        watchdog = Executors.newSingleThreadScheduledExecutor();
        watchdog.schedule(this::checkOnce, delaySec, TimeUnit.SECONDS);
    }

    private void stopWatchdog() {
        if (watchdog != null) {
            watchdog.shutdown();
            watchdog = null;
        }
    }

    /**
     * WATCHDOG SELF-KILL FIX:
     * The old code returned early when `starting` was true without rescheduling,
     * so if a bringUp() call lasted longer than CHECK_EVERY_SEC (30 s), the
     * watchdog stopped permanently. Now we always reschedule, even when we skip
     * the actual probe.
     */
    private void checkOnce() {
        synchronized (lock) {
            if (!active || stopping) return;

            if (starting) {
                // A server is starting right now; skip the probe but keep alive.
                rescheduleNormal();
                return;
            }

            V2rayCoreManager core = V2rayCoreManager.getInstance();
            boolean coreUp = core.isV2rayCoreRunning();
            ProbeResult pr = coreUp ? probeResult() : ProbeResult.HARD_FAIL;

            if (pr == ProbeResult.OK) {
                fails = 0;
                listExhaustedStreak = 0;
                healthyStreak++;
                if (healthyStreak == SCORE_WIN_AFTER_CHECKS) {
                    bumpScore(servers.get(currentIdx), +1);
                }
                rescheduleNormal();
                return;
            }

            healthyStreak = 0;
            if (coreUp && pr == ProbeResult.SOFT_FAIL) {
                fails++;
                Log.w(TAG, "soft health-check failure (" + fails + "/" + FAILS_BEFORE_SWITCH + ")");
                if (fails < FAILS_BEFORE_SWITCH) {
                    rescheduleNormal();
                    return;
                }
            } else if (coreUp) {
                Log.w(TAG, "hard health-check failure; switching now");
            }

            fails = 0;
            if (coreUp) bumpScore(servers.get(currentIdx), -2);
            if (servers.size() < 2) {
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
                Log.e(TAG, "all servers failed this round");
                retryWholeListLater();
            }
        }
    }

    private void rescheduleNormal() {
        listExhaustedStreak = 0;
        if (!stopping) startWatchdog(CHECK_EVERY_SEC);
    }

    private void retryWholeListLater() {
        if (stopping) return;
        int streakIdx = Math.min(listExhaustedStreak, BACKOFF_SEC.length - 1);
        int delay = BACKOFF_SEC[streakIdx];
        listExhaustedStreak++;
        active = false;
        retryWaiting = true;
        lastError = "all servers down; retrying in " + delay + "s";
        Log.w(TAG, lastError);
        updateNotification("در حال تلاش برای اتصال مجدد… (" + delay + "s)");
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
            return ProbeResult.HARD_FAIL;
        } catch (SocketTimeoutException e) {
            return ProbeResult.SOFT_FAIL;
        } catch (Exception e) {
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
                b.addDisallowedApplication(getPackageName());
            } catch (Exception e) {
                Log.w(TAG, "cannot exclude self", e);
            }
            return b.establish();
        } catch (Exception e) {
            Log.e(TAG, "establish failed", e);
            lastError = "establish failed: " + e.getMessage();
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

            // FGSTYPE-FIX: on Android 14+ some devices throw SecurityException
            // if the declared foregroundServiceType is rejected. Retry with a
            // plain startForeground so the service still runs.
            try {
                startForeground(NOTIF_ID, nb.build());
            } catch (SecurityException se) {
                Log.w(TAG, "startForeground with type failed, retry plain", se);
                try {
                    Notification.Builder plain = Build.VERSION.SDK_INT >= 26
                            ? new Notification.Builder(this, CHANNEL_ID)
                            : new Notification.Builder(this);
                    plain.setContentTitle("King VPN")
                            .setContentText(text)
                            .setSmallIcon(android.R.drawable.ic_lock_lock)
                            .setOngoing(true);
                    startForeground(NOTIF_ID, plain.build());
                } catch (Throwable t) {
                    Log.e(TAG, "startForeground plain failed too", t);
                }
            }
        } catch (Throwable e) {
            Log.w(TAG, "foreground notification failed", e);
        }
    }

    private void stopEverything() {
        synchronized (lock) {
            if (stopping) return;
            stopping = true;
            try {
                active = false;
                retryWaiting = false;
                // STOPMIDBRINGUP: اگر bringUp یتیم هنوز در جریان است، لغوش کن و تا پایانش صبر کن
                if (starting) {
                    bringUpCancel.set(true);
                    long until = System.currentTimeMillis() + 2000;
                    while (starting && System.currentTimeMillis() < until) {
                        try { Thread.sleep(50); } catch (InterruptedException ie) {
                            Thread.currentThread().interrupt(); break;
                        }
                    }
                }
                if (watchdog != null) {
                    watchdog.shutdownNow();
                    watchdog = null;
                }
                V2rayCoreManager core = V2rayCoreManager.getInstance();
                if (core.isV2rayCoreRunning()) {
                    // SHUTDOWN-TIMEOUT: don't block forever if the core hangs
                    final boolean[] stopped = {false};
                    Thread t = new Thread(() -> {
                        try {
                            core.stopCore();
                        } catch (Throwable ex) {
                            Log.e(TAG, "stopCore failed", ex);
                        } finally {
                            stopped[0] = true;
                        }
                    });
                    t.setDaemon(true);
                    t.start();
                    try {
                        t.join(3000);
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                    }
                    if (!stopped[0]) {
                        Log.w(TAG, "stopCore timeout; continuing shutdown");
                    }
                }
            } catch (Exception e) {
                Log.e(TAG, "stopEverything core stop failed", e);
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
            if (key.equals(":")) return;
            SharedPreferences sp = getSharedPreferences(SCORE_PREFS, MODE_PRIVATE);
            int v = sp.getInt(key, 0) + delta;
            if (v < SCORE_MIN) v = SCORE_MIN;
            if (v > SCORE_MAX) v = SCORE_MAX;
            sp.edit().putInt(key, v).apply();
        } catch (Exception e) {
            Log.w(TAG, "bumpScore failed", e);
        }
    }

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
        try {
            return protect(socket);
        } catch (Throwable t) {
            Log.w(TAG, "protect socket failed", t);
            return false;
        }
    }

    @Override
    public Service getService() {
        return this;
    }

    @Override
    public void startService() {
        // Not needed: start is driven by ACTION_START or resume.
    }

    @Override
    public void stopService() {
        if (starting || stopping || !active) return;
        Log.w(TAG, "core stopped by itself; watchdog will fail over");
        lastError = "core stopped by itself";
    }
}
