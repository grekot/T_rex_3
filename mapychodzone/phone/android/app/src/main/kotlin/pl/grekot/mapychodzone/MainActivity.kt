package pl.grekot.mapychodzone

import android.Manifest
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Kanały do Androida bez dodatkowych wtyczek:
 *  - „pl.grekot.mapychodzone/urzadzenie”: prywatny katalog aplikacji, zgoda na lokalizację,
 *    ekran nie gaśnie,
 *  - „pl.grekot.mapychodzone/trasy”: wyznaczanie tras przez BRouter (Trasy.kt) w osobnym wątku.
 */
class MainActivity : FlutterActivity() {
    private var czekaNaZgode: MethodChannel.Result? = null
    private val watekTras = Executors.newSingleThreadExecutor()
    private val glowny = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val komunikator = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(komunikator, "pl.grekot.mapychodzone/urzadzenie").setMethodCallHandler { call, result ->
            when (call.method) {
                "katalog" -> result.success(filesDir.absolutePath)
                "maZgodeLokalizacji" -> result.success(maZgodeLokalizacji())
                "poprosOLokalizacje" -> {
                    if (maZgodeLokalizacji()) {
                        result.success(true)
                    } else {
                        czekaNaZgode?.success(false)
                        czekaNaZgode = result
                        requestPermissions(
                            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                            KOD_LOKALIZACJA,
                        )
                    }
                }
                "ekranWlaczony" -> {
                    if (call.arguments == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(komunikator, "pl.grekot.mapychodzone/trasy").setMethodCallHandler { call, result ->
            when (call.method) {
                "oblicz" -> {
                    val segmenty = call.argument<String>("segmenty")
                    val profil = call.argument<String>("profil")
                    val punkty = call.argument<List<List<Double>>>("punkty")
                    val czasMs = (call.argument<Int>("czasMs") ?: 60_000).toLong()
                    if (segmenty == null || profil == null || punkty == null) {
                        result.error("argumenty", "Brak segmentów, profilu albo punktów", null)
                        return@setMethodCallHandler
                    }
                    watekTras.execute {
                        try {
                            val geojson = Trasy.oblicz(segmenty, profil, punkty, czasMs)
                            glowny.post { result.success(geojson) }
                        } catch (e: Throwable) {
                            glowny.post { result.error("brouter", e.message ?: e.javaClass.simpleName, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun maZgodeLokalizacji(): Boolean =
        checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == KOD_LOKALIZACJA) {
            czekaNaZgode?.success(maZgodeLokalizacji())
            czekaNaZgode = null
        }
    }

    override fun onDestroy() {
        watekTras.shutdown()
        super.onDestroy()
    }

    private companion object {
        const val KOD_LOKALIZACJA = 41
    }
}
