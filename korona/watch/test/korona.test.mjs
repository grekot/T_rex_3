// `node test/korona.test.mjs` - rozpoznanie szczytu, najbliższe, postęp, daty, własne szczyty
import assert from "node:assert/strict";
import { findPeak, PEAKS, MY_GROUP } from "../utils/peaks.js";
import { distance, bearing, formatDistance, cardinal } from "../utils/geo.js";
import {
  SUMMIT_RADIUS_M,
  LEAVE_EXTRA_M,
  radiusOf,
  dateKey,
  todayKey,
  parseKey,
  formatDate,
  daysInMonth,
  clampDate,
  stepDate,
  normalizeClimbs,
  normalizeCustom,
  addClimb,
  removeClimb,
  climbOf,
  newCustomId,
  autoName,
  progress,
  totalClimbed,
  groupRows,
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
assert.deepEqual(stepDate({ y: 2026, m: 5, d: 1 }, "y", -10, NOW), { y: 2016, m: 5, d: 1 }, "rok o 10");

// --- zdobycia ---
let climbs = {};
climbs = addClimb(climbs, "rysy", "2024-07-15", true);
climbs = addClimb(climbs, "sleza", "2019-04-01", false);
climbs = addClimb(climbs, "borowa", "2023-08-08", true); // wariant - nie liczy się do 28
climbs = addClimb(climbs, "nie-ma", "2023-08-08", true); // nieznany szczyt - ignorowany
climbs = addClimb(climbs, "turbacz", "zła data", true);
assert.deepEqual(Object.keys(climbs).sort(), ["borowa", "rysy", "sleza"]);
assert.deepEqual(progress("kgp", climbs, {}), { done: 2, total: 28, complete: false });
// Rysy liczą się także w Tatrach
const tatry = progress("tatry", climbs, {});
assert.equal(tatry.done, 1);
assert.ok(tatry.total > 150);
assert.equal(progress("gorce", climbs, {}).done, 0);
climbs = removeClimb(climbs, "sleza");
assert.equal(progress("kgp", climbs, {}).done, 1);
assert.deepEqual(
  normalizeClimbs({ rysy: { d: "2024-07-15", gps: 1 }, x: { d: "2024-01-01" }, sleza: { d: "?" } }),
  { rysy: { d: "2024-07-15", gps: true } }
);
assert.deepEqual(normalizeClimbs(null), {});

// --- własne szczyty ---
const custom = normalizeCustom({
  c100: { name: "Polana pod lasem", lat: 49.7, lon: 20.2, d: "2025-06-01", gps: true },
  c101: { name: "Szczyt 2", lat: 49.71, lon: 20.21, d: "2025-07-01" },
  c103: { name: "  ", lat: 49.7, lon: 20.2, d: "2025-06-01" }, // pusta nazwa
  x5: { name: "zły id", lat: 1, lon: 1, d: "2025-06-01" },
  c102: { name: "bez daty", lat: 1, lon: 1 },
});
assert.deepEqual(Object.keys(custom).sort(), ["c100", "c101"]);
assert.deepEqual(progress(MY_GROUP, climbs, custom), { done: 2, total: 2, complete: false });
assert.equal(totalClimbed(climbs, custom), 2 + 2);
assert.deepEqual(climbOf("c100", climbs, custom), { d: "2025-06-01", gps: true });
assert.deepEqual(climbOf("rysy", climbs, custom), { d: "2024-07-15", gps: true });
assert.equal(climbOf("tarnica", climbs, custom), null);
assert.equal(newCustomId(1000, {}), "c1000");
assert.equal(newCustomId(1000, { c1000: {} }), "c1001");
assert.equal(autoName(custom), "Szczyt 3");
assert.equal(autoName({}), "Szczyt 1");

// --- wiersze listy: zdobyte (najnowsze), niezdobyte (najwyższe), warianty na końcu ---
let rows = groupRows("kgp", { sleza: { d: "2019-04-01" }, rysy: { d: "2024-07-15" } }, {});
assert.equal(rows.length, 34);
assert.deepEqual(rows.slice(0, 3).map((r) => r.peak.id), ["rysy", "sleza", "babia"]);
assert.ok(rows.slice(-6).every((r) => r.peak.variantOf));
rows = groupRows(MY_GROUP, climbs, custom);
assert.deepEqual(rows.map((r) => r.peak.id), ["c101", "c100"]);
rows = groupRows("tatry", {}, {});
assert.equal(rows[0].peak.id, "rysy", "najwyższy polski szczyt pierwszy");

// --- rozpoznanie szczytu ---
const rysy = findPeak("rysy");
assert.ok(radiusOf(rysy) <= SUMMIT_RADIUS_M);
assert.equal(summitAt(rysy, PEAKS).peak.id, "rysy");
assert.equal(summitAt(north(rysy, radiusOf(rysy) - 10), PEAKS).peak.id, "rysy");
assert.equal(summitAt(north(rysy, radiusOf(rysy) + 20), PEAKS), null);
assert.equal(summitAt(null, PEAKS), null);
const mog = findPeak("mogielica");
assert.equal(summitAt(north(mog, 100), PEAKS).peak.id, "mogielica", "płaski szczyt - 100 m wystarcza");
assert.equal(summitAt(findPeak("klodzka"), PEAKS).peak.id, "klodzka");
assert.equal(summitAt(findPeak("szeroka"), PEAKS).peak.id, "szeroka");
assert.equal(summitAt(findPeak("agata"), PEAKS).peak.id, "agata");
// każdy szczyt rozpoznaje sam siebie (bliźniacze wierzchołki < 80 m: wygrywa bliższy, czyli on sam)
PEAKS.forEach((p) => assert.equal(summitAt(p, PEAKS).peak.id, p.id, p.name));
// własny szczyt też jest rozpoznawany
const withMine = PEAKS.concat([{ id: "c1", name: "Mój", lat: 49.9, lon: 20.9, r: 0, groups: [MY_GROUP] }]);
assert.equal(summitAt({ lat: 49.9, lon: 20.9 }, withMine).peak.id, "c1");

// Strażnik z histerezą: 2 odczyty, by wejść; wyjście dopiero za promień + LEAVE_EXTRA_M
const R1 = radiusOf(mog);
const w = createSummitWatcher();
assert.deepEqual(w.update(north(mog, 500), PEAKS), { peak: null, entered: false });
assert.deepEqual(w.update(north(mog, 50), PEAKS), { peak: null, entered: false }, "jeden odczyt to za mało");
let r = w.update(north(mog, 30), PEAKS);
assert.equal(r.peak.id, "mogielica");
assert.equal(r.entered, true);
assert.equal(w.update(north(mog, 10), PEAKS).entered, false, "wibracja tylko raz");
assert.equal(w.update(north(mog, R1 + LEAVE_EXTRA_M - 20), PEAKS).peak.id, "mogielica", "histereza");
assert.equal(w.update(null, PEAKS).peak.id, "mogielica", "brak GPS nie zmienia stanu");
assert.equal(w.update(north(mog, R1 + LEAVE_EXTRA_M + 30), PEAKS).peak, null, "zejście");
assert.equal(w.current(), null);
// skok GPS: jeden odczyt na szczycie, potem daleko - bez rozpoznania
const w2 = createSummitWatcher();
w2.update(north(mog, 20), PEAKS);
assert.equal(w2.update(north(mog, 2000), PEAKS).peak, null);
assert.equal(w2.update(north(mog, 20), PEAKS).entered, false, "licznik wyzerowany po skoku");
// Grań: z jednego wierzchołka na sąsiedni (Tatry) - przełączenie po 2 odczytach
const a1 = PEAKS.find((p) => p.groups.includes("tatry") && p.r && p.r > 60 && p.r < 100);
const b1 = PEAKS.filter((p) => p !== a1).sort(
  (x, y) => distance(a1.lat, a1.lon, x.lat, x.lon) - distance(a1.lat, a1.lon, y.lat, y.lon)
)[0];
const w3 = createSummitWatcher();
w3.update(a1, PEAKS);
assert.equal(w3.update(a1, PEAKS).peak.id, a1.id);
assert.equal(w3.update(b1, PEAKS).peak.id, a1.id, "jeden odczyt na sąsiednim - jeszcze stary");
r = w3.update(b1, PEAKS);
assert.equal(r.peak.id, b1.id, a1.name + " -> " + b1.name);
assert.equal(r.entered, true);

// --- najbliższe niezdobyte ---
const sobotka = { lat: 50.898, lon: 16.744 };
let n = nearestUnclimbed(sobotka, {}, "kgp", 3);
assert.equal(n.length, 3);
assert.equal(n[0].peak.id, "sleza");
assert.ok(n[0].distance > 3000 && n[0].distance < 6000, "Sobótka-Ślęża ok. 4,5 km: " + n[0].distance);
assert.ok(n[0].distance <= n[1].distance && n[1].distance <= n[2].distance);
n = nearestUnclimbed(sobotka, { sleza: { d: "2020-01-01" } }, "kgp", 3);
assert.notEqual(n[0].peak.id, "sleza", "zdobyta pomijana");
assert.ok(n.every((x) => !x.peak.variantOf), "bez wariantów");
assert.deepEqual(nearestUnclimbed(null, {}, "kgp", 3), []);
assert.equal(nearestUnclimbed(sobotka, {}, "kgp").length, 28);
// Z Mszany Dolnej - najbliższe w Beskidzie Wyspowym; ze wszystkich list nie dalej
const mszana = { lat: 49.6747, lon: 20.0786 };
n = nearestUnclimbed(mszana, {}, "wyspowy", 5);
assert.ok(n.every((x) => x.peak.groups.includes("wyspowy")));
assert.ok(n[0].distance < 5000, "z Mszany Dolnej blisko do szczytu Wyspowego: " + n[0].distance);
assert.ok(nearestUnclimbed(mszana, {}, null, 1)[0].distance <= n[0].distance);

// Z Zakopanego Rysy są na południowy wschód, ok. 15-20 km
const zakopane = { lat: 49.2992, lon: 19.9496 };
const rd = distance(zakopane.lat, zakopane.lon, rysy.lat, rysy.lon);
assert.ok(rd > 14000 && rd < 20000, "Zakopane-Rysy " + rd);
assert.equal(cardinal(bearing(zakopane.lat, zakopane.lon, rysy.lat, rysy.lon)), "Pd-Wsch");
assert.equal(formatDistance(rd).endsWith(" km"), true);

// --- podpisy ---
assert.equal(peakLine(rysy), "2499 m · Tatry");
assert.equal(peakLine({ h: 0, range: "Gorce" }), "Gorce");
assert.equal(variantLine(findPeak("borowa")), "wariant dla: Chełmiec");
assert.equal(variantLine(rysy), "");

console.log("korona.test.mjs: OK");
