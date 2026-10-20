// `node test/peaks.test.mjs` - sprawdzenie danych listy (liczba, współrzędne, warianty)
import assert from "node:assert/strict";
import { PEAKS, OFFICIAL, VARIANTS, findPeak } from "../utils/peaks.js";
import { distance } from "../utils/geo.js";
import { SUMMIT_RADIUS_M } from "../utils/korona.js";

assert.equal(OFFICIAL.length, 28, "Korona Gór Polski ma 28 szczytów");
assert.equal(new Set(PEAKS.map((p) => p.id)).size, PEAKS.length, "unikalne id");
assert.equal(new Set(OFFICIAL.map((p) => p.range)).size, 28, "po jednym szczycie na pasmo");

// Lista od najwyższego (Rysy) do najniższego (Łysica)
assert.equal(OFFICIAL[0].name, "Rysy");
assert.equal(OFFICIAL[27].name, "Łysica");
for (let i = 1; i < OFFICIAL.length; i++) {
  assert.ok(OFFICIAL[i - 1].h >= OFFICIAL[i].h, "kolejność wysokości: " + OFFICIAL[i].name);
}

// Wszystkie wierzchołki w Polsce lub na granicy (prostokąt z zapasem)
PEAKS.forEach((p) => {
  assert.ok(p.lat > 49.0 && p.lat < 51.1, p.name + " szerokość");
  assert.ok(p.lon > 15.0 && p.lon < 23.0, p.name + " długość");
  assert.ok(p.h > 500 && p.h < 2500, p.name + " wysokość");
  assert.ok(Number.isInteger(p.osm) && p.osm > 0, p.name + " węzeł OSM");
});

// Kilka znanych punktów kontrolnych (z map turystycznych) - zgodność z OSM do 300 m
const near = (id, lat, lon) => {
  const p = findPeak(id);
  const d = distance(p.lat, p.lon, lat, lon);
  assert.ok(d < 300, `${p.name}: ${Math.round(d)} m od punktu kontrolnego`);
};
near("rysy", 49.1795, 20.0881);
near("sniezka", 50.736, 15.7397);
near("babia", 49.573, 19.5293);
near("sleza", 50.8649, 16.7084);
near("tarnica", 49.0747, 22.7263);

// Warianty wskazują na szczyt z listy, z tego samego albo sąsiedniego pasma
VARIANTS.forEach((v) => {
  const main = findPeak(v.variantOf);
  assert.ok(main && !main.variantOf, v.name + " -> " + v.variantOf);
  assert.ok(distance(v.lat, v.lon, main.lat, main.lon) < 30000, v.name + " blisko " + main.name);
});

// Strefy „na szczycie” się nie nakładają (najbliższa para to Kłodzka Góra - Szeroka Góra)
let minPair = Infinity;
let pairName = "";
for (let i = 0; i < PEAKS.length; i++) {
  for (let j = i + 1; j < PEAKS.length; j++) {
    const d = distance(PEAKS[i].lat, PEAKS[i].lon, PEAKS[j].lat, PEAKS[j].lon);
    if (d < minPair) {
      minPair = d;
      pairName = PEAKS[i].name + " - " + PEAKS[j].name;
    }
  }
}
assert.ok(minPair > 2 * SUMMIT_RADIUS_M, "nakładające się strefy: " + pairName);
console.log("najbliższa para: " + pairName + " " + Math.round(minPair) + " m");

console.log("peaks.test.mjs: OK");
