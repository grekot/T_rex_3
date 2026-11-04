package pl.grekot.homeautomation

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import org.json.JSONObject

/// Kafelki szybkich ustawień Androida „Dom 1-4” (pasek rozwijany z góry). Pozycję każdego ustawia aplikacja
/// (`QuickTilesScreen`) jako widżet o identyfikatorze -1…-4 - stan liczy i dotknięcia wykonuje ta sama usługa
/// widżetów ([LiveWidgetService]), a kafelek tylko rysuje ostatnią kratkę.
object QuickTiles {
    private const val PREFS = "quick_tiles"
    private const val KEY_ADDED = "added"
    const val SLOTS = 4

    /// Identyfikator „widżetu” kafelka [slot] (1-4) w usłudze widżetów.
    fun id(slot: Int) = -slot

    private fun service(slot: Int): Class<out TileService> = when (slot) {
        1 -> QsTile1::class.java
        2 -> QsTile2::class.java
        3 -> QsTile3::class.java
        else -> QsTile4::class.java
    }

    /// Kafelki dodane do szybkich ustawień (system woła onTileAdded / onTileRemoved).
    fun added(context: Context): Set<Int> =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet(KEY_ADDED, emptySet())!!
            .mapNotNull { it.toIntOrNull() }.toSet()

    fun setAdded(context: Context, slot: Int, on: Boolean) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val set = added(context).map { it.toString() }.toMutableSet()
        if (on) set.add(slot.toString()) else set.remove(slot.toString())
        prefs.edit().putStringSet(KEY_ADDED, set).apply()
    }

    /// Identyfikatory dodanych kafelków (-1…-4) - usługa widżetów działa także dla nich.
    fun addedIds(context: Context): IntArray = added(context).map { id(it) }.toIntArray()

    /// Wszystkie identyfikatory kafelków - ich ustawień usługa nie kasuje (kafelek może zostać dodany później).
    fun allIds(): List<Int> = (1..SLOTS).map { id(it) }

    /// Nowy stan z usługi - system odpyta kafelki ([TileService.onStartListening]).
    fun refresh(context: Context) {
        for (slot in 1..SLOTS) {
            try {
                TileService.requestListeningState(context, ComponentName(context, service(slot)))
            } catch (_: Exception) {
                // Kafelek nie jest dodany albo system nie pozwala - narysuje się przy otwarciu paska.
            }
        }
    }
}

/// Wspólna część kafelków „Dom 1-4”.
abstract class QsTileBase(private val slot: Int) : TileService() {
    override fun onTileAdded() {
        QuickTiles.setAdded(this, slot, true)
        LiveWidgetService.ensure(this, LiveWidgetService.ACTION_RELOAD)
        draw()
    }

    override fun onTileRemoved() {
        QuickTiles.setAdded(this, slot, false)
    }

    override fun onStartListening() {
        QuickTiles.setAdded(this, slot, true)
        draw()
        // Pasek otwarty - usługa odświeży stan (po zgaszonym ekranie była wstrzymana).
        LiveWidgetService.ensure(this)
    }

    private fun cell(): JSONObject? = HomeWidgets.cells(this, QuickTiles.id(slot))?.optJSONObject(0)

    private fun draw() {
        val tile = qsTile ?: return
        val c = cell()
        if (c == null) {
            tile.label = "Dom $slot"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) tile.subtitle = "Ustaw w aplikacji"
            tile.state = Tile.STATE_INACTIVE
            tile.icon = Icon.createWithResource(this, R.drawable.ic_widget_bulb)
        } else {
            tile.label = c.optString("title")
            val value = if (c.has("value")) c.optString("value") else null
            val subtitle = listOfNotNull(value, c.optString("subtitle").takeIf { it.isNotEmpty() }).joinToString(" · ")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) tile.subtitle = subtitle
            tile.state = when {
                c.optBoolean("dimmed") -> Tile.STATE_UNAVAILABLE
                c.optBoolean("active") -> Tile.STATE_ACTIVE
                else -> Tile.STATE_INACTIVE
            }
            val png = HomeWidgets.bitmap(c.optString("iconPng"))
            tile.icon = if (png != null) Icon.createWithBitmap(png) else Icon.createWithResource(this, HomeWidgets.icon(c.optString("icon")))
        }
        tile.updateTile()
    }

    override fun onClick() {
        val c = cell()
        val open = c?.optString("open")?.takeIf { it.isNotEmpty() }
        if (c == null || open != null) {
            // Bez ustawienia - aplikacja; termostat, czujnik, wykres - jego ekran.
            openApp(open)
            return
        }
        // Wyjście: od razu nowy stan na kafelku (usługa potwierdzi albo cofnie przy następnym rysowaniu).
        if (c.optString("icon") != "scene") {
            qsTile?.let {
                it.state = if (it.state == Tile.STATE_ACTIVE) Tile.STATE_INACTIVE else Tile.STATE_ACTIVE
                it.updateTile()
            }
        }
        val intent = Intent(this, LiveWidgetService::class.java)
            .setAction(LiveWidgetService.ACTION_TAP)
            .putExtra(LiveWidgetService.EXTRA_ID, QuickTiles.id(slot))
            .putExtra(LiveWidgetService.EXTRA_INDEX, 0)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
        } catch (_: Exception) {
            // System nie pozwolił uruchomić usługi z tła - otwieramy aplikację.
            openApp(null)
        }
    }

    private fun openApp(device: String?) {
        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (device != null) {
            intent.putExtra(MainActivity.EXTRA_OPEN_DEVICE, device).putExtra(MainActivity.EXTRA_OPEN_WIDGET, QuickTiles.id(slot))
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(
                PendingIntent.getActivity(this, slot, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE),
            )
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}

class QsTile1 : QsTileBase(1)

class QsTile2 : QsTileBase(2)

class QsTile3 : QsTileBase(3)

class QsTile4 : QsTileBase(4)
