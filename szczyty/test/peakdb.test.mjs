import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { fileURLToPath } from "node:url";
import { encodeDb } from "../tools/encode.mjs";
import {
  parseHeader, parseIndex, indexLength, tilesInRange, decodeTile, loadPeaksNear, utf8Decode, formatDbDate, HEADER_SIZE,
} from "../utils/peakdb.js";
import {
  parseEle, pickName, normalizePeaks, computeIsolation, keepPeak, selectPeaks, distanceToPolygonKm, POLAND,
} from "../tools/peaks-lib.mjs";
import { distance } from "../utils/geo.js";

const GRID = { lat0: 48, lon0: 13, size: 0.5, rows: 16, cols: 26 };
const reader = (bin) => (pos, len) => bin.subarray(pos, pos + len);

const SAMPLE = [
  { name: "Rysy", lat: 49.1795, lon: 20.0881, ele: 2499, rank: 230 },
  { name: "Gerlachovský štít", lat: 49.1641, lon: 20.1338, ele: 2655, rank: 255 },
  { name: "Śnieżka", lat: 50.7360, lon: 15.7398, ele: 1603, rank: 250 },
  { name: "Babia Góra", lat: 49.5731, lon: 19.5292, ele: 1725, rank: 240 },
  { name: "Говерла 😀", lat: 48.16, lon: 24.5, ele: 2061, rank: 1 },
  { name: "poza siatką", lat: 60, lon: 10, ele: 100, rank: 0 },
];

test("UTF-8: polskie, słowackie, cyrylica i 4-bajtowe znaki", () => {
  const s = "Śnieżka · Lomnický štít · Говерла · 😀";
  const b = new TextEncoder().encode(s);
  assert.equal(utf8Decode(b, 0, b.length), s);
});

test("koder i dekoder: te same szczyty, dokładność ~1 m", () => {
  const bin = encodeDb(SAMPLE, GRID, 20261020);
  const h = parseHeader(bin);
  assert.equal(h.count, 5, "szczyt poza siatką pominięty");
  assert.equal(h.date, 20261020);
  assert.equal(formatDbDate(h.date), "20.10.2026");
  assert.deepEqual([h.lat0, h.lon0, h.size, h.rows, h.cols], [48, 13, 0.5, 16, 26]);
  const off = parseIndex(h, bin.subarray(h.indexAt, h.indexAt + indexLength(h)));
  assert.equal(off[off.length - 1], bin.length);
  const all = [];
  for (let t = 0; t < h.rows * h.cols; t++) decodeTile(h, t, bin.subarray(off[t], off[t + 1]), all);
  assert.equal(all.length, 5);
  for (const p of SAMPLE.slice(0, 5)) {
    const q = all.find((x) => x.name === p.name);
    assert.ok(q, p.name);
    assert.equal(q.ele, p.ele);
    assert.equal(q.rank, p.rank);
    assert.ok(distance(p.lat, p.lon, q.lat, q.lon) < 2, p.name + " przesunięty");
  }
});

test("wczytanie tylko kafli w zasięgu", () => {
  const bin = encodeDb(SAMPLE, GRID, 20261020);
  const h = parseHeader(bin);
  // z Zakopanego 100 km: Tatry i Babia, bez Śnieżki
  const tiles = tilesInRange(h, 49.3, 19.95, 100);
  assert.ok(tiles.length >= 12 && tiles.length <= 40, "kafli: " + tiles.length);
  const res = loadPeaksNear(reader(bin), 49.3, 19.95, 100);
  const names = res.peaks.map((p) => p.name).sort();
  assert.deepEqual(names, ["Babia Góra", "Gerlachovský štít", "Rysy"]);
  assert.equal(loadPeaksNear(reader(new Uint8Array(HEADER_SIZE)), 49, 19, 50), null, "obcy plik");
});

test("wysokość z tagu ele", () => {
  assert.equal(parseEle("1725"), 1725);
  assert.equal(parseEle("1725 m"), 1725);
  assert.equal(parseEle("1 725,3"), 1725.3);
  assert.equal(Math.round(parseEle("5000 ft")), 1524);
  assert.ok(Number.isNaN(parseEle("brak")));
  assert.ok(Number.isNaN(parseEle("12000")));
  assert.equal(pickName({ name: "Lomnický štít", "name:pl": "Łomnica" }), "Łomnica");
  assert.equal(pickName({ name: "Lomnický  štít" }, ""), "Lomnický štít");
  assert.equal(pickName({ name: "Говерла" }), "Howerla");
  assert.equal(pickName({ name: "Пікуй" }), "Pikuj");
  assert.equal(pickName({ name: "Кам’янка" }), "Kamjanka");
  assert.equal(pickName({ name: "Щавник" }), "Szczawnyk");
  assert.equal(pickName({ name: "Vetrová skala/Вітрова-Скала" }), "Vetrová skala");
  assert.equal(pickName({ name: "Стинка", "name:sk": "Stinská" }), "Stinská");
  assert.equal(pickName({ name: "Пікуй", "name:pl": "Pikuj" }), "Pikuj");
});

