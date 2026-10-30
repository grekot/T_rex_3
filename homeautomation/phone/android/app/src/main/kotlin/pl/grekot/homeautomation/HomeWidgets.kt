package pl.grekot.homeautomation

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

/// Widżety na ekranie telefonu. Stan liczy Dart w usłudze [LiveWidgetService]; tu jest tylko rysowanie
/// z ostatniego stanu (zapisany, więc widżet przeżyje restart telefonu i usługi).
object HomeWidgets {
    private const val PREFS = "home_widget_render"
    private const val KEY = "cells"

    fun ids(context: Context): IntArray {
        val manager = AppWidgetManager.getInstance(context)
        return manager.getAppWidgetIds(ComponentName(context, TileWidgetProvider::class.java)) +
            manager.getAppWidgetIds(ComponentName(context, ListWidgetProvider::class.java))
    }

    /// Nowy stan z Darta: `{"<id widżetu>": [kratki]}`. Widżety spoza mapy zostają jak były.
    fun save(context: Context, json: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val all = JSONObject(prefs.getString(KEY, null) ?: "{}")
        val fresh = JSONObject(json)
        fresh.keys().forEach { all.put(it, fresh.get(it)) }
        prefs.edit().putString(KEY, all.toString()).apply()
        fresh.keys().forEach { key -> key.toIntOrNull()?.let { draw(context, it) } }
    }

    fun forget(context: Context, id: Int) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val all = JSONObject(prefs.getString(KEY, null) ?: "{}")
        all.remove(id.toString())
        prefs.edit().putString(KEY, all.toString()).apply()
    }

    fun draw(context: Context, id: Int) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val cells = JSONObject(prefs.getString(KEY, null) ?: "{}").optJSONArray(id.toString()) ?: placeholder()
        val root = RemoteViews(context.packageName, R.layout.widget_root)
        root.removeAllViews(R.id.widget_root)
        val columns = if (cells.length() <= 1) 1 else 2
        var row: RemoteViews? = null
        for (i in 0 until cells.length()) {
            if (i % columns == 0) {
                row?.let { root.addView(R.id.widget_root, it) }
                row = RemoteViews(context.packageName, R.layout.widget_row).apply { removeAllViews(R.id.widget_row) }
            }
            row?.addView(R.id.widget_row, cell(context, id, i, cells.getJSONObject(i)))
        }
        row?.let { root.addView(R.id.widget_root, it) }
        AppWidgetManager.getInstance(context).updateAppWidget(id, root)
    }

    private fun placeholder() = JSONArray().put(
        JSONObject().put("title", "HomeAutomation").put("subtitle", "Łączenie…").put("icon", "bulb").put("dimmed", true),
    )

    private fun cell(context: Context, id: Int, index: Int, c: JSONObject): RemoteViews {
        val active = c.optBoolean("active")
        val text = context.getColor(if (active) R.color.widget_on_active else R.color.widget_on_surface)
        val views = RemoteViews(context.packageName, R.layout.widget_cell)
        views.setTextViewText(R.id.widget_title, c.optString("title"))
        views.setTextViewText(R.id.widget_subtitle, c.optString("subtitle"))
        views.setTextColor(R.id.widget_title, text)
        views.setTextColor(R.id.widget_subtitle, text)
        views.setTextColor(R.id.widget_value, text)
        val value = if (c.has("value")) c.optString("value") else null
        views.setViewVisibility(R.id.widget_value, if (value == null) View.GONE else View.VISIBLE)
        views.setTextViewText(R.id.widget_value, value ?: "")
        views.setImageViewResource(R.id.widget_icon, icon(c.optString("icon")))
        views.setInt(R.id.widget_icon, "setColorFilter", text)
        views.setInt(
            R.id.widget_cell,
            "setBackgroundResource",
            if (active) R.drawable.widget_bg_active else R.drawable.widget_bg,
        )
        views.setFloat(R.id.widget_cell, "setAlpha", if (c.optBoolean("dimmed")) 0.6f else 1f)
        val open = if (c.has("open")) c.optString("open") else null
        views.setOnClickPendingIntent(
            R.id.widget_cell,
            if (open != null) openIntent(context, id, index, open) else tapIntent(context, id, index),
        )
        return views
    }

    private fun icon(name: String) = when (name) {
        "thermostat" -> R.drawable.ic_widget_thermostat
        "flame" -> R.drawable.ic_widget_flame
        "scene" -> R.drawable.ic_widget_scene
        "lock" -> R.drawable.ic_widget_lock
        else -> R.drawable.ic_widget_bulb
    }

    private fun tapIntent(context: Context, id: Int, index: Int): PendingIntent {
        val intent = Intent(context, LiveWidgetService::class.java)
            .setAction(LiveWidgetService.ACTION_TAP)
            .setData(Uri.parse("homeautomation://widget/$id/$index"))
            .putExtra(LiveWidgetService.EXTRA_ID, id)
            .putExtra(LiveWidgetService.EXTRA_INDEX, index)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(context, 0, intent, flags)
        } else {
            PendingIntent.getService(context, 0, intent, flags)
        }
    }

    private fun openIntent(context: Context, id: Int, index: Int, device: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(Uri.parse("homeautomation://open/$id/$index"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra(MainActivity.EXTRA_OPEN_DEVICE, device)
            .putExtra(MainActivity.EXTRA_OPEN_WIDGET, id)
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

/// Wspólna część dostawców: rysuje z zapisanego stanu i pilnuje usługi na żywo.
abstract class HomeWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { HomeWidgets.draw(context, it) }
        LiveWidgetService.ensure(context)
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        ids.forEach { HomeWidgets.forget(context, it) }
        LiveWidgetService.instance?.reload()
    }

    override fun onDisabled(context: Context) {
        if (HomeWidgets.ids(context).isEmpty()) LiveWidgetService.instance?.stopSelf()
    }
}

/// Jedna kratka.
class TileWidgetProvider : HomeWidgetProvider()

/// Kilka pozycji w jednym widżecie.
class ListWidgetProvider : HomeWidgetProvider()

/// Po restarcie telefonu albo aktualizacji aplikacji widżety znów są na żywo.
class WidgetBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        LiveWidgetService.ensure(context)
    }
}
