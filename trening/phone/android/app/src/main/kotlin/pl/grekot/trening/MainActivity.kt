package pl.grekot.trening

import android.Manifest
import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Kanał „pl.grekot.trening/urzadzenie”: to, czego aplikacja potrzebuje od Androida,
 * bez dodatkowych wtyczek (każda wtyczka to kolejna zależność i uprawnienia):
 *  - katalog: prywatny folder aplikacji na stan.json,
 *  - ekranWlaczony: ekran nie gaśnie podczas treningu,
 *  - ton: krótki sygnał dźwiękowy (ToneGenerator, strumień multimediów),
 *  - wibracja,
 *  - przypomnienia (Przypomnienia.kt), zgoda na powiadomienia, bateria,
 *  - zadzwon: ekran wybierania numeru (bez uprawnienia do dzwonienia).
 */
class MainActivity : FlutterActivity() {
    private var ton: ToneGenerator? = null
    private var czekaNaZgode: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Przypomnienia.kanaly(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pl.grekot.trening/urzadzenie")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "katalog" -> result.success(filesDir.absolutePath)
                    "ekranWlaczony" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "ton" -> {
                        val ms = call.argument<Int>("ms") ?: 150
                        val rodzaj = when (call.argument<String>("typ")) {
                            "wysoki" -> ToneGenerator.TONE_PROP_BEEP2
                            "potwierdzenie" -> ToneGenerator.TONE_PROP_ACK
                            else -> ToneGenerator.TONE_PROP_BEEP
                        }
                        try {
                            val generator = ton ?: ToneGenerator(AudioManager.STREAM_MUSIC, 90).also { ton = it }
                            generator.startTone(rodzaj, ms)
                        } catch (e: RuntimeException) {
                            // brak dźwięku nie może przerwać treningu
                        }
                        result.success(null)
                    }
                    "wibracja" -> {
                        val ms = (call.argument<Int>("ms") ?: 100).toLong()
                        val wibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
                        } else {
                            @Suppress("DEPRECATION")
                            getSystemService(VIBRATOR_SERVICE) as Vibrator
                        }
                        wibrator.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
                        result.success(null)
                    }
                    "zaplanujPrzypomnienia" -> {
                        @Suppress("UNCHECKED_CAST")
                        Przypomnienia.zaplanuj(this, call.arguments as List<Map<String, Any?>>)
                        result.success(null)
                    }
                    "przypomnienieTestowe" -> {
                        @Suppress("UNCHECKED_CAST")
                        Przypomnienia.jedno(this, call.arguments as Map<String, Any?>)
                        result.success(null)
                    }
                    "powiadomieniaWlaczone" -> result.success(Przypomnienia.wlaczone(this))
                    "poprosOPowiadomienia" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            result.success(Przypomnienia.wlaczone(this))
                        } else {
                            czekaNaZgode?.success(false)
                            czekaNaZgode = result
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), ZGODA_POWIADOMIENIA)
                        }
                    }
                    "ustawieniaPowiadomien" -> otworz(
                        result,
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
                    )
                    "ustawieniaAplikacji" -> otworz(
                        result,
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)),
                    )
                    "bateriaBezOgraniczen" -> result.success(
                        (getSystemService(POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName),
                    )
                    "zwolnijZBaterii" -> otworz(result, zwolnienieZBaterii())
                    "zadzwon" -> otworz(result, Intent(Intent.ACTION_DIAL, Uri.parse("tel:${call.arguments}")))
                    else -> result.notImplemented()
                }
            }
    }

    // Aplikacja nie jest w Google Play; o zwolnienie z oszczędzania baterii pytamy wprost,
    // bo bez niego Samsung usypia przypomnienia (plan aplikacji, sekcja 6).
    @SuppressLint("BatteryLife")
    private fun zwolnienieZBaterii() =
        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))

    private fun otworz(result: MethodChannel.Result, intent: Intent) {
        try {
            startActivity(intent)
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("brak", e.message, null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == ZGODA_POWIADOMIENIA) {
            czekaNaZgode?.success(Przypomnienia.wlaczone(this))
            czekaNaZgode = null
        }
    }

    override fun onDestroy() {
        ton?.release()
        ton = null
        super.onDestroy()
    }

    private companion object {
        const val ZGODA_POWIADOMIENIA = 7
    }
}
