package com.hiddify.hiddify.bg

import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.URL
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** Lives with the VPN service, independently of Flutter's foreground channel. */
internal class TunnelHealthMonitor(
    private val proxyPort: () -> Int,
    private val wanted: () -> Boolean,
    private val network: () -> Any?,
    private val elapsedMillis: () -> Long,
    private val recover: () -> Unit,
    private val log: (String, Exception?) -> Unit,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val generation = AtomicLong()
    private val connection = AtomicReference<HttpURLConnection?>()
    private var job: Job? = null

    fun start() {
        stop()
        val run = generation.get()
        job = scope.launch {
            val policy = TunnelRecoveryPolicy()
            var previousNetwork: Any? = null
            // Mobile.setup finishes before Flutter starts the actual tunnel.
            delay(30_000L)
            while (isActive && generation.get() == run) {
                try {
                    val currentNetwork = network()
                    if (!wanted() || currentNetwork == null) {
                        policy.resetFailures()
                    } else {
                        if (previousNetwork != currentNetwork) policy.resetFailures()
                        val healthy = probe(run)
                        // A result from the previous network/profile must not
                        // restart a tunnel the user just stopped or reloaded.
                        if (isActive && generation.get() == run && wanted() && network() == currentNetwork) {
                            if (policy.record(healthy, elapsedMillis())) {
                                log("VPN traffic checks failed; recovering the tunnel", null)
                                recover()
                            }
                        } else {
                            policy.resetFailures()
                        }
                    }
                    previousNetwork = currentNetwork
                } catch (e: Exception) {
                    if (isActive) log("VPN recovery check failed", e)
                }
                delay(30_000L)
            }
        }
    }

    fun stop() {
        generation.incrementAndGet()
        job?.cancel()
        job = null
        connection.getAndSet(null)?.disconnect()
    }

    private fun probe(run: Long): Boolean {
        val port = proxyPort()
        if (port !in 1..65535) return true // No mixed inbound configured.
        val proxy = Proxy(Proxy.Type.HTTP, InetSocketAddress("127.0.0.1", port))
        val targets = listOf(
            "https://www.gstatic.com/generate_204" to 204,
            "https://www.cloudflare.com/cdn-cgi/trace" to 200,
        )
        for ((target, expectedStatus) in targets) {
            if (generation.get() != run || !wanted()) return true
            val request = URL(target).openConnection(proxy) as HttpURLConnection
            connection.set(request)
            try {
                request.connectTimeout = 5_000
                request.readTimeout = 5_000
                request.instanceFollowRedirects = false
                request.useCaches = false
                request.setRequestProperty("Connection", "close")
                // Explicit proxy only: a direct fallback could hide a dead VPN.
                if (request.responseCode == expectedStatus) return true
            } catch (_: Exception) {
                // One unavailable target is insufficient to restart the VPN.
            } finally {
                connection.compareAndSet(request, null)
                request.disconnect()
            }
        }
        return false
    }
}
