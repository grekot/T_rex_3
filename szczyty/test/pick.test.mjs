import test from "node:test";
import assert from "node:assert/strict";
import { buildCandidates, pickPeak, stripPeaks, PICK } from "../utils/pick.js";
import { screenModel } from "../utils/view.js";

// Obserwator na Turbaczu (Gorce), 1310 m
const OBS = { lat: 49.5431, lon: 20.1117, ele: 1310 };
const P = (name, lat, lon, ele, rank = 120) => ({ name, lat, lon, ele, rank });
const PEAKS = [
  P("Babia Góra", 49.5731, 19.5292, 1725, 200), // ~42 km, Zach (~275°)
  P("Gerlach", 49.1639, 20.1339, 2655, 230), // ~42 km, Pd (~178°)
  P("Rysy", 49.1794, 20.0881, 2499, 220), // ~40 km, Pd (~183°)
  P("Lubań", 49.4889, 20.3433, 1211, 150), // ~18 km, Pd-Wsch
  P("Mogielica", 49.6553, 20.2764, 1170, 160), // ~17 km, Pn-Wsch
  P("Pilsko", 49.5289, 19.3197, 1557, 180), // ~57 km, Zach, tuż obok Babiej (zasłonięte?)
  P("Pagórek", 49.5447, 20.0500, 700, 10), // blisko, niski, na zachód
  P("Turbacz", 49.5431, 20.1117, 1310, 200), // tu stoimy - pomijany
  P("Śnieżka", 50.736, 15.74, 1603, 255), // daleko poza zasięgiem
];

const cands = buildCandidates(PEAKS, OBS);
const byName = (n) => cands.find((c) => c.name === n);

test("kandydaci: w zasięgu, bez szczytu pod nogami, posortowani wg kierunku", () => {
  assert.ok(!byName("Turbacz"), "szczyt, na którym stoisz");
  assert.ok(!byName("Śnieżka"), "poza 100 km");
  assert.ok(byName("Babia Góra") && byName("Gerlach"));
  for (let i = 1; i < cands.length; i++) assert.ok(cands[i].b >= cands[i - 1].b);
  assert.ok(byName("Lubań").elev < 0, "Lubań jest niżej niż Turbacz");
  assert.ok(byName("Gerlach").elev > 1, "Gerlach wysoko nad horyzontem");
});

test("wskazanie prosto na szczyt", () => {
  const b = byName("Babia Góra").b;
  const r = pickPeak(cands, b + 2);
  assert.equal(r.best.name, "Babia Góra");
  assert.ok(Math.abs(r.offset + 2) < 1e-9, "2° w lewo");
});

test("przy podobnym kącie wygrywa wyższy w oczach (Gerlach/Rysy)", () => {
  const g = byName("Gerlach");
  const ry = byName("Rysy");
  const mid = (g.b + ry.b) / 2;
  assert.equal(pickPeak(cands, mid).best.name, "Gerlach");
  // ale wskazując dokładnie na Rysy dostajemy Rysy
  assert.equal(pickPeak(cands, ry.b + 0.3).best.name, "Rysy");
});

test("niski pagórek obok nie zabiera wyraźnego szczytu", () => {
  const pag = byName("Pagórek");
  assert.ok(pag, "pagórek jest w kandydatach");
  // pagórek leży prawie na zachód, Babia Góra też na zachód (kilka stopni dalej)
  const r = pickPeak(cands, pag.b);
  assert.ok(["Pagórek", "Babia Góra"].includes(r.best.name));
  const between = pickPeak(cands, (pag.b + byName("Babia Góra").b) / 2);
  assert.equal(between.best.name, "Babia Góra");
});

test("sąsiedzi po bokach i 'za nim'", () => {
  const r = pickPeak(cands, byName("Rysy").b);
  assert.equal(r.best.name, "Rysy");
  // patrząc na południe wschód jest po lewej: Gerlach ~5° w lewo, na prawo (do 60°) nic
  assert.equal(r.left.c.name, "Gerlach");
  assert.ok(r.left.off < -3 && r.left.off > -8);
  assert.equal(r.right, null);
  // patrząc na zachód: Babia Góra, Pilsko 6° w lewo (pagórek 2,5° w lewo to za blisko boku)
  const m = pickPeak(cands, byName("Babia Góra").b);
  assert.equal(m.best.name, "Babia Góra");
  assert.equal(m.left.c.name, "Pilsko");
  // Babia i Pilsko w prawie tym samym kierunku: Pilsko (dalej, niżej w oczach) jest "za nią"
  const pil = byName("Pilsko");
  const bab = byName("Babia Góra");
  if (Math.abs(pil.b - bab.b) < PICK.behindDeg) {
    assert.equal(pickPeak(cands, bab.b).behind.name, "Pilsko");
  }
});

test("brak szczytu w stożku", () => {
  // na północ od Turbacza w tej bazie nic nie ma (Mogielica jest na Pn-Wsch ~ 35°)
  const r = pickPeak(cands, 330);
  assert.equal(r.best, null);
  assert.ok(r.left || r.right);
});

