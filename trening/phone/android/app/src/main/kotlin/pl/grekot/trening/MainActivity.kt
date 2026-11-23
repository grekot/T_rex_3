package pl.grekot.trening

import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
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
 *  - wibracja.
 */
class MainActivity : FlutterActivity() {
    private var ton: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        ton?.release()
        ton = null
        super.onDestroy()
    }
}
