// `node test/peaks.test.mjs` - sprawdzenie danych list (liczba, współrzędne, grupy, warianty)
import assert from "node:assert/strict";
import { PEAKS, GROUPS, MY_GROUP, findPeak, findGroup, groupPeaks, allPeaks, customPeaks } from "../utils/peaks.js";
import { distance } from "../utils/geo.js";
import { radiusOf, SUMMIT_RADIUS_M } from "../utils/korona.js";

const KGP = groupPeaks("kgp", null, true);
assert.equal(KGP.length, 28, "Korona Gór Polski ma 28 szczytów");
assert.equal(groupPeaks("kgp", null, false).length, 34, "+ 6 wariantów");
assert.equal(new Set(KGP.map((p) => p.range)).size, 28, "po jednym szczycie na pasmo");
assert.equal(KGP[0].name, "Rysy");
assert.equal(KGP[27].name, "Łysica");
assert.equal(new Set(PEAKS.map((p) => p.id)).size, PEAKS.length, "unikalne id");

// Listy pasm - liczby z generatora (data/peaks.json) i rozsądne minimum
assert.deepEqual(GROUPS.map((g) => g.id), ["kgp", "wyspowy", "sadecki", "gorce", "tatry", MY_GROUP]);
for (const g of GROUPS.filter((x) => x.id !== MY_GROUP)) {
  assert.equal(groupPeaks(g.id, null, true).length, g.counted, g.id + " counted");
}
assert.ok(groupPeaks("wyspowy").length > 120);
assert.ok(groupPeaks("sadecki").length > 120);
assert.ok(groupPeaks("gorce").length > 100);
assert.ok(groupPeaks("tatry").length > 150);

// Szczyty KGP leżące w pasmach należą do obu list (jedno zdobycie liczy się w obu)
const groupsOf = (id) => findPeak(id).groups.join("+");
assert.equal(groupsOf("rysy"), "kgp+tatry");
assert.equal(groupsOf("turbacz"), "kgp+gorce");
assert.equal(groupsOf("radziejowa"), "kgp+sadecki");
assert.equal(groupsOf("mogielica"), "kgp+wyspowy");
// Kilka znanych szczytów pasm
const named = (name, group) => PEAKS.find((p) => p.name === name && p.groups.includes(group));
for (const [name, group] of [
  ["Luboń Wielki", "wyspowy"], ["Ćwilin", "wyspowy"], ["Śnieżnica", "wyspowy"], ["Łopień", "wyspowy"],
  ["Jaworzyna Krynicka", "sadecki"], ["Prehyba", "sadecki"], ["Lubań", "gorce"], ["Gorc", "gorce"],
  ["Wielki Giewont", "tatry"], ["Kasprowy Wierch", "tatry"], ["Świnica", "tatry"], ["Kozi Wierch", "tatry"],
]) {
  assert.ok(named(name, group), name + " w " + group);
}

// Współrzędne w Polsce / na granicy, wysokości sensowne
PEAKS.forEach((p) => {
  assert.ok(p.lat > 49.0 && p.lat < 51.1 && p.lon > 15.0 && p.lon < 23.0, p.name + " poza Polską");
  assert.ok(p.h === 0 || (p.h > 250 && p.h < 2500), p.name + " wysokość " + p.h);
  assert.ok(p.name.length > 1 && !/\(/.test(p.name), "nazwa: " + p.name);
  assert.ok(radiusOf(p) >= 40 && radiusOf(p) <= SUMMIT_RADIUS_M, p.name + " promień");
});
// Rysy, Śnieżka w znanym miejscu (do 300 m)
const near = (id, lat, lon) => assert.ok(distance(findPeak(id).lat, findPeak(id).lon, lat, lon) < 300, id);
near("rysy", 49.1795, 20.0881);
near("sniezka", 50.736, 15.7397);
const giewont = named("Wielki Giewont", "tatry");
assert.ok(distance(giewont.lat, giewont.lon, 49.2508, 19.9339) < 300, "Giewont");

// Warianty wskazują na szczyt KGP
groupPeaks("kgp").filter((p) => p.variantOf).forEach((v) => {
  const main = findPeak(v.variantOf);
  assert.ok(main && !main.variantOf && main.groups.includes("kgp"), v.name);
});

// Strefy rozpoznania nakładają się tylko przy wierzchołkach bliżej niż 80 m (wtedy wygrywa bliższy)
for (let i = 0; i < PEAKS.length; i++) {
  for (let j = i + 1; j < PEAKS.length; j++) {
    const a = PEAKS[i];
    const b = PEAKS[j];
    const d = distance(a.lat, a.lon, b.lat, b.lon);
    if (d < radiusOf(a) + radiusOf(b)) assert.ok(d < 80, "strefy " + a.name + " / " + b.name + " " + Math.round(d) + " m");
  }
}

// Własne szczyty
const custom = { c1: { name: "Polana", lat: 49.6, lon: 20.1, d: "2025-05-01", gps: true } };
assert.equal(findPeak("c1", custom).name, "Polana");
assert.equal(findPeak("c1", null), null);
assert.equal(customPeaks(custom)[0].groups[0], MY_GROUP);
assert.equal(allPeaks(custom).length, PEAKS.length + 1);
assert.equal(allPeaks({}).length, PEAKS.length);
assert.equal(groupPeaks(MY_GROUP, custom).length, 1);
assert.equal(findGroup("tatry").name, "Tatry polskie");

console.log("peaks.test.mjs: OK (" + PEAKS.length + " szczytów)");
