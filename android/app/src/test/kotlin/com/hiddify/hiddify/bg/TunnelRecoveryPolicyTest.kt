package com.hiddify.hiddify.bg

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TunnelRecoveryPolicyTest {
    @Test fun requiresTwoFailedRounds() {
        val policy = TunnelRecoveryPolicy()
        assertFalse(policy.record(false, 30_000))
        assertTrue(policy.record(false, 60_000))
    }

    @Test fun aHealthyRoundClearsFailures() {
        val policy = TunnelRecoveryPolicy()
        assertFalse(policy.record(false, 30_000))
        assertFalse(policy.record(true, 60_000))
        assertFalse(policy.record(false, 90_000))
        assertTrue(policy.record(false, 120_000))
    }

    @Test fun networkLossOrChangeClearsOldFailures() {
        val policy = TunnelRecoveryPolicy()
        assertFalse(policy.record(false, 30_000))
        policy.resetFailures()
        assertFalse(policy.record(false, 60_000))
        assertTrue(policy.record(false, 90_000))
    }

    @Test fun persistentFailureDoesNotCreateRestartLoop() {
        val policy = TunnelRecoveryPolicy()
        assertFalse(policy.record(false, 30_000))
        assertTrue(policy.record(false, 60_000))
        assertFalse(policy.record(false, 90_000))
        assertFalse(policy.record(false, 120_000))
        assertFalse(policy.record(false, 150_000))
        assertTrue(policy.record(false, 180_000))
    }

    @Test fun successDoesNotBypassRecoveryCooldown() {
        val policy = TunnelRecoveryPolicy()
        policy.record(false, 30_000)
        assertTrue(policy.record(false, 60_000))
        assertFalse(policy.record(true, 70_000))
        assertFalse(policy.record(false, 80_000))
        assertFalse(policy.record(false, 90_000))
        assertTrue(policy.record(false, 180_000))
    }
}
