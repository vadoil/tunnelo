package com.hiddify.hiddify.bg

import com.hiddify.core.libbox.PlatformInterface
import com.hiddify.core.mobile.Mobile
import com.hiddify.core.mobile.SetupOptions

internal object CoreSetup {
    private val coordinator = CoreSetupCoordinator<PlatformInterface, SetupOptions> { options, platform ->
        Mobile.setup(options, platform)
    }

    fun foreground(options: SetupOptions) = coordinator.foreground(options)
    fun background(options: SetupOptions, platform: PlatformInterface) = coordinator.background(options, platform)
    fun clear(platform: PlatformInterface) = coordinator.clear(platform)
}
