package pl.grekot.homeautomation

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Bundle
import android.os.PatternMatcher
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Kanał `pl.grekot.homeautomation/wifi`: łączenie z siecią konfiguracyjną urządzenia `HA_<id>`
/// (kontrakt pkt 9.4) bez internetu i kierowanie ruchu aplikacji przez nią (`bindProcessToNetwork`).
/// Kanał `pl.grekot.homeautomation/links`: otwarcie adresu w innej aplikacji (np. `ntfy://` - pkt 3d).
class MainActivity : FlutterActivity() {
    companion object {
        const val EXTRA_OPEN_DEVICE = "open_device"
        const val EXTRA_OPEN_WIDGET = "open_widget"
    }

    private var callback: ConnectivityManager.NetworkCallback? = null

    /// Urządzenie z dotkniętego widżetu termostatu, do odebrania z Darta (`widget_link`).
    private var openDevice: String? = null
    private var openWidget = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        takeWidgetIntent(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        takeWidgetIntent(intent)
    }

    private fun takeWidgetIntent(intent: Intent?) {
        openDevice = intent?.getStringExtra(EXTRA_OPEN_DEVICE) ?: return
        openWidget = intent.getIntExtra(EXTRA_OPEN_WIDGET, 0)
    }

    override fun onResume() {
        super.onResume()
        // Na ekranie start usługi jest zawsze dozwolony, nawet gdy po restarcie telefonu system go odmówił.
        LiveWidgetService.ensure(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pl.grekot.homeautomation/wifi")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "joinAp" -> joinAp(
                        call.argument<String>("ssid"),
                        call.argument<String>("prefix") ?: "HA_",
                        call.argument<String>("passphrase") ?: "",
                        result,
                    )
                    "releaseAp" -> {
                        releaseAp()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pl.grekot.homeautomation/links")
            .setMethodCallHandler { call, result ->
                if (call.method != "open") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val url = call.argument<String>("url")
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                } catch (_: ActivityNotFoundException) {
                    result.success(false)
                } catch (_: Exception) {
                    result.success(false)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pl.grekot.homeautomation/widget_link")
            .setMethodCallHandler { call, result ->
                if (call.method != "take") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val device = openDevice
                openDevice = null
                result.success(device?.let { mapOf("device" to it, "widget" to openWidget) })
            }
    }

    private fun joinAp(ssid: String?, prefix: String, passphrase: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("unsupported", "WifiNetworkSpecifier wymaga Androida 10", null)
            return
        }
        releaseAp()
        val specifier = WifiNetworkSpecifier.Builder().apply {
            // Bez znanej nazwy system pokazuje okno z sieciami HA_* do wyboru.
            if (ssid != null) setSsid(ssid) else setSsidPattern(PatternMatcher(prefix, PatternMatcher.PATTERN_PREFIX))
            setWpa2Passphrase(passphrase)
        }.build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()
        val cm = getSystemService(ConnectivityManager::class.java)
        var answered = false
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                cm.bindProcessToNetwork(network)
                runOnUiThread {
                    if (!answered) {
                        answered = true
                        result.success(null)
                    }
                }
            }

            override fun onUnavailable() {
                runOnUiThread {
                    if (!answered) {
                        answered = true
                        result.error("unavailable", "Sieć urządzenia niedostępna", null)
                    }
                }
            }
        }
        callback = cb
        cm.requestNetwork(request, cb, 60_000)
    }

    private fun releaseAp() {
        val cm = getSystemService(ConnectivityManager::class.java)
        cm.bindProcessToNetwork(null)
        callback?.let {
            try {
                cm.unregisterNetworkCallback(it)
            } catch (_: Exception) {
                // już wyrejestrowany
            }
        }
        callback = null
    }

    override fun onDestroy() {
        releaseAp()
        super.onDestroy()
    }
}