test("zasłonięcie: daleki niższy szczyt za bliskim wyższym", () => {
  const obs = { lat: 50, lon: 20, ele: 300 };
  // bliski wysoki pagór (6° nad okiem) zasłania daleki szczyt w tym samym kierunku
  let list = buildCandidates([P("Bliski", 50.05, 20, 900), P("Daleki", 50.4, 20.003, 1000)], obs);
  const get = (n) => list.find((c) => c.name === n);
  assert.equal(get("Bliski").hidden, false);
  assert.equal(get("Daleki").hidden, true);
  let r = pickPeak(list, 0);
  assert.equal(r.best.name, "Bliski");
  assert.equal(r.behind.name, "Daleki", "pokazuje szczyt za nim");
  // niski bliski pagórek (1,5°) nie zasłania wysokiego dalekiego (2,4°) - ten wygrywa
  list = buildCandidates([P("Bliski", 50.05, 20, 450), P("Daleki", 50.4, 20.003, 1000), P("Wysoki", 50.45, 20.004, 2600)], obs);
  assert.equal(get("Daleki").hidden, true);
  assert.equal(get("Wysoki").hidden, false, "wystaje ponad bliski");
  r = pickPeak(list, 0);
  assert.equal(r.best.name, "Wysoki");
});

test("limit kandydatów zostawia najbardziej widoczne", () => {
  const many = [];
  for (let i = 0; i < 1000; i++) many.push(P("x" + i, 50 + (i % 40) * 0.01, 20 + Math.floor(i / 40) * 0.01, 300 + (i % 7), 0));
  many.push(P("Wielki", 50.3, 20.3, 1500, 255));
  // niski, ale jedyny szczyt na zachodzie nie może wypaść przez tłok na wschodzie
  many.push(P("Zachodni", 49.9, 19.5, 320, 0));
  const list = buildCandidates(many, { lat: 49.9, lon: 19.9, ele: 250 });
  assert.ok(list.length <= PICK.maxCandidates);
  assert.ok(list.some((c) => c.name === "Wielki"));
  assert.ok(list.some((c) => c.name === "Zachodni"), "wycinek bez konkurencji");
  const perSector = {};
  for (const c of list) perSector[Math.floor(c.b / PICK.sectorDeg)] = (perSector[Math.floor(c.b / PICK.sectorDeg)] || 0) + 1;
  assert.ok(Object.values(perSector).every((n) => n <= PICK.perSector));
});

test("pasek horyzontu: najwyżej stripMax, wybrany zaznaczony", () => {
  const s = stripPeaks(cands, byName("Rysy").b);
  assert.ok(s.length <= PICK.stripMax);
  assert.ok(s.every((x) => Math.abs(x.off) <= PICK.stripHalf));
});

test("model ekranu: wszystkie stany", () => {
  const now = new Date(2026, 9, 20, 15, 0).getTime();
  let m = screenModel({ pos: null, heading: null, cands: null, now });
  assert.equal(m.name, "Szukam GPS...");
  assert.equal(m.top, "kompas ?");
  m = screenModel({ pos: { lat: 1, lon: 1, t: now - 3600000, live: false }, heading: null, cands, now });
  assert.equal(m.name, "Kalibracja kompasu");
  assert.equal(m.status, "pozycja: dziś 14:00");
  const b = byName("Babia Góra").b;
  m = screenModel({ pos: { ...OBS, t: now, live: true }, ele: 1312.4, heading: b + 3, cands, now });
  assert.equal(m.name, "Babia Góra");
  assert.equal(m.details, "1725 m · 42 km");
  assert.match(m.hint, /^kierunek \d+° · 3° w lewo$/);
  assert.equal(m.status, "GPS · 1312 m n.p.m.");
  assert.ok(m.strip.some((s) => s.best));
  assert.ok(m.left || m.right);
  m = screenModel({ pos: { ...OBS, t: now, live: true }, heading: b, cands, now, frozen: true });
  assert.match(m.top, /^STOP \d+° Zach$/);
  m = screenModel({ pos: { ...OBS, t: now, live: true }, heading: 330, cands, now });
  assert.equal(m.name, "Brak szczytu");
  m = screenModel({ pos: { ...OBS, t: now, live: true }, heading: 10, cands: [], now });
  assert.equal(m.name, "Brak szczytów");
  m = screenModel({ pos: null, heading: 1, cands: null, now, noDb: true });
  assert.equal(m.name, "Brak bazy szczytów");
});

test("krótkie nazwy na boki ekranu", async () => {
  const { shortName } = await import("../utils/view.js");
  assert.equal(shortName("Einserkogel (Kleiner Rabenstein)"), "Einserkogel");
  assert.equal(shortName("Babia Góra"), "Babia Góra");
  assert.equal(shortName("Východná Vysoká veža"), "Východná Vyso.");
  assert.equal(shortName("(tylko nawias)"), "(tylko nawias)");
});
