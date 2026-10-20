// `node test/korona.test.mjs` - rozpoznanie szczytu, najbliższe, postęp, daty
import assert from "node:assert/strict";
import { findPeak } from "../utils/peaks.js";
import { distance, bearing, formatDistance, cardinal } from "../utils/geo.js";
import {
  SUMMIT_RADIUS_M,
  LEAVE_RADIUS_M,
  dateKey,
  todayKey,
  parseKey,
  formatDate,
  daysInMonth,
  clampDate,
  stepDate,
  normalizeClimbs,
  addClimb,
  removeClimb,
  progress,
  listRows,
  summitAt,
  nearestUnclimbed,
  createSummitWatcher,
  peakLine,
  variantLine,
} from "../utils/korona.js";

// Punkt przesunięty o `m` metrów na północ od szczytu
const north = (p, m) => ({ lat: p.lat + m / 111195, lon: p.lon });

const NOW = new Date(2026, 9, 20, 12, 0, 0).getTime(); // 20.10.2026

// --- daty ---
assert.equal(dateKey(2024, 5, 2), "2024-05-02");
assert.equal(todayKey(NOW), "2026-10-20");
assert.deepEqual(parseKey("2024-05-02"), { y: 2024, m: 5, d: 2 });
assert.equal(parseKey("12.05.2024"), null);
assert.equal(parseKey(undefined), null);
assert.equal(formatDate("2024-05-02"), "02.05.2024");
assert.equal(formatDate("bzdura"), "");
assert.equal(daysInMonth(2024, 2), 29);
assert.equal(daysInMonth(2025, 2), 28);
assert.equal(daysInMonth(2025, 12), 31);
assert.deepEqual(clampDate(2027, 1, 1, NOW), { y: 2026, m: 1, d: 1 }, "rok z przyszłości -> bieżący");
assert.deepEqual(clampDate(2026, 12, 24, NOW), { y: 2026, m: 10, d: 20 }, "dzień z przyszłości -> dziś");
assert.deepEqual(clampDate(1900, 3, 31, NOW), { y: 1950, m: 3, d: 31 });
assert.deepEqual(clampDate(2025, 2, 31, NOW), { y: 2025, m: 2, d: 28 }, "31 lutego -> 28");
// wybierak daty
assert.deepEqual(stepDate({ y: 2025, m: 12, d: 31 }, "m", 1, NOW), { y: 2025, m: 1, d: 31 }, "miesiąc zawija się");
assert.deepEqual(stepDate({ y: 2025, m: 3, d: 31 }, "m", -1, NOW), { y: 2025, m: 2, d: 28 });
assert.deepEqual(stepDate({ y: 2025, m: 3, d: 1 }, "d", -1, NOW), { y: 2025, m: 3, d: 31 }, "dzień zawija się");
assert.deepEqual(stepDate({ y: 2024, m: 2, d: 29 }, "y", 1, NOW), { y: 2025, m: 2, d: 28 });
assert.deepEqual(stepDate({ y: 2026, m: 5, d: 1 }, "y", 1, NOW), { y: 2026, m: 5, d: 1 }, "nie w przyszłość");

// --- zdobycia ---
let climbs = {};
climbs = addClimb(climbs, "rysy", "2024-07-15", true);
climbs = addClimb(climbs, "sleza", "2019-04-01", false);
climbs = addClimb(climbs, "borowa", "2023-08-08", true); // wariant - nie liczy się
climbs = addClimb(climbs, "nie-ma", "2023-08-08", true); // nieznany szczyt - ignorowany
climbs = addClimb(climbs, "turbacz", "zła data", true);
assert.deepEqual(Object.keys(climbs).sort(), ["borowa", "rysy", "sleza"]);
assert.deepEqual(progress(climbs), { done: 2, total: 28, complete: false });
climbs = removeClimb(climbs, "sleza");
assert.equal(progress(climbs).done, 1);
assert.deepEqual(
  normalizeClimbs({ rysy: { d: "2024-07-15", gps: 1 }, x: { d: "2024-01-01" }, sleza: { d: "?" } }),
  { rysy: { d: "2024-07-15", gps: true } }
);
assert.deepEqual(normalizeClimbs(null), {});
const rows = listRows(climbs);
assert.equal(rows.length, 34);
assert.equal(rows[0].peak.id, "rysy");
assert.equal(rows[0].climb.d, "2024-07-15");
assert.equal(rows[1].climb, null);
const all = {};
listRows({}).forEach((r) => {
  if (!r.peak.variantOf) all[r.peak.id] = { d: "2020-01-01", gps: false };
});
assert.deepEqual(progress(all), { done: 28, total: 28, complete: true });

