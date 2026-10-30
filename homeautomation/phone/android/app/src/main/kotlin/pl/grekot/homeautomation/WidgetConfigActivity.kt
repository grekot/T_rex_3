package pl.grekot.homeautomation

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Wybór treści widżetu przy dodawaniu na ekran (i „Zmień” na Androidzie 12+), we własnym punkcie wejścia Darta.
class WidgetConfigActivity : FlutterActivity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        // Wyjście bez zapisu nie dodaje widżetu.
        setResult(Activity.RESULT_CANCELED, resultIntent())
        super.onCreate(savedInstanceState)
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) finish()
    }

    override fun getDartEntrypointFunctionName() = "homeWidgetConfigMain"

    private fun resultIntent() = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pl.grekot.homeautomation/widget_config")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "args" -> {
                        val provider = AppWidgetManager.getInstance(this).getAppWidgetInfo(widgetId)?.provider
                        result.success(
                            mapOf("id" to widgetId, "multi" to (provider?.className == ListWidgetProvider::class.java.name)),
                        )
                    }
                    "done" -> {
                        HomeWidgets.draw(this, widgetId)
                        // Działająca usługa wczyta nową listę, a zatrzymana wczyta ją przy starcie.
                        LiveWidgetService.ensure(this, LiveWidgetService.ACTION_RELOAD)
                        setResult(Activity.RESULT_OK, resultIntent())
                        result.success(null)
                        finish()
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
