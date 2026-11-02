package com.kingvpn.king_vpn;

import android.app.ActivityManager;
import android.app.ApplicationExitInfo;
import android.content.Context;
import android.os.Build;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;

/**
 * KINGDIAG: records WHY the app process died, so the next in-app error report can show it.
 *
 * The user's phone (Samsung One UI) showed "king_vpn was closed because this app has a problem /
 * clear cache?" while connecting. That dialog means the process crashed, but nothing in the old
 * report said how. Two sources are used:
 *  1) Java crash: a default UncaughtExceptionHandler writes the stack to files/king_last_crash.txt
 *     and then hands over to the previous handler, so Android's own crash behaviour is unchanged.
 *  2) Any kind of process death (Java crash, native/Go crash, ANR, low memory, killed by the
 *     system): ApplicationExitInfo (Android 11+) is read at the next start.
 *
 * Everything here is wrapped in try/catch: diagnostics must never be the reason for a crash.
 */
public final class KingDiag {
    private static final String CRASH_FILE = "king_last_crash.txt";
    // time of the newest process exit that was already reported (each death is reported once)
    private static final String SEEN_FILE = "king_diag_seen.txt";
    private static volatile boolean installed = false;

    private KingDiag() {
    }

    private static Context appCtx(Context c) {
        Context a = c.getApplicationContext();
        return a != null ? a : c;
    }

    /** Safe to call many times; never throws. */
    public static void install(Context ctx) {
        try {
            if (installed) return;
            installed = true;
            final Context app = appCtx(ctx);
            final Thread.UncaughtExceptionHandler prev = Thread.getDefaultUncaughtExceptionHandler();
            Thread.setDefaultUncaughtExceptionHandler(new Thread.UncaughtExceptionHandler() {
                @Override
                public void uncaughtException(Thread t, Throwable e) {
                    try {
                        recordCrash(app, t, e);
                    } catch (Throwable ignored) {
                        // the recorder must never hide the real crash
                    }
                    if (prev != null) prev.uncaughtException(t, e);
                }
            });
        } catch (Throwable ignored) {
            // nothing to do
        }
    }

    private static String procName() {
        BufferedReader r = null;
        try {
            r = new BufferedReader(new FileReader("/proc/self/cmdline"));
            String s = r.readLine();
            if (s != null) {
                int z = s.indexOf('\0');
                return z >= 0 ? s.substring(0, z) : s;
            }
        } catch (Throwable ignored) {
            // fall through
        } finally {
            closeQuietly(r);
        }
        return "?";
    }

    private static void recordCrash(Context app, Thread t, Throwable e) throws Exception {
        StringWriter sw = new StringWriter();
        PrintWriter pw = new PrintWriter(sw);
        pw.println(new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(new Date())
                + " proc=" + procName() + " thread=" + (t == null ? "?" : t.getName()));
        e.printStackTrace(pw);
        pw.flush();
        String body = sw.toString();
        if (body.length() > 8000) body = body.substring(0, 8000);
        File f = new File(app.getFilesDir(), CRASH_FILE);
        // only the newest crash is kept: a crash loop must not fill the disk
        FileOutputStream o = new FileOutputStream(f, false);
        try {
            o.write(body.getBytes("UTF-8"));
            o.getFD().sync();
        } finally {
            o.close();
        }
    }

    private static String clip(String s, int max) {
        if (s == null) return "";
        s = s.replace('\n', ' ').replace('\r', ' ').trim();
        return s.length() > max ? s.substring(0, max) : s;
    }

    private static void closeQuietly(java.io.Closeable c) {
        try {
            if (c != null) c.close();
        } catch (Throwable ignored) {
            // nothing to do
        }
    }

    private static long readSeen(Context app) {
        BufferedReader r = null;
        try {
            File f = new File(app.getFilesDir(), SEEN_FILE);
            if (!f.exists()) return 0L;
            r = new BufferedReader(new FileReader(f));
            String s = r.readLine();
            return s == null ? 0L : Long.parseLong(s.trim());
        } catch (Throwable ignored) {
            return 0L;
        } finally {
            closeQuietly(r);
        }
    }

    private static void writeSeen(Context app, long ts) {
        FileOutputStream o = null;
        try {
            o = new FileOutputStream(new File(app.getFilesDir(), SEEN_FILE), false);
            o.write(String.valueOf(ts).getBytes("UTF-8"));
        } catch (Throwable ignored) {
            // worst case: the same exit is reported again
        } finally {
            closeQuietly(o);
        }
    }

