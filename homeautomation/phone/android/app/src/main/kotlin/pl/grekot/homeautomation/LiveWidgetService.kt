package pl.grekot.homeautomation

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/// Stała usługa widżetów: osobny silnik Fluttera (`homeWidgetServiceMain`) trzyma połączenia z urządzeniami
/// i rysuje stan na żywo. Typ `specialUse`, bo `dataSync` Android 15 ucina po 6 godzinach na dobę.
class LiveWidgetService : Service() {
    companion object {
        const val ACTION_TAP = "pl.grekot.homeautomation.WIDGET_TAP"
        const val ACTION_RELOAD = "pl.grekot.homeautomation.WIDGET_RELOAD"
        const val EXTRA_ID = "id"
        const val EXTRA_INDEX = "index"
        private const val CHANNEL_ID = "live_widgets"
        private const val NOTIFICATION_ID = 0x57494447

        var instance: LiveWidgetService? = null
            private set

        /// Start, gdy są widżety. System może odmówić startu z tła - wtedy ruszy przy dotknięciu albo w aplikacji.
        fun ensure(context: Context, action: String? = null) {
            if (HomeWidgets.ids(context).isEmpty()) return
            val intent = Intent(context, LiveWidgetService::class.java).setAction(action)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: IllegalStateException) {
                // ForegroundServiceStartNotAllowedException - aplikacja w tle
            }
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var ready = false
    private val pending = ArrayDeque<Pair<Int, Int>>()

    private val screen = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            send(if (intent.action == Intent.ACTION_SCREEN_OFF) "pause" else "resume")
        }
    }

    private val network = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(n: Network) {
            main.post { send("network") }
        }

        override fun onLost(n: Network) {
            main.post { send("network") }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        goForeground()
        val e = FlutterEngine(applicationContext)
        val ch = MethodChannel(e.dartExecutor.binaryMessenger, "pl.grekot.homeautomation/widgets")
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "render" -> {
                    HomeWidgets.save(this, call.arguments as String)
                    result.success(null)
                }
                "widgetIds" -> result.success(HomeWidgets.ids(this).toList())
                "ready" -> {
                    ready = true
                    if (!getSystemService(PowerManager::class.java).isInteractive) send("pause")
                    while (pending.isNotEmpty()) {
                        val (id, index) = pending.removeFirst()
                        tap(id, index)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
        engine = e
        e.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(FlutterInjector.instance().flutterLoader().findAppBundlePath(), "homeWidgetServiceMain"),
        )
        registerReceiver(
            screen,
            IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
            },
        )
        getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(network)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Każde startForegroundService wymaga startForeground, także gdy usługa już działa.
        goForeground()
        if (HomeWidgets.ids(this).isEmpty()) {
            stopSelf()
            return START_NOT_STICKY
        }
        when (intent?.action) {
            ACTION_TAP -> tap(intent.getIntExtra(EXTRA_ID, 0), intent.getIntExtra(EXTRA_INDEX, 0))
            ACTION_RELOAD -> reload()
        }
        return START_STICKY
    }

    fun reload() = send("reload")

    private fun tap(id: Int, index: Int) {
        if (ready) {
            channel?.invokeMethod("tap", mapOf("id" to id, "index" to index))
        } else {
            pending.addLast(id to index)
        }
    }

    private fun send(method: String) {
        if (ready) channel?.invokeMethod(method, null)
    }

    private fun goForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Widżety na żywo", NotificationManager.IMPORTANCE_MIN)
            channel.description = "Stan urządzeń na widżetach ekranu telefonu"
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_widget_bulb)
            .setContentTitle("Widżety na żywo")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onDestroy() {
        instance = null
        unregisterReceiver(screen)
        getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(network)
        channel?.setMethodCallHandler(null)
        engine?.destroy()
        super.onDestroy()
    }
}
