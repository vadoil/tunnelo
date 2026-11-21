package com.hiddify.hiddify.bg

import java.lang.ref.WeakReference

/** Both UI and VPN service initialize the same Go instance. */
internal class CoreSetupCoordinator<P : Any, O>(private val setup: (O, P?) -> Unit) {
    private var platform: WeakReference<P>? = null

    @Synchronized fun foreground(options: O) {
        // A UI setup must retain the existing Android VPN bridge.
        setup(options, platform?.get())
    }

    @Synchronized fun background(options: O, nativePlatform: P) {
        setup(options, nativePlatform)
        platform = WeakReference(nativePlatform)
    }

    @Synchronized fun clear(nativePlatform: P) {
        if (platform?.get() === nativePlatform) platform = null
    }
}
