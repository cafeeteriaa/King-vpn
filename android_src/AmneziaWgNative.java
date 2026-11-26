/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Thin JNI declaration matching the official AmneziaWG Android JNI ABI.
 * The native library is built from the pinned upstream source by the
 * AmneziaWG native build pipeline; it is intentionally not GoBackend's
 * independent Android VpnService implementation.
 */
package org.amnezia.awg;

public final class GoBackend {
    static {
        System.loadLibrary("awg-go");
    }

    private GoBackend() {}

    public static native String awgGetConfig(int handle);
    public static native int awgGetSocketV4(int handle);
    public static native int awgGetSocketV6(int handle);
    public static native void awgTurnOff(int handle);
    public static native int awgTurnOn(String ifName, int tunFd, String settings);
    public static native String awgVersion();
}