test("izolacja: odległość do najbliższego wyższego", () => {
  const peaks = [
    { name: "A", lat: 49.0, lon: 20.0, ele: 1000 },
    { name: "B", lat: 49.01, lon: 20.0, ele: 900 }, // 1,1 km od A
    { name: "C", lat: 49.2, lon: 20.0, ele: 950 }, // 22 km od A
  ];
  computeIsolation(peaks, 50);
  assert.equal(peaks[0].iso, 50, "najwyższy - limit");
  assert.ok(Math.abs(peaks[1].iso - 1.11) < 0.02);
  assert.ok(Math.abs(peaks[2].iso - 22.2) < 0.2);
});

test("izolacja: remis kilku metrów wygrywa szczyt z Wikipedii", () => {
  const peaks = [
    { name: "Łysica", lat: 50.8916, lon: 20.8966, ele: 613, wiki: true },
    { name: "Agata", lat: 50.8891, lon: 20.9059, ele: 614, wiki: false },
  ];
  computeIsolation(peaks, 50);
  assert.equal(peaks[0].iso, 50);
  assert.ok(peaks[1].iso < 1);
});

test("filtr: wyraźne szczyty zostają, garby i bez nazwy odpadają", () => {
  assert.equal(keepPeak({ name: "X", ele: 2000, iso: 1 }), true);
  assert.equal(keepPeak({ name: "X", ele: 2000, iso: 0.5 }), false);
  assert.equal(keepPeak({ name: "X", ele: 2000, iso: 0.5, wiki: true }), true);
  assert.equal(keepPeak({ name: "X", ele: 400, iso: 2 }), false);
  assert.equal(keepPeak({ name: "X", ele: 400, iso: 3.5 }), true);
  assert.equal(keepPeak({ name: "", ele: 2000, iso: 9 }), false);
  assert.equal(keepPeak({ name: "X", ele: 150, iso: 9 }), false);
  assert.equal(keepPeak({ name: "X", ele: 600, iso: 0.2, prominence: 150 }), true);
});

test("region: odległość od granicy Polski", () => {
  assert.equal(distanceToPolygonKm(52.23, 21.01, POLAND), 0, "Warszawa w środku");
  const ger = distanceToPolygonKm(49.164, 20.134, POLAND); // Gerlach - ok. 10-20 km od granicy
  assert.ok(ger > 3 && ger < 30, "Gerlach " + ger);
  assert.ok(distanceToPolygonKm(48.94, 19.59, POLAND) < 100, "Ďumbier w zasięgu");
  assert.ok(distanceToPolygonKm(47.07, 12.69, POLAND) > 300, "Grossglockner daleko");
});

test("selectPeaks: duplikaty i bez wysokości", () => {
  const els = [
    { type: "node", id: 1, lat: 49.1795, lon: 20.0881, tags: { natural: "peak", name: "Rysy", ele: "2499" } },
    { type: "node", id: 2, lat: 49.1797, lon: 20.0884, tags: { natural: "peak", name: "Rysy", ele: "2503" } },
    { type: "node", id: 3, lat: 49.2, lon: 20.1, tags: { natural: "peak", name: "Bez wysokości" } },
    { type: "node", id: 4, lat: 49.25, lon: 20.2, tags: { natural: "peak", ele: "2600" } },
  ];
  const out = selectPeaks(els);
  assert.deepEqual(out.map((p) => p.name), ["Rysy"]);
  assert.equal(normalizePeaks(els).length, 3, "bez nazwy zostaje do liczenia izolacji");
});

// Prawdziwa baza z assets (jeśli wygenerowana z pełnych danych)
const REAL = fileURLToPath(new URL("../assets/gt.r/peaks.bin", import.meta.url));
test("prawdziwa baza: znane szczyty na miejscu", { skip: !fs.existsSync(REAL) }, () => {
  const bin = new Uint8Array(fs.readFileSync(REAL));
  const h = parseHeader(bin);
  assert.ok(h.count > 2000 && h.count < 30000, "liczba szczytów " + h.count);
  assert.ok(bin.length < 600000, "rozmiar " + bin.length);
  const expect = [
    ["Rysy", 49.1795, 20.0881, 2499],
    ["Babia Góra", 49.5731, 19.5292, 1725],
    ["Śnieżka", 50.736, 15.7398, 1603],
    ["Tarnica", 49.0749, 22.7266, 1346],
    ["Łysica", 50.8925, 20.8992, 614],
    ["Ślęża", 50.865, 16.7087, 718],
  ];
  for (const [name, lat, lon, ele] of expect) {
    const res = loadPeaksNear(reader(bin), lat, lon, 3);
    const p = res.peaks.find((x) => x.name === name);
    assert.ok(p, "brak " + name);
    assert.ok(Math.abs(p.ele - ele) <= 5, name + " " + p.ele);
  }
  // najgęstsze miejsce: Tatry - ile szczytów wczytuje zegarek
  const tatry = loadPeaksNear(reader(bin), 49.23, 19.98, 106);
  assert.ok(tatry.peaks.length < 6000, "w zasięgu z Kasprowego: " + tatry.peaks.length);
});
