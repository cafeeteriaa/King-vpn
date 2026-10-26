package com.kingvpn.king_vpn;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.net.VpnService;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import android.util.Log;

import dev.amirzr.flutter_v2ray_client.v2ray.core.V2rayCoreManager;
import dev.amirzr.flutter_v2ray_client.v2ray.interfaces.V2rayServicesListener;
import dev.amirzr.flutter_v2ray_client.v2ray.utils.V2rayConfig;

// KINGVPN: سرویس VPN خود برنامه.
// هسته (libv2ray) را از پلاگین استفاده می‌کند، اما چرخه‌ی سرویس VPN دست خودمان است.
// هر بار قبل از شروع هسته، این نمونه‌ی سرویس را به هسته معرفی می‌کند (رفع race سرویس پلاگین).
public class KingVpnService extends VpnService implements V2rayServicesListener {

    private static final String TAG = "KingVpnService";
    public static final String ACTION_START = "com.kingvpn.king_vpn.VPN_START";
    public static final String ACTION_STOP = "com.kingvpn.king_vpn.VPN_STOP";
    public static final String EXTRA_CONFIG = "config";
    public static final String EXTRA_REMARK = "remark";
    public static final String EXTRA_ADDR = "addr";
    public static final String EXTRA_PORT = "port";

    private static final int NOTIF_ID = 42;
    private static final String CHANNEL_ID = "king_vpn";
    private static final int MTU = 1500;

    private ParcelFileDescriptor tun = null;
    private boolean stopping = false;

    @Override
    public void onCreate() {
        super.onCreate();
        V2rayCoreManager.getInstance().setUpListener(this);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) {
            return START_NOT_STICKY;
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

        V2rayConfig cfg = new V2rayConfig();
        cfg.V2RAY_FULL_JSON_CONFIG = json;
        cfg.REMARK = orEmpty(intent.getStringExtra(EXTRA_REMARK));
        cfg.CONNECTED_V2RAY_SERVER_ADDRESS = orEmpty(intent.getStringExtra(EXTRA_ADDR));
        cfg.CONNECTED_V2RAY_SERVER_PORT = orEmpty(intent.getStringExtra(EXTRA_PORT));
        cfg.APPLICATION_NAME = "King VPN";
        cfg.NOTIFICATION_DISCONNECT_BUTTON_NAME = "قطع";
        cfg.ENABLE_TRAFFIC_STATICS = true;

        startForegroundSafe(cfg.REMARK);

        // مهم: قبل از شروع هسته، همین نمونه‌ی سرویس را معرفی کن
        V2rayCoreManager core = V2rayCoreManager.getInstance();
        core.setUpListener(this);
        if (core.isV2rayCoreRunning()) {
            core.stopCore();
        }

        tun = establish(cfg);
        if (tun == null) {
            Log.e(TAG, "VPN interface not established (permission missing?)");
            stopEverything();
            return START_NOT_STICKY;
        }

        boolean ok;
        try {
            ok = core.startCore(cfg, tun.getFd());
        } catch (Exception e) {
            Log.e(TAG, "startCore threw", e);
            ok = false;
        }
        if (!ok) {
            Log.e(TAG, "core failed to start");
            stopEverything();
        }
        return START_NOT_STICKY;
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
                    .setContentText(remark.isEmpty() ? "متصل است" : remark)
                    .setSmallIcon(android.R.drawable.ic_lock_lock)
                    .setOngoing(true);
            startForeground(NOTIF_ID, nb.build());
        } catch (Exception e) {
            Log.w(TAG, "foreground notification failed", e);
        }
    }

    // جلوگیری از حلقه: stopCore باعث stopService از طرف هسته می‌شود
    private void stopEverything() {
        if (stopping) return;
        stopping = true;
        try {
            V2rayCoreManager core = V2rayCoreManager.getInstance();
            if (core.isV2rayCoreRunning()) {
                core.stopCore();
            }
        } catch (Exception e) {
            Log.e(TAG, "stopCore failed", e);
        }
        closeTun();
        try {
            stopForeground(true);
        } catch (Exception ignored) {
        }
        stopSelf();
        stopping = false;
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

    @Override
    public void onRevoke() {
        stopEverything();
    }

    @Override
    public void onDestroy() {
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
        // نیازی نیست: شروع با ACTION_START انجام می‌شود
    }

    @Override
    public void stopService() {
        stopEverything();
    }
}
