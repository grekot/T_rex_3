package pl.grekot.mapychodzone

import btools.router.FormatJson
import btools.router.RoutingContext
import btools.router.RoutingEngine
import btools.router.RoutingParamCollector
import java.io.File

/**
 * Wyznaczanie tras offline przez BRouter (biblioteka Java, licencja MIT, libs/brouter-*-ro.jar).
 *
 * Dane:
 *  - segmenty: katalog z plikami *.rd5 (kwadraty 5×5°, np. E20_N45.rd5) z brouter.de,
 *  - profil: pełna ścieżka do pliku .brf; w tym samym katalogu musi leżeć lookups.dat.
 *
 * Wynik: GeoJSON z BRoutera (FeatureCollection z jedną linią [lon, lat, wysokość] i właściwościami
 * „track-length”, „filtered ascend”, „total-time”…), parsowany po stronie Darta.
 */
object Trasy {
    /**
     * @param punkty lista [lon, lat] w kolejności: start, punkty pośrednie, cel
     * @param parametry parametry profilu (np. hiking_routes_preference = „5” – trzymaj się szlaków)
     * @param czasMs limit czasu liczenia (0 = bez limitu)
     */
    fun oblicz(
        segmenty: String,
        profil: String,
        punkty: List<List<Double>>,
        parametry: Map<String, String>,
        czasMs: Long,
    ): String {
        require(punkty.size >= 2) { "Trasa potrzebuje co najmniej dwóch punktów" }
        require(File(profil).isFile) { "Brak profilu tras: $profil" }
        require(File(File(profil).parentFile, "lookups.dat").isFile) { "Brak lookups.dat obok profilu" }
        require(File(segmenty).isDirectory) { "Brak katalogu danych tras: $segmenty" }

        val zbieracz = RoutingParamCollector()
        val lonlaty = punkty.joinToString("|") { "${it[0]},${it[1]}" }
        val waypointy = zbieracz.getWayPointList(lonlaty)
        val kontekst = RoutingContext()
        kontekst.localFunction = profil
        // przed RoutingEngine: konstruktor czyta profil razem z tymi parametrami
        if (parametry.isNotEmpty()) zbieracz.setProfileParams(kontekst, parametry)

        val silnik = RoutingEngine(null, null, File(segmenty), waypointy, kontekst)
        silnik.quite = true
        silnik.doRun(czasMs)

        silnik.errorMessage?.let { throw IllegalStateException(it) }
        val slad = silnik.foundTrack ?: throw IllegalStateException("Nie znaleziono trasy")
        return FormatJson(kontekst).format(slad)
    }
}
