package com.hiddify.hiddify.bg

/** Two failed rounds, each with independent HTTPS targets, precede recovery. */
internal class TunnelRecoveryPolicy(
    private val failuresRequired: Int = 2,
    private val cooldownMillis: Long = 120_000L,
) {
    private var failures = 0
    private var lastRecovery: Long? = null

    fun resetFailures() {
        failures = 0
    }

    fun record(healthy: Boolean, nowMillis: Long): Boolean {
        if (healthy) {
            resetFailures()
            return false
        }
        failures++
        if (failures < failuresRequired) return false
        val previous = lastRecovery
        if (previous != null && nowMillis - previous < cooldownMillis) return false
        resetFailures()
        lastRecovery = nowMillis
        return true
    }
}
