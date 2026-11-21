package com.hiddify.hiddify.bg

import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class CoreSetupCoordinatorTest {
    @Test fun uiCanInitializeBeforeTheVpnService() {
        var received: Any? = Any()
        val setup = CoreSetupCoordinator<Any, String> { _, platform -> received = platform }
        setup.foreground("UI")
        assertNull(received)
    }

    @Test fun openingUiAfterBackgroundStartPreservesTheVpnBridge() {
        val nativePlatform = Any()
        var received: Any? = null
        val setup = CoreSetupCoordinator<Any, String> { _, platform -> received = platform }
        setup.background("VPN", nativePlatform)
        setup.foreground("UI")
        assertSame(nativePlatform, received)
        setup.foreground("UI resume")
        assertSame(nativePlatform, received)
    }

    @Test fun anOldServiceCannotClearItsReplacement() {
        val oldPlatform = Any()
        val newPlatform = Any()
        var received: Any? = null
        val setup = CoreSetupCoordinator<Any, String> { _, platform -> received = platform }
        setup.background("old VPN", oldPlatform)
        setup.background("new VPN", newPlatform)
        setup.clear(oldPlatform)
        setup.foreground("UI")
        assertSame(newPlatform, received)
        setup.clear(newPlatform)
        setup.foreground("UI after stop")
        assertNull(received)
    }

    @Test fun failedReplacementKeepsTheWorkingBridge() {
        val working = Any()
        var received: Any? = null
        val setup = CoreSetupCoordinator<Any, String> { options, platform ->
            if (options == "failing VPN") throw IllegalStateException("setup failed")
            received = platform
        }
        setup.background("VPN", working)
        try {
            setup.background("failing VPN", Any())
        } catch (_: IllegalStateException) { }
        setup.foreground("UI")
        assertSame(working, received)
    }
}
