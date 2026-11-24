package pl.grekot.trening

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

/**
 * Przypomnienia bez wtyczek: Dart wylicza listę (id, czas, kanał, tytuł, treść),
 * a tutaj każda pozycja to jeden alarm AlarmManagera. Alarmy są nieprecyzyjne
 * (setAndAllowWhileIdle): minuta różnicy przy przerwie nie ma znaczenia, a nie
 * trzeba uprawnienia do dokładnych alarmów. Lista leży w SharedPreferences, żeby
 * po restarcie telefonu albo aktualizacji aplikacji ustawić alarmy od nowa.
 */
object Przypomnienia {
    private const val PLIK = "przypomnienia"
    private const val LISTA = "lista"

    fun kanaly(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannels(
            listOf(
                NotificationChannel("trening", "Trening", NotificationManager.IMPORTANCE_DEFAULT)
                    .apply { description = "Przypomnienie o dzisiejszym treningu" },
                NotificationChannel("przerwy", "Przerwy w siedzeniu", NotificationManager.IMPORTANCE_DEFAULT)
                    .apply { description = "Wstań, przejdź się, zmień pozycję" },
                NotificationChannel("wyprosty", "Wyprosty", NotificationManager.IMPORTANCE_DEFAULT)
                    .apply { description = "Wyprosty w leżeniu co kilka godzin" },
            ),
        )
    }

    fun wlaczone(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return ctx.getSystemService(NotificationManager::class.java).areNotificationsEnabled()
    }

    /** Zastępuje wszystkie zaplanowane przypomnienia nową listą. */
    fun zaplanuj(ctx: Context, lista: List<Map<String, Any?>>) {
        val prefs = ctx.getSharedPreferences(PLIK, Context.MODE_PRIVATE)
        val am = ctx.getSystemService(AlarmManager::class.java)
        val stare = JSONArray(prefs.getString(LISTA, "[]"))
        for (i in 0 until stare.length()) {
            am.cancel(intencja(ctx, stare.getJSONObject(i)))
        }
        val nowe = JSONArray()
        for (m in lista) {
            nowe.put(
                JSONObject()
                    .put("id", (m["id"] as Number).toInt())
                    .put("czas", (m["czas"] as Number).toLong())
                    .put("kanal", m["kanal"] as String)
                    .put("tytul", m["tytul"] as String)
                    .put("tresc", m["tresc"] as String),
            )
        }
        prefs.edit().putString(LISTA, nowe.toString()).apply()
        ustaw(ctx, nowe)
    }

    /** Jedno przypomnienie poza listą (test). */
    fun jedno(ctx: Context, m: Map<String, Any?>) {
        val o = JSONObject()
            .put("id", (m["id"] as Number).toInt())
            .put("czas", (m["czas"] as Number).toLong())
            .put("kanal", m["kanal"] as String)
            .put("tytul", m["tytul"] as String)
            .put("tresc", m["tresc"] as String)
        ustaw(ctx, JSONArray().put(o))
    }

    /** Po restarcie telefonu albo aktualizacji aplikacji system zapomina alarmy. */
    fun przywroc(ctx: Context) {
        val prefs = ctx.getSharedPreferences(PLIK, Context.MODE_PRIVATE)
        ustaw(ctx, JSONArray(prefs.getString(LISTA, "[]")))
    }

    private fun ustaw(ctx: Context, lista: JSONArray) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        val teraz = System.currentTimeMillis()
        for (i in 0 until lista.length()) {
            val o = lista.getJSONObject(i)
            val czas = o.getLong("czas")
            if (czas <= teraz) continue
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, czas, intencja(ctx, o))
        }
    }

    // Alarm rozpoznaje się po klasie odbiorcy i requestCode (= id); dodatki są tylko treścią.
    private fun intencja(ctx: Context, o: JSONObject): PendingIntent {
        val id = o.getInt("id")
        val i = Intent(ctx, PrzypomnienieOdbiorca::class.java)
            .putExtra("id", id)
            .putExtra("kanal", o.optString("kanal", "trening"))
            .putExtra("tytul", o.optString("tytul"))
            .putExtra("tresc", o.optString("tresc"))
        return PendingIntent.getBroadcast(
            ctx,
            id,
            i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun pokaz(ctx: Context, id: Int, kanal: String, tytul: String, tresc: String) {
        if (!wlaczone(ctx)) return
        kanaly(ctx)
        val otworz = PendingIntent.getActivity(
            ctx,
            0,
            Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val n = Notification.Builder(ctx, kanal)
            .setSmallIcon(R.drawable.ic_powiadomienie)
            .setColor(0xFF1E88A8.toInt())
            .setContentTitle(tytul)
            .setContentText(tresc)
            .setStyle(Notification.BigTextStyle().bigText(tresc))
            .setCategory(Notification.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(otworz)
            .build()
        try {
            ctx.getSystemService(NotificationManager::class.java).notify(id, n)
        } catch (e: SecurityException) {
            // zgoda cofnięta w międzyczasie
        }
    }
}

/** Alarm przyszedł: pokaż powiadomienie (Zepp przekaże je na zegarek). */
class PrzypomnienieOdbiorca : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        Przypomnienia.pokaz(
            ctx,
            intent.getIntExtra("id", 0),
            intent.getStringExtra("kanal") ?: "trening",
            intent.getStringExtra("tytul") ?: "Trening",
            intent.getStringExtra("tresc") ?: "",
        )
    }
}

/** Restart telefonu albo aktualizacja aplikacji: ustaw alarmy od nowa. */
class StartOdbiorca : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> Przypomnienia.przywroc(ctx)
        }
    }
}