    /**
     * The Java crash recorded by the previous run, as report lines (CRASH-JAVA1 ...), or "".
     * The file is deleted once read, so each crash is reported once.
     */
    public static String takeLastCrash(Context ctx) {
        try {
            File f = new File(appCtx(ctx).getFilesDir(), CRASH_FILE);
            if (!f.exists()) return "";
            StringBuilder raw = new StringBuilder();
            BufferedReader r = null;
            try {
                r = new BufferedReader(new InputStreamReader(new FileInputStream(f), "UTF-8"));
                String ln;
                int guard = 0;
                while ((ln = r.readLine()) != null && guard++ < 400) {
                    raw.append(ln).append('\n');
                }
            } finally {
                closeQuietly(r);
            }
            //noinspection ResultOfMethodCallIgnored
            f.delete();
            return digest(raw.toString());
        } catch (Throwable t) {
            return "";
        }
    }

    /** First lines of the stack + the "Caused by" chain, one report line each (max 16). */
    private static String digest(String txt) {
        List<String> out = new ArrayList<String>();
        String[] ls = txt.split("\n");
        int frames = 0;
        int caused = 0;
        for (int k = 0; k < ls.length && out.size() < 16; k++) {
            String t = ls[k].trim();
            if (t.length() == 0) continue;
            if (k == 0) {
                out.add(t);
                continue;
            }
            if (t.startsWith("at ")) {
                if (frames < (caused == 0 ? 6 : 4)) {
                    out.add(t);
                    frames++;
                }
                continue;
            }
            if (t.startsWith("Caused by:")) {
                if (caused >= 3) continue;
                caused++;
                frames = 0;
                out.add(t);
                continue;
            }
            if (t.startsWith("...")) continue;
            // the first non-"at" line after the header is the exception itself
            if (frames == 0 && caused == 0) {
                out.add(t);
            }
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < out.size(); i++) {
            sb.append("CRASH-JAVA").append(i + 1).append(' ').append(clip(out.get(i), 260)).append('\n');
        }
        return sb.toString();
    }

    private static String reasonName(int r) {
        switch (r) {
            case 1:
                return "EXIT_SELF";
            case 2:
                return "SIGNALED";
            case 3:
                return "LOW_MEMORY";
            case 4:
                return "CRASH";
            case 5:
                return "CRASH_NATIVE";
            case 6:
                return "ANR";
            case 7:
                return "INITIALIZATION_FAILURE";
            case 8:
                return "PERMISSION_CHANGE";
            case 9:
                return "EXCESSIVE_RESOURCE_USAGE";
            case 10:
                return "USER_REQUESTED";
            case 11:
                return "USER_STOPPED";
            case 12:
                return "DEPENDENCY_DIED";
            case 13:
                return "OTHER";
            case 14:
                return "FREEZER";
            case 15:
                return "PACKAGE_STATE_CHANGE";
            case 16:
                return "PACKAGE_UPDATED";
            default:
                return "UNKNOWN(" + r + ")";
        }
    }

    /** Normal ends (the user swiped the app away, the app updated itself...) are not interesting. */
    private static boolean interesting(int r) {
        switch (r) {
            case 2: // SIGNALED
            case 3: // LOW_MEMORY
            case 4: // CRASH
            case 5: // CRASH_NATIVE
            case 6: // ANR
            case 7: // INITIALIZATION_FAILURE
            case 9: // EXCESSIVE_RESOURCE_USAGE
            case 12: // DEPENDENCY_DIED
            case 13: // OTHER
            case 14: // FREEZER
                return true;
            default:
                return false;
        }
    }

