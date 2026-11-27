package com.kingvpn.king_vpn;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.VpnService;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import android.os.SystemClock;
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
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.locks.ReentrantLock;

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
    /** جدید: notification id used by the plugin (V2rayCoreManager.NOTIFICATION_ID). */
    private static final int PLUGIN_NOTIF_ID = 1;
    /** جدید: libv2ray is wired once per process; see wireCoreOnce(). */
    private static volatile boolean coreWired = false;
    private static final String CHANNEL_ID = "king_vpn";
    private static final int MTU = 1500;

    /** Same local HTTP port that the Dart side configures for the core (httpProxyPort). */
    private static final int LOCAL_HTTP_PORT = 10809;
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

    /** Boolean extra: the user chose national-network mode (international internet cut). */
    public static final String EXTRA_NATIONAL = "national";
    /** Attempt id from Dart (see own_vpn.dart). 0 = no attempt (service restart / resume). */
    public static final String EXTRA_ATTEMPT = "attempt";
    /**
     * Probes used in national mode (international internet cut). Only domestic
     * destinations count there; the international probes always fail in that mode.
     */
    private static final String[] DOMESTIC_PROBE_URLS = {
            "https://www.aparat.com/",
            "https://www.digikala.com/",
            "https://www.snapp.ir/",
    };
    /**
     * Probes used in global mode. Only international destinations count there, so a
     * domestic site answering through a dead tunnel cannot mark the server as healthy.
     */
    private static final String[] INTERNATIONAL_PROBE_URLS = {
            "https://www.google.com/generate_204",
            "https://www.gstatic.com/generate_204",
    };

    private final Object lock = new Object();
    private final List<Srv> servers = new ArrayList<>();
    private ParcelFileDescriptor tun = null;
    // جدید: ONE scheduler for the whole service (was a new executor per tick, never closed)
    private volatile ScheduledExecutorService scheduler = null;
    // جدید: the pending watchdog tick; cancelled when replaced
    private volatile ScheduledFuture<?> watchdogTask = null;
    /** Attempt id of the start that is currently active; sent with every status message. */
    private volatile int activeAttemptId = 0;
    private int currentIdx = 0;
    private int fails = 0;
    private int listExhaustedStreak = 0;
    private int healthyStreak = 0;
    private final AtomicLong watchdogChecks = new AtomicLong(0);
    private final AtomicLong healthyProbes = new AtomicLong(0);
    private final AtomicLong softProbeFailures = new AtomicLong(0);
    private final AtomicLong hardProbeFailures = new AtomicLong(0);
    private final AtomicLong failoverCount = new AtomicLong(0);
    private final AtomicLong retryCount = new AtomicLong(0);
    private volatile long serviceStartedElapsedMs = 0L;
    private volatile long lastProbeElapsedMs = 0L;
    private volatile long lastProbeDurationMs = 0L;
    private volatile String lastProbeResult = "never";
    private volatile String lastProbeMode = "unknown";
    private volatile boolean active = false;
    private volatile boolean stopping = false;
    private volatile boolean retryWaiting = false;
    // ---- Core ownership -------------------------------------------------------
    // The V2Ray core is ONE native instance and the TUN is ONE fd. Lock order is
    // lock -> coreLock -> tunLock. Every operation that starts or stops the core,
    // or opens or closes the TUN, runs under coreLock and only while its attempt
    // is still the newest (isCurrent). So an orphaned attempt can never touch the
    // core once it has been superseded, however long it lives: it either never
    // gets the lock and bails out, or it cleans up its own result before releasing.
    private final ReentrantLock coreLock = new ReentrantLock();
    /** Every new attempt, every stop and every timeout increments this. */
    private final AtomicInteger attemptSeq = new AtomicInteger(0);
    /** bringUp calls that have not returned yet, orphans included. */
    private final AtomicInteger inFlight = new AtomicInteger(0);
    /** True while a stopCore call is still running on its thread (it may hang). Core is fenced. */
    private volatile boolean coreStopping = false;
    /** Close the TUN only after a timed-out native stop has actually returned. */
    private boolean closeTunAfterCoreStop = false;
    /**
     * A native call (startCore/stopCore) that does not return cannot be killed from Java.
     * If one stays busy longer than HUNG_NATIVE_MS, the only real recovery is a fresh
     * process: the Go runtime behind the core cannot be reset in place. We save the
     * state first, then end the process; START_STICKY makes Android restart the service,
     * and resumeSaved() reconnects from the saved list.
     */
    private static final long HUNG_NATIVE_MS = 45_000L;
    private final AtomicLong nativeToken = new AtomicLong(0);
    private volatile boolean nativeBusy = false;
    private final AtomicBoolean recovering = new AtomicBoolean(false);
    /** True when the user asked to stop. A restart after a hang must not resume the connection. */
    private volatile boolean userStopped = false;
    /** How long a stop waits for coreLock before it leaves the core to the attempt holding it. */
    private static final long STOP_LOCK_WAIT_MS = 3000L;
    /** How long one stopCore call may take before the core is considered fenced. */
    private static final long STOP_CORE_WAIT_MS = 3000L;
    /** Guards the TUN handle only. Never acquire `lock` while holding this. */
    private final Object tunLock = new Object();

    // Validated physical underlays only; never export SSID, carrier or network IDs.
    private final Object physicalNetworkLock = new Object();
    private final Map<Network, Integer> validatedPhysicalNetworks = new LinkedHashMap<>();
    private volatile ConnectivityManager connectivityManager;
    private volatile ConnectivityManager.NetworkCallback physicalNetworkCallback;
    private final AtomicLong physicalNetworkChangeCount = new AtomicLong(0);
    private volatile long lastPhysicalNetworkChangeElapsedMs = 0L;
    private volatile int validatedWifiNetworkCount = 0;
    private volatile int validatedCellularNetworkCount = 0;
    private volatile String physicalNetworkTransportSummary = "unknown";
    /** Single worker: all start/stop/resume work runs here, never on the main thread. */
    private volatile ExecutorService worker = null;
    /** Serializes worker submission with onDestroy() detaching and shutting it down. */
    private final Object workerLock = new Object();

    /** Persisted national-mode flag (see EXTRA_NATIONAL). */
    private volatile boolean nationalMode = false;

    /** Last error message for Dart diagnostics (populated on failures). */
    private volatile String lastError = "";

    /** Diagnostic accessor for the last failure message. */
    public String getLastError() { return lastError; }

    /**
     * Privacy-safe snapshot for cross-language diagnostics.
     * Never includes server config, credentials, addresses, or backup payloads.
     */
    public Map<String, Object> diagnosticSnapshot() {
        synchronized (lock) {
        final long now = SystemClock.elapsedRealtime();
        Map<String, Object> snapshot = new HashMap<String, Object>();
        snapshot.put("protocolVersion", 3);
        snapshot.put("serviceRunning", true);
        snapshot.put("active", active);
        snapshot.put("stopping", stopping);
        snapshot.put("retryWaiting", retryWaiting);
        snapshot.put("nativeBusy", nativeBusy);
        snapshot.put("recovering", recovering.get());
        snapshot.put("userStopped", userStopped);
        snapshot.put("nationalMode", nationalMode);
        snapshot.put("activeAttempt", activeAttemptId);
        snapshot.put("attemptSequence", attemptSeq.get());
        snapshot.put("inFlightOperations", inFlight.get());
        String error = lastError == null ? "" : lastError.toLowerCase(java.util.Locale.ROOT);
        snapshot.put("lastErrorPresent", !error.isEmpty());
        String category = "none";
        if (!error.isEmpty()) {
            if (error.contains("permission")) category = "permission";
            else if (error.contains("timeout") || error.contains("timed out")) category = "timeout";
            else if (error.contains("empty config")) category = "invalid_config";
            else if (error.contains("establish")) category = "tun_setup";
            else if (error.contains("core")) category = "core";
            else if (error.contains("stopped")) category = "stopped";
            else category = "service";
        }
        snapshot.put("lastErrorCategory", category);
        snapshot.put("serviceUptimeMs", serviceStartedElapsedMs > 0L ? Math.max(0L, now - serviceStartedElapsedMs) : 0L);
        snapshot.put("watchdogChecks", watchdogChecks.get());
        snapshot.put("healthyProbes", healthyProbes.get());
        snapshot.put("softProbeFailures", softProbeFailures.get());
        snapshot.put("hardProbeFailures", hardProbeFailures.get());
        snapshot.put("failoverCount", failoverCount.get());
        snapshot.put("retryCount", retryCount.get());
        snapshot.put("currentFailureStreak", fails);
        snapshot.put("healthyStreak", healthyStreak);
        snapshot.put("lastProbeResult", lastProbeResult);
        snapshot.put("lastProbeMode", lastProbeMode);
        snapshot.put("lastProbeDurationMs", lastProbeDurationMs);
        snapshot.put("lastProbeAgeMs", lastProbeElapsedMs > 0L ? Math.max(0L, now - lastProbeElapsedMs) : -1L);
        snapshot.put("physicalNetworkProtocolVersion", 1);
        snapshot.put("physicalNetworkChangeCount", physicalNetworkChangeCount.get());
        snapshot.put("lastPhysicalNetworkChangeAgeMs", lastPhysicalNetworkChangeElapsedMs > 0L ? Math.max(0L, now - lastPhysicalNetworkChangeElapsedMs) : -1L);
        snapshot.put("validatedWifiNetworkCount", validatedWifiNetworkCount);
        snapshot.put("validatedCellularNetworkCount", validatedCellularNetworkCount);
        snapshot.put("physicalNetworkTransportSummary", physicalNetworkTransportSummary);
        return snapshot;
        }
    }

    /** جدید: receives start/stop outcomes; MainActivity forwards them to Dart. */
    public interface StatusSink {
        void onStatus(String state, String error, int attempt);
    }
    /** جدید: set by MainActivity. States: CONNECTED, FAILED, STOPPED. */
    public static volatile StatusSink statusSink = null;
    /** جدید: the running instance, so the app can stop it directly (no background startService). */
    public static volatile KingVpnService instance = null;

    /** جدید: sends a status to Dart if a sink is registered. Never throws. */
    private void emit(String state, String error, int attempt) {
        StatusSink s = statusSink;
        if (s == null) return;
        try {
            s.onStatus(state, error == null ? "" : error, attempt);
        } catch (Throwable t) {
            Log.w(TAG, "status sink failed", t);
        }
    }

    /** جدید: stop requested by the app while it is in the background. */
    public void stopFromApp() {
        requestStop();
        submit(this::stopEverything);
    }

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
        worker = Executors.newSingleThreadExecutor();
        serviceStartedElapsedMs = SystemClock.elapsedRealtime();
        instance = this; // جدید
        wireCoreOnce(); // جدید: was setUpListener() on every start
        registerPhysicalNetworkMonitor();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // Keep this method short: it runs on the main thread, and the system
        // expects a foreground service to be promoted within a few seconds.
        if (intent == null) {
            // Android restarted the service (START_STICKY): promote immediately on the
            // main thread before queuing recovery, otherwise a busy worker can miss the
            // foreground-service deadline and Android may terminate the VPN process.
            if (!startForegroundSafe("در حال بازیابی اتصال…")) {
                lastError = "Unable to enter foreground mode during VPN service recovery";
                Log.e(TAG, lastError);
                requestStop();
                submit(this::stopEverything);
                return START_NOT_STICKY;
            }
            // No Dart attempt is waiting for it, so its status uses attempt 0 (accepted by all).
            activeAttemptId = 0;
            submit(this::resumeSaved);
            return START_STICKY;
        }
        String action = intent.getAction();
        if (ACTION_STOP.equals(action)) {
            // ACTION_STOP may itself arrive through startForegroundService; satisfy the
            // same deadline before asynchronous shutdown work is queued.
            startForegroundSafe("در حال قطع اتصال…");
            requestStop();
            submit(this::stopEverything);
            return START_NOT_STICKY;
        }
        if (!ACTION_START.equals(action)) {
            return START_NOT_STICKY;
        }

        String json = intent.getStringExtra(EXTRA_CONFIG);
        if (json == null || json.isEmpty()) {
            Log.e(TAG, "start without config");
            lastError = "start called with empty config";
            // جدید: startForegroundService requires startForeground() within 5 s, or Android
            // kills the process with ForegroundServiceDidNotStartInTimeException.
            updateNotification("خطا: تنظیمات سرور خالی است");
            requestStop();
            submit(this::stopEverything);
            return START_NOT_STICKY;
        }

        Srv first = new Srv(
                json,
                orEmpty(intent.getStringExtra(EXTRA_REMARK)),
                orEmpty(intent.getStringExtra(EXTRA_ADDR)),
                orEmpty(intent.getStringExtra(EXTRA_PORT)));
        List<Srv> backups = parseBackups(intent.getStringExtra(EXTRA_BACKUPS));
        sortByScoreDesc(backups);
        nationalMode = intent.getBooleanExtra(EXTRA_NATIONAL, false);
        activeAttemptId = intent.getIntExtra(EXTRA_ATTEMPT, 0);
        userStopped = false;

        if (!startForegroundSafe(first.remark)) {
            lastError = "Unable to enter foreground mode; VPN startup was refused";
            Log.e(TAG, lastError);
            emit("FAILED", lastError, activeAttemptId);
            requestStop();
            submit(this::stopEverything);
            return START_NOT_STICKY;
        }
        final int attempt = activeAttemptId; // مشکل ۹: شناسه‌ی همین شروع، نه فیلد سراسری بعدی
        submit(() -> startFlow(first, backups, attempt));
        return START_STICKY;
    }

    /** Runs a task on the single worker thread (never on the main thread). */
    private void submit(Runnable r) {
        synchronized (workerLock) {
            ExecutorService ex = worker;
            if (ex == null || ex.isShutdown()) {
                // onDestroy() owns the one final cleanup task. Never run a start/resume
                // task on an ad-hoc thread after the serialized worker has been detached.
                Log.w(TAG, "worker unavailable; dropping task after shutdown");
                return;
            }
            try {
                ex.execute(r);
            } catch (java.util.concurrent.RejectedExecutionException e) {
                // Shutdown cleanup is scheduled explicitly by onDestroy(); running this
                // arbitrary task concurrently could restart the VPN after destruction.
                Log.w(TAG, "worker rejected task; service shutdown owns cleanup", e);
            }
        }
    }

    /** Last-resort daemon execution when the service worker is already unavailable. */
    private void runFallback(Runnable r) {
        Thread t = new Thread(r, "KingVpnService-fallback");
        t.setDaemon(true);
        t.start();
    }

    /** Worker side of ACTION_START: builds the list and connects. */
    private void startFlow(Srv first, List<Srv> backups, int attempt) {
        synchronized (lock) {
            if (stopping) return; // a stop request arrived first
            // جدید: without the user's VPN consent, establish() fails for every server one by one.
            // Check once here and report a single clear error instead.
            if (VpnService.prepare(this) != null) {
                lastError = "VPN permission not granted";
                Log.e(TAG, lastError);
                emit("FAILED", lastError, attempt); // جدید
                stopEverything();
                return;
            }
            stopWatchdog();
            listExhaustedStreak = 0;
            healthyStreak = 0;
            servers.clear();
            servers.add(first);
            for (Srv b : backups) {
                if (servers.size() > MAX_BACKUPS) break;
                if (!b.config.equals(first.config)) servers.add(b);
            }
            currentIdx = 0; // جدید: new list starts at 0; a stale index from the last session was saved before
            fails = 0;      // جدید
            saveState(); // persist the pending list first, so a restart mid-connect can resume it
            if (connectFrom(0)) {
                saveState();
                startWatchdog(CHECK_EVERY_SEC);
                emit("CONNECTED", "", attempt); // جدید
            } else {
                lastError = "no server could be started";
                Log.e(TAG, lastError);
                emit("FAILED", lastError, attempt); // جدید
                stopEverything();
            }
        }
    }

    private void resumeSaved() {
        synchronized (lock) {
            if (stopping) return;
            if (!loadState()) {
                stopSelf();
                return;
            }
            startForegroundSafe(servers.get(currentIdx).remark);
            if (connectFrom(currentIdx)) {
                saveState();
                startWatchdog(CHECK_EVERY_SEC);
                return;
            }
            stopEverything();
        }
    }

    /**
     * Non-blocking half of a stop. Safe to call on the main thread: it only sets
     * flags and cancels the running attempt. The real work runs on the worker.
     */
    private void requestStop() {
        userStopped = true;
        stopping = true;
        active = false;
        retryWaiting = false;
        // Supersede whatever attempt is running. It can no longer act on the core.
        attemptSeq.incrementAndGet();
    }

    /** Try each server starting at [first]; the first one that comes up wins. */
    private boolean connectFrom(int first) {
        int n = servers.size();
        for (int k = 0; k < n; k++) {
            if (stopping) return false; // جدید: a Stop stops the list walk at once; no next server starts
            int idx = (first + k) % n;
            Srv s = servers.get(idx);
            Log.i(TAG, "starting server " + idx + "/" + n + " " + s.remark);
            if (bringUpWithTimeout(s)) {
                currentIdx = idx;
                fails = 0;
                healthyStreak = 0;
                active = true;
                applyValidatedUnderlyingNetworks();
                startForegroundSafe(s.remark);
                cancelPluginNotification(); // جدید
                return true;
            }
            Log.w(TAG, "server failed to start: " + s.remark);
        }
        return false;
    }

    /**
     * Runs bringUp() on its own thread with a hard timeout. A timed-out attempt is
     * superseded at once (attemptSeq is bumped), so it can never act on the core
     * afterwards. There is no join-and-continue: the next attempt does not start
     * the core until it holds coreLock, which the orphan releases only when it is done.
     */
    private boolean bringUpWithTimeout(Srv s) {
        final int myAttempt = attemptSeq.incrementAndGet();
        final boolean[] result = {false};
        final Object waitLock = new Object();
        final boolean[] done = {false};

        Thread attemptThread = new Thread(() -> {
            boolean ok = false;
            try {
                ok = bringUp(s, myAttempt);
            } catch (Throwable t) {
                Log.e(TAG, "bringUp threw", t);
                lastError = "bringUp: " + t.getMessage();
            } finally {
                synchronized (waitLock) {
                    result[0] = ok;
                    done[0] = true;
                    waitLock.notifyAll();
                }
            }
        });
        attemptThread.setDaemon(true);
        attemptThread.start();

        synchronized (waitLock) {
            long deadline = System.currentTimeMillis() + BRING_UP_TIMEOUT_MS;
            while (!done[0]) {
                if (stopping) break; // جدید: a Stop cancels this wait at once instead of up to 20 s
                long remaining = deadline - System.currentTimeMillis();
                if (remaining <= 0) break;
                try {
                    waitLock.wait(Math.min(remaining, 100L)); // جدید: short slices so Stop is seen quickly
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
            if (done[0]) return result[0];
        }
        // Not finished: either a Stop arrived or the timeout expired. Supersede this attempt
        // BEFORE reporting, so that if it returns later from startCore it sees it is stale.
        attemptSeq.incrementAndGet();
        if (stopping) {
            lastError = "stopped by user"; // جدید
            Log.i(TAG, lastError + " for " + s.remark);
        } else {
            lastError = "bringUp timed out after " + (BRING_UP_TIMEOUT_MS / 1000) + "s";
            Log.e(TAG, lastError + " for " + s.remark);
        }
        return false;
    }

    private static void closeQuietly(ParcelFileDescriptor fd) {
        if (fd == null) return;
        try { fd.close(); } catch (Exception ignored) {}
    }

    /** True only for the newest attempt, while no stop is in progress. */
    private boolean isCurrent(int myAttempt) {
        return myAttempt == attemptSeq.get() && !stopping;
    }

    /** True while any bringUp thread (including an orphan) is still inside the core path. */
    private boolean isStarting() {
        return inFlight.get() > 0;
    }

    /** Marks a native call as in progress and arms a watcher for it. */
    private void beginNative(final String what) {
        final long token = nativeToken.incrementAndGet();
        nativeBusy = true;
        Thread w = new Thread(() -> {
            try {
                Thread.sleep(HUNG_NATIVE_MS);
            } catch (InterruptedException ie) {
                return;
            }
            if (nativeBusy && nativeToken.get() == token) recoverWedgedCore(what);
        }, "king-native-watch");
        w.setDaemon(true);
        w.start();
    }

    private void endNative() {
        nativeBusy = false;
    }

    /**
     * The core is wedged inside a native call. Save what we need, then end the process so
     * Android restarts the service fresh (START_STICKY). If the user asked to stop, the
     * saved state is cleared so the restart does not reconnect.
     */
    private void recoverWedgedCore(String what) {
        if (!recovering.compareAndSet(false, true)) return;
        Log.e(TAG, what + " has not returned after " + (HUNG_NATIVE_MS / 1000)
                + "s; restarting the VPN process");
        try {
            if (userStopped) clearState();
            else saveState();
        } catch (Throwable t) {
            Log.w(TAG, "state save before restart failed", t);
        }
        android.os.Process.killProcess(android.os.Process.myPid());
    }

    /**
     * Stops the core if it is running. Caller must hold coreLock. The stop runs on its
     * own thread so that a hung native call cannot block shutdown forever. If it is
     * still running after STOP_CORE_WAIT_MS the core stays fenced (coreStopping) until
     * that call returns, and no start is allowed in the meantime.
     */
    private boolean stopCoreNow() {
        V2rayCoreManager core = V2rayCoreManager.getInstance();
        synchronized (tunLock) {
            if (coreStopping) {
                closeTunAfterCoreStop = true;
                return false;
            }
            final boolean running;
            try {
                running = core.isV2rayCoreRunning();
            } catch (Throwable stateError) {
                closeTunAfterCoreStop = true;
                lastError = "could not read core state before stop";
                Log.e(TAG, lastError + "; retaining TUN", stateError);
                return false;
            }
            if (!running) {
                if (closeTunAfterCoreStop) {
                    closeQuietly(tun);
                    tun = null;
                    closeTunAfterCoreStop = false;
                }
                return true;
            }
            coreStopping = true;
        }
        Thread t = new Thread(() -> {
            try {
                core.stopCore();
            } catch (Throwable ex) {
                Log.e(TAG, "stopCore failed", ex);
            } finally {
                endNative();
                final boolean stillRunning;
                try {
                    stillRunning = core.isV2rayCoreRunning();
                } catch (Throwable checkError) {
                    Log.e(TAG, "could not verify native core stop; retaining TUN", checkError);
                    synchronized (tunLock) {
                        coreStopping = false;
                        closeTunAfterCoreStop = true;
                    }
                    return;
                }
                synchronized (tunLock) {
                    coreStopping = false;
                    if (!stillRunning && closeTunAfterCoreStop) {
                        closeQuietly(tun);
                        tun = null;
                        closeTunAfterCoreStop = false;
                    } else if (stillRunning) {
                        // stopCore() may throw or return while the native process is alive.
                        // Keep both the descriptor and the deferred-close marker for retry.
                        closeTunAfterCoreStop = true;
                        Log.e(TAG, "native core remains running; retaining TUN until a verified stop");
                    }
                }
            }
        }, "KingVpnCoreStop");
        t.setDaemon(true);
        beginNative("stopCore");
        t.start();
        try {
            t.join(STOP_CORE_WAIT_MS);
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
        }
        synchronized (tunLock) {
            if (coreStopping) {
                // The native core may still be using its TUN descriptor. Defer closing it
                // to the stop thread instead of tearing the interface out from underneath it.
                closeTunAfterCoreStop = true;
                Log.w(TAG, "stopCore still running; TUN close deferred until native stop returns");
                return false;
            }
            final boolean stillRunning;
            try {
                stillRunning = core.isV2rayCoreRunning();
            } catch (Throwable stateError) {
                closeTunAfterCoreStop = true;
                lastError = "could not verify native core stop";
                Log.e(TAG, lastError + "; retaining TUN", stateError);
                return false;
            }
            if (stillRunning) {
                closeTunAfterCoreStop = true;
                Log.e(TAG, "native core is still running after stop; TUN retained");
                return false;
            }
            if (closeTunAfterCoreStop) {
                closeQuietly(tun);
                tun = null;
                closeTunAfterCoreStop = false;
            }
            return true;
        }
    }

    /**
     * Worker-side start of one attempt. Everything that touches the shared core or the
     * TUN happens here, under coreLock, and only while this attempt is current.
     */
    private boolean bringUp(Srv s, int myAttempt) {
        inFlight.incrementAndGet();
        coreLock.lock();
        try {
            // A newer attempt, a stop, or a timeout may have superseded us while we waited.
            if (!isCurrent(myAttempt)) return false;

            V2rayConfig cfg = new V2rayConfig();
            cfg.V2RAY_FULL_JSON_CONFIG = s.config;
            cfg.REMARK = s.remark;
            cfg.CONNECTED_V2RAY_SERVER_ADDRESS = s.addr;
            cfg.CONNECTED_V2RAY_SERVER_PORT = s.port;
            cfg.APPLICATION_NAME = "King VPN";
            cfg.NOTIFICATION_DISCONNECT_BUTTON_NAME = "قطع";
            cfg.ENABLE_TRAFFIC_STATICS = true;

            V2rayCoreManager core = V2rayCoreManager.getInstance();
            // جدید: setUpListener() here rebuilt the CoreController, so the running core was
            // orphaned (isV2rayCoreRunning() read false on the new one, ports stayed bound).
            // Only the listener reference is updated now; the controller is never replaced.
            core.v2rayServicesListener = this;
            if (core.isV2rayCoreRunning()) {
                stopCoreNow();
                // Poll briefly until the core reports stopped (its flag may lag the call).
                long until = System.currentTimeMillis() + 1500L;
                while (core.isV2rayCoreRunning() && !coreStopping
                        && System.currentTimeMillis() < until) {
                    try { Thread.sleep(50); } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        break;
                    }
                }
            }
            // Refuse to start on a core that is still shutting down or still running.
            if (coreStopping || core.isV2rayCoreRunning()) {
                lastError = "core still busy from a previous attempt";
                Log.e(TAG, lastError);
                return false;
            }

            closeTun();
            ParcelFileDescriptor fd = establish(cfg);
            if (fd == null) {
                lastError = "VPN interface not established (permission missing?)";
                Log.e(TAG, lastError);
                return false;
            }
            synchronized (tunLock) {
                if (!isCurrent(myAttempt)) {
                    closeQuietly(fd);
                    return false;
                }
                tun = fd;
            }

            // SOCKETPROTECT: the service's own sockets must bypass the tunnel.
            try {
                protect((int) fd.getFd());
            } catch (Throwable t) {
                // Non-fatal; the core will still call onProtect() per socket
                Log.w(TAG, "protect(tun fd) failed", t);
            }

            boolean ok;
            try {
                beginNative("startCore");
                ok = core.startCore(cfg, fd.getFd());
            } catch (Throwable t) {
                Log.e(TAG, "startCore threw", t);
                lastError = "startCore: " + t.getMessage();
                ok = false;
            } finally {
                endNative();
            }
            if (!isCurrent(myAttempt)) {
                // Superseded while startCore ran. We still hold coreLock, so no other
                // attempt has touched the core; undo our own start and leave.
                boolean stopped = stopCoreNow();
                if (stopped) closeTun();
                return false;
            }
            if (!ok) {
                lastError = "core startCore returned false";
                boolean stopped = stopCoreNow();
                if (stopped) closeTun();
            }
            return ok;
        } finally {
            coreLock.unlock();
            inFlight.decrementAndGet();
        }
    }

    /** Schedule the next watchdog tick (single-shot; each tick reschedules). */
    private void startWatchdog(int delaySec) {
        scheduleTask(this::checkOnce, delaySec);
    }

    /** جدید: schedules one task on the single shared scheduler, replacing any pending tick. */
    private void scheduleTask(Runnable task, int delaySec) {
        stopWatchdog();
        ScheduledExecutorService s = scheduler;
        if (s == null || s.isShutdown()) {
            s = Executors.newSingleThreadScheduledExecutor();
            scheduler = s;
        }
        watchdogTask = s.schedule(task, delaySec, TimeUnit.SECONDS);
    }

    /** جدید: cancels the pending tick. The scheduler thread is reused, never leaked. */
    private void stopWatchdog() {
        ScheduledFuture<?> f = watchdogTask;
        watchdogTask = null;
        if (f != null) f.cancel(false);
    }

    /**
     * WATCHDOG SELF-KILL FIX:
     * The old code returned early when `starting` was true without rescheduling,
     * so if a bringUp() call lasted longer than CHECK_EVERY_SEC (30 s), the
     * watchdog stopped permanently. Now we always reschedule, even when we skip
     * the actual probe.
     */
    private void checkOnce() {
        final long probeStartedElapsedMs = SystemClock.elapsedRealtime();
        watchdogChecks.incrementAndGet();
        synchronized (lock) {
            if (!active || stopping) return;
            if (isStarting()) {
                // A server is starting right now; skip the probe but keep alive.
                rescheduleNormal();
                return;
            }
        }
        // The probe does network I/O (several seconds at worst). It runs OUTSIDE the
        // lock, so a stop request or a server switch is never blocked behind it.
        V2rayCoreManager core = V2rayCoreManager.getInstance();
        final boolean coreUp;
        try {
            coreUp = core.isV2rayCoreRunning();
        } catch (Throwable stateError) {
            // A transient JNI/state-query failure must not kill the scheduled watchdog.
            // Keep the current TUN and retry on the next tick; never fail over on unknown state.
            recordWatchdogProbe("core_state_unknown", probeStartedElapsedMs);
            Log.e(TAG, "watchdog could not read core state; retaining current tunnel", stateError);
            synchronized (lock) {
                if (active && !stopping) rescheduleNormal();
            }
            return;
        }
        ProbeResult pr = coreUp ? probeResult() : ProbeResult.HARD_FAIL;
        final String outcome = !coreUp ? "core_down" :
                (pr == ProbeResult.OK ? "healthy" :
                (pr == ProbeResult.SOFT_FAIL ? "soft_failure" : "hard_failure"));
        recordWatchdogProbe(outcome, probeStartedElapsedMs);

        synchronized (lock) {
            if (!active || stopping) return;
            if (isStarting()) {
                rescheduleNormal();
                return;
            }

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
                failoverCount.incrementAndGet();
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
        retryCount.incrementAndGet();
        int streakIdx = Math.min(listExhaustedStreak, BACKOFF_SEC.length - 1);
        int base = BACKOFF_SEC[streakIdx];
        // ±10% jitter so many devices do not retry at the same moment
        int delay = Math.max(1, base + (int) Math.round(base * 0.1 * (Math.random() * 2 - 1)));
        listExhaustedStreak++;
        active = false;
        retryWaiting = true;
        lastError = "all servers down; retrying in " + delay + "s";
        Log.w(TAG, lastError);
        updateNotification("در حال تلاش برای اتصال مجدد… (" + delay + "s)");
        scheduleTask(this::retryWholeListNow, delay);
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

    /**
     * OK if any probe gets an HTTP answer through the tunnel. In national mode the
     * international probe is skipped: it always fails there, which used to make the
     * watchdog punish good national servers and switch between them forever.
     */
    private void recordWatchdogProbe(String result, long startedAtElapsedMs) {
        final long now = SystemClock.elapsedRealtime();
        lastProbeElapsedMs = now;
        lastProbeDurationMs = Math.max(0L, now - startedAtElapsedMs);
        lastProbeResult = result;
        lastProbeMode = nationalMode ? "national" : "global";
        if ("healthy".equals(result)) healthyProbes.incrementAndGet();
        else if ("soft_failure".equals(result)) softProbeFailures.incrementAndGet();
        else if ("hard_failure".equals(result) || "core_down".equals(result)) hardProbeFailures.incrementAndGet();
    }

    private ProbeResult probeResult() {
        ProbeResult worst = ProbeResult.HARD_FAIL;
        String[] urls = nationalMode ? DOMESTIC_PROBE_URLS : INTERNATIONAL_PROBE_URLS;
        for (String u : urls) {
            ProbeResult r = probeOne(u);
            if (r == ProbeResult.OK) return ProbeResult.OK;
            if (r == ProbeResult.SOFT_FAIL) worst = ProbeResult.SOFT_FAIL;
        }
        return worst;
    }

    private ProbeResult probeOne(String url) {
        HttpURLConnection c = null;
        try {
            Proxy p = new Proxy(Proxy.Type.HTTP,
                    new InetSocketAddress("127.0.0.1", LOCAL_HTTP_PORT));
            c = (HttpURLConnection) new URL(url).openConnection(p);
            c.setConnectTimeout(CHECK_TIMEOUT_MS);
            c.setReadTimeout(CHECK_TIMEOUT_MS);
            c.setUseCaches(false);
            c.setInstanceFollowRedirects(false);
            c.setRequestProperty("User-Agent", "Mozilla/5.0");
            // Any real HTTP answer (2xx, 3xx, even 403) proves the request went through the tunnel.
            int code = c.getResponseCode();
            return (code >= 200 && code < 500) ? ProbeResult.OK : ProbeResult.SOFT_FAIL;
        } catch (ConnectException | NoRouteToHostException e) {
            // جدید: the core is running (checked before probing), so a refused connection to the
            // local port means only that this config has no HTTP inbound. That must not switch
            // servers every 30 s; it counts as a soft failure like any other.
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
            // FIX #49: the app is NOT excluded from the tunnel. Its own requests (e.g. the ASN
            // lookup in nat_ultra.dart, which uses DIRECT) must go through the VPN, otherwise they
            // show the real IP. Only the core's outbound sockets are exempt, via protect() in onProtect.
            return b.establish();
        } catch (Exception e) {
            Log.e(TAG, "establish failed", e);
            lastError = "establish failed: " + e.getMessage();
            return null;
        }
    }

    /** جدید: wires libv2ray exactly once per process. */
    private void wireCoreOnce() {
        synchronized (KingVpnService.class) {
            if (coreWired) return;
            V2rayCoreManager.getInstance().setUpListener(this);
            coreWired = true;
        }
    }

    /**
     * جدید: the plugin calls startForeground(1) inside startCore() and shows its own
     * notification whose button points to the plugin's VPN service. That service's
     * onCreate() would call setUpListener() and orphan our core. Remove it: our own
     * notification (id 42) is the foreground one and has our own stop button.
     */
    private void cancelPluginNotification() {
        try {
            NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            if (nm != null) nm.cancel(PLUGIN_NOTIF_ID);
        } catch (Throwable t) {
            Log.w(TAG, "cancel plugin notification failed", t);
        }
    }

    private boolean startForegroundSafe(String remark) {
        return updateNotification(remark == null || remark.isEmpty() ? "متصل است" : remark);
    }

    private boolean updateNotification(String text) {
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
                if (nm == null) throw new IllegalStateException("NotificationManager unavailable");
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

            // جدید: the stop button now targets THIS service (was the plugin's VPN service).
            Intent stop = new Intent(this, KingVpnService.class);
            stop.setAction(ACTION_STOP);
            int flags = PendingIntent.FLAG_UPDATE_CURRENT
                    | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0);
            PendingIntent stopPi = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                    ? PendingIntent.getForegroundService(this, 1, stop, flags)
                    : PendingIntent.getService(this, 1, stop, flags);
            nb.addAction(0, "قطع", stopPi); // جدید

            // Plain startForeground: no typed variant, so no separate retry is needed.
            startForeground(NOTIF_ID, nb.build());
            return true;
        } catch (Throwable e) {
            Log.e(TAG, "foreground notification failed", e);
            return false;
        }
    }

    private void stopEverything() {
        synchronized (lock) {
            // Supersede every attempt first: a stale one that returns later does nothing.
            stopping = true;
            attemptSeq.incrementAndGet();
            active = false;
            retryWaiting = false;
            stopWatchdog(); // جدید: cancel only; the shared scheduler is closed in onDestroy

            boolean locked = false;
            try {
                locked = coreLock.tryLock(STOP_LOCK_WAIT_MS, TimeUnit.MILLISECONDS);
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
            }
            if (locked) {
                try {
                    boolean stopped = stopCoreNow();
                    if (stopped) closeTun();
                } catch (Exception e) {
                    Log.e(TAG, "stopEverything core stop failed", e);
                } finally {
                    coreLock.unlock();
                }
            } else {
                // An attempt is still inside a native call. Never touch the core or the
                // TUN from here: that attempt is stale now and will stop the core and
                // close its TUN itself as soon as it returns.
                Log.w(TAG, "core busy in a previous attempt; leaving it to that attempt");
                lastError = "core busy from a previous attempt";
            }
            clearState();
            servers.clear();
            try {
                stopForeground(true);
            } catch (Exception ignored) {
            }
            stopSelf();
            stopping = false;
            emit("STOPPED", "", -1); // جدید: با هیچ تلاشی تطابق ندارد
        }
    }

    private void closeTun() {
        synchronized (tunLock) {
            closeQuietly(tun);
            tun = null;
        }
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
                    .putBoolean("national", nationalMode)
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
            nationalMode = sp.getBoolean("national", false);
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
        // Another VPN took over: stop our core and free the TUN, without blocking the main thread.
        requestStop();
        submit(this::stopEverything);
    }

    @Override
    public void onDestroy() {
        if (instance == this) instance = null; // جدید
        stopWatchdog();
        requestStop();
        ScheduledExecutorService sch = scheduler; // جدید: close the scheduler thread for good
        scheduler = null;
        if (sch != null) sch.shutdownNow();
        // The core must stop so its local ports are released. Run it on the worker; shutdown()
        // still runs queued tasks, so this does not block the main thread.
        boolean fallbackStop = false;
        synchronized (workerLock) {
            ExecutorService ex = worker;
            worker = null;
            if (ex != null) {
                try {
                    // Queue cleanup before shutdown while submissions are excluded by workerLock.
                    ex.execute(this::stopEverything);
                } catch (java.util.concurrent.RejectedExecutionException e) {
                    Log.w(TAG, "worker rejected final cleanup; using fallback", e);
                    fallbackStop = true;
                } finally {
                    ex.shutdown();
                }
            } else {
                fallbackStop = true;
            }
        }
        if (fallbackStop) runFallback(this::stopEverything);
        unregisterPhysicalNetworkMonitor();
        super.onDestroy();
    }

    private void registerPhysicalNetworkMonitor() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return;
        try {
            ConnectivityManager cm = (ConnectivityManager) getSystemService(CONNECTIVITY_SERVICE);
            if (cm == null) return;
            NetworkRequest request = new NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
                    .build();
            ConnectivityManager.NetworkCallback callback = new ConnectivityManager.NetworkCallback() {
                @Override public void onCapabilitiesChanged(Network network, NetworkCapabilities capabilities) {
                    updatePhysicalNetwork(network, capabilities);
                }
                @Override public void onLost(Network network) { removePhysicalNetwork(network); }
            };
            cm.registerNetworkCallback(request, callback);
            connectivityManager = cm;
            physicalNetworkCallback = callback;
        } catch (Throwable t) {
            Log.w(TAG, "physical network monitor unavailable", t);
        }
    }

    private void unregisterPhysicalNetworkMonitor() {
        ConnectivityManager cm = connectivityManager;
        ConnectivityManager.NetworkCallback callback = physicalNetworkCallback;
        connectivityManager = null;
        physicalNetworkCallback = null;
        if (cm != null && callback != null) {
            try { cm.unregisterNetworkCallback(callback); } catch (Throwable ignored) { }
        }
        synchronized (physicalNetworkLock) {
            validatedPhysicalNetworks.clear();
            validatedWifiNetworkCount = 0;
            validatedCellularNetworkCount = 0;
            physicalNetworkTransportSummary = "unknown";
        }
    }

    private void updatePhysicalNetwork(Network network, NetworkCapabilities capabilities) {
        if (network == null || capabilities == null) return;
        int transports = 0;
        boolean internet = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET);
        boolean validated = Build.VERSION.SDK_INT < Build.VERSION_CODES.M
                || capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED);
        if (internet && validated) {
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) transports |= 1;
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) transports |= 2;
        }
        boolean changed;
        synchronized (physicalNetworkLock) {
            Integer previous = validatedPhysicalNetworks.get(network);
            if (transports == 0) changed = validatedPhysicalNetworks.remove(network) != null;
            else {
                changed = previous == null || previous != transports;
                validatedPhysicalNetworks.put(network, transports);
            }
        }
        if (changed) recordPhysicalNetworkChange();
    }

    private void removePhysicalNetwork(Network network) {
        if (network == null) return;
        boolean changed;
        synchronized (physicalNetworkLock) {
            changed = validatedPhysicalNetworks.remove(network) != null;
        }
        if (changed) recordPhysicalNetworkChange();
    }

    private void recordPhysicalNetworkChange() {
        List<Network> wifiNetworks = new ArrayList<>();
        List<Network> cellularNetworks = new ArrayList<>();
        int wifi = 0, cellular = 0;
        synchronized (physicalNetworkLock) {
            for (Map.Entry<Network, Integer> entry : validatedPhysicalNetworks.entrySet()) {
                int transports = entry.getValue();
                if ((transports & 1) != 0) { wifi++; wifiNetworks.add(entry.getKey()); }
                if ((transports & 2) != 0) { cellular++; cellularNetworks.add(entry.getKey()); }
            }
            validatedWifiNetworkCount = wifi;
            validatedCellularNetworkCount = cellular;
            physicalNetworkTransportSummary = wifi > 0 && cellular > 0 ? "wifi_cellular"
                    : wifi > 0 ? "wifi" : cellular > 0 ? "cellular" : "none";
        }
        physicalNetworkChangeCount.incrementAndGet();
        lastPhysicalNetworkChangeElapsedMs = SystemClock.elapsedRealtime();
        if (active && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            applyUnderlyingNetworks(wifiNetworks, cellularNetworks);
        }
    }

    private void applyValidatedUnderlyingNetworks() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP_MR1) return;
        List<Network> wifiNetworks = new ArrayList<>(), cellularNetworks = new ArrayList<>();
        synchronized (physicalNetworkLock) {
            for (Map.Entry<Network, Integer> entry : validatedPhysicalNetworks.entrySet()) {
                int transports = entry.getValue();
                if ((transports & 1) != 0) wifiNetworks.add(entry.getKey());
                if ((transports & 2) != 0) cellularNetworks.add(entry.getKey());
            }
        }
        applyUnderlyingNetworks(wifiNetworks, cellularNetworks);
    }

    private void applyUnderlyingNetworks(List<Network> wifiNetworks, List<Network> cellularNetworks) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP_MR1 || stopping) return;
        List<Network> ordered = new ArrayList<>(wifiNetworks.size() + cellularNetworks.size());
        ordered.addAll(wifiNetworks);
        ordered.addAll(cellularNetworks);
        try {
            setUnderlyingNetworks(ordered.isEmpty() ? null : ordered.toArray(new Network[0]));
        } catch (Throwable t) {
            Log.w(TAG, "could not publish VPN underlying networks", t);
        }
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
        if (isStarting() || stopping || !active) return;
        Log.w(TAG, "core stopped by itself; watchdog will fail over");
        lastError = "core stopped by itself";
    }
}