// --- rozpoznanie szczytu ---
const rysy = findPeak("rysy");
assert.equal(summitAt(rysy, SUMMIT_RADIUS_M).peak.id, "rysy");
assert.equal(summitAt(north(rysy, 100), SUMMIT_RADIUS_M).peak.id, "rysy");
assert.equal(summitAt(north(rysy, 140), SUMMIT_RADIUS_M), null);
assert.equal(summitAt(null, SUMMIT_RADIUS_M), null);
// Kłodzka Góra i Szeroka Góra - każda rozpoznana osobno
assert.equal(summitAt(findPeak("klodzka"), SUMMIT_RADIUS_M).peak.id, "klodzka");
assert.equal(summitAt(findPeak("szeroka"), SUMMIT_RADIUS_M).peak.id, "szeroka");
// Agata (wariant Łysicy) - rozpoznany wariant
assert.equal(summitAt(findPeak("agata"), SUMMIT_RADIUS_M).peak.id, "agata");

// Strażnik z histerezą: 2 odczyty, by wejść; wyjście dopiero za LEAVE_RADIUS_M
const w = createSummitWatcher();
assert.deepEqual(w.update(north(rysy, 500)), { peak: null, entered: false });
assert.deepEqual(w.update(north(rysy, 50)), { peak: null, entered: false }, "jeden odczyt to za mało");
let r = w.update(north(rysy, 30));
assert.equal(r.peak.id, "rysy");
assert.equal(r.entered, true);
r = w.update(north(rysy, 10));
assert.equal(r.entered, false, "wibracja tylko raz");
assert.equal(w.update(north(rysy, 170)).peak.id, "rysy", "histereza");
assert.equal(w.update(null).peak.id, "rysy", "brak GPS nie zmienia stanu");
assert.equal(w.update(north(rysy, LEAVE_RADIUS_M + 30)).peak, null, "zejście");
assert.equal(w.current(), null);
// skok GPS: jeden odczyt na szczycie, potem daleko - bez rozpoznania
const w2 = createSummitWatcher();
w2.update(north(rysy, 20));
assert.equal(w2.update(north(rysy, 2000)).peak, null);
assert.equal(w2.update(north(rysy, 20)).entered, false, "licznik wyzerowany po skoku");

// --- najbliższe niezdobyte ---
// Spod Ślęży (Sobótka): najbliżej Ślęża, potem coś w Sudetach
const sobotka = { lat: 50.898, lon: 16.744 };
let n = nearestUnclimbed(sobotka, {}, 3);
assert.equal(n.length, 3);
assert.equal(n[0].peak.id, "sleza");
assert.ok(n[0].distance > 3000 && n[0].distance < 6000, "Sobótka-Ślęża ok. 4,5 km: " + n[0].distance);
assert.ok(n[0].distance <= n[1].distance && n[1].distance <= n[2].distance);
n = nearestUnclimbed(sobotka, { sleza: { d: "2020-01-01" } }, 3);
assert.notEqual(n[0].peak.id, "sleza", "zdobyta pomijana");
assert.ok(n.every((x) => !x.peak.variantOf), "bez wariantów");
assert.deepEqual(nearestUnclimbed(null, {}, 3), []);
assert.equal(nearestUnclimbed(sobotka, {}).length, 28);

// Z Zakopanego Rysy są na południowy wschód, ok. 15-20 km
const zakopane = { lat: 49.2992, lon: 19.9496 };
const rd = distance(zakopane.lat, zakopane.lon, rysy.lat, rysy.lon);
assert.ok(rd > 14000 && rd < 20000, "Zakopane-Rysy " + rd);
assert.equal(cardinal(bearing(zakopane.lat, zakopane.lon, rysy.lat, rysy.lon)), "Pd-Wsch");
assert.equal(formatDistance(rd).endsWith(" km"), true);

// --- podpisy ---
assert.equal(peakLine(rysy), "2499 m · Tatry");
assert.equal(variantLine(findPeak("borowa")), "wariant dla: Chełmiec");
assert.equal(variantLine(rysy), "");

console.log("korona.test.mjs: OK");