    /**
     * Why did the app's recent processes die? (Android 11+) Report lines "PROC-EXIT1 ...", or "".
     * Only the last 24 hours and only abnormal reasons are returned (max 5 processes).
     */
    @android.annotation.TargetApi(30)
    public static String lastExits(Context ctx) {
        if (Build.VERSION.SDK_INT < 30) return "";
        StringBuilder sb = new StringBuilder();
        try {
            ActivityManager am = (ActivityManager) appCtx(ctx).getSystemService(Context.ACTIVITY_SERVICE);
            if (am == null) return "";
            List<ApplicationExitInfo> l = am.getHistoricalProcessExitReasons(null, 0, 12);
            if (l == null) return "";
            Context app = appCtx(ctx);
            long seen = readSeen(app);
            long newest = seen;
            long now = System.currentTimeMillis();
            int shown = 0;
            for (ApplicationExitInfo i : l) {
                long ts = i.getTimestamp();
                if (ts > newest) newest = ts;
                if (shown >= 5) continue; // keep looking only to find the newest timestamp
                if (ts <= seen) continue; // already reported by an earlier start
                int r = i.getReason();
                long ageMin = (now - ts) / 60000L;
                if (ageMin > 24 * 60) continue;
                if (!interesting(r)) continue;
                shown++;
                StringBuilder line = new StringBuilder();
                line.append("PROC-EXIT").append(shown).append(' ').append(reasonName(r))
                        .append(" \u2022 ").append(ageMin).append(" min ago \u2022 proc=").append(i.getProcessName())
                        .append(" \u2022 status=").append(i.getStatus())
                        .append(" \u2022 imp=").append(i.getImportance())
                        .append(" \u2022 rss=").append(i.getRss() / 1024L).append("MB");
                String desc = i.getDescription();
                if (desc != null && desc.length() > 0) line.append(" \u2022 ").append(desc);
                sb.append(clip(line.toString(), 280)).append('\n');
                if (r == 5) {
                    nativeHints(sb, i, shown);
                } else if (r == 6) {
                    anrHints(sb, i, shown);
                }
            }
            if (newest > seen) writeSeen(app, newest);
        } catch (Throwable t) {
            sb.append("PROC-EXIT0 ").append(clip(String.valueOf(t), 200)).append('\n');
        }
        return sb.toString();
    }

    /**
     * Native crash: the trace is a binary tombstone (protobuf). The readable parts (library paths,
     * abort message, symbol names) are enough to see which library crashed.
     */
    @android.annotation.TargetApi(30)
    private static void nativeHints(StringBuilder sb, ApplicationExitInfo info, int idx) {
        InputStream in = null;
        try {
            in = info.getTraceInputStream();
            if (in == null) return;
            byte[] buf = new byte[160 * 1024];
            int n = 0;
            int k;
            while (n < buf.length && (k = in.read(buf, n, buf.length - n)) > 0) {
                n += k;
            }
            LinkedHashSet<String> seen = new LinkedHashSet<String>();
            StringBuilder cur = new StringBuilder();
            for (int p = 0; p <= n && seen.size() < 40; p++) {
                int c = p < n ? (buf[p] & 0xff) : 0;
                if (c >= 32 && c < 127) {
                    cur.append((char) c);
                    continue;
                }
                if (cur.length() >= 8) {
                    String t = cur.toString();
                    String low = t.toLowerCase(Locale.US);
                    if (low.contains(".so") || low.contains("panic") || low.contains("fatal")
                            || low.contains("abort") || low.contains("sig") || low.contains("runtime")
                            || low.contains("goroutine") || low.contains("gojni") || low.contains("xray")
                            || low.contains("v2ray") || low.contains("tun")) {
                        seen.add(t);
                    }
                }
                cur.setLength(0);
            }
            int num = 0;
            for (String t : seen) {
                if (num >= 8) break;
                num++;
                sb.append("PROC-EXIT").append(idx).append("-NATIVE").append(num).append(' ')
                        .append(clip(t, 220)).append('\n');
            }
        } catch (Throwable ignored) {
            // the main line was already written
        } finally {
            closeQuietly(in);
        }
    }

    /** ANR: the trace is text; the "main" thread stack shows what the app was stuck on. */
    @android.annotation.TargetApi(30)
    private static void anrHints(StringBuilder sb, ApplicationExitInfo info, int idx) {
        BufferedReader r = null;
        try {
            InputStream in = info.getTraceInputStream();
            if (in == null) return;
            r = new BufferedReader(new InputStreamReader(in, "UTF-8"));
            String ln;
            int lines = 0;
            int shown = 0;
            boolean inMain = false;
            while ((ln = r.readLine()) != null && lines++ < 6000) {
                if (!inMain) {
                    if (ln.startsWith("\"main\" prio=")) inMain = true;
                    continue;
                }
                String t = ln.trim();
                if (t.length() == 0) break;
                shown++;
                sb.append("PROC-EXIT").append(idx).append("-ANR").append(shown).append(' ')
                        .append(clip(t, 220)).append('\n');
                if (shown >= 10) break;
            }
        } catch (Throwable ignored) {
            // the main line was already written
        } finally {
            closeQuietly(r);
        }
    }
}
