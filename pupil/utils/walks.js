// Wyzwania z kompasem, barometrem i GPS - czysta logika, testy w test/walks.test.mjs.
// Zadania spacerowe (wspinaczka, wyprawa, znaczenie terenu) zapisują się w stanie pupila
// (s.walks), więc aplikacja nie musi być włączona przez cały spacer: po otwarciu gry
// zegarek sprawdza, czy już się udało.
import { makeRng } from "./games.js";

const MIN = 60000;
const HOUR = 60 * MIN;
export const R = 6371000;
const toRad = (d) => (d * Math.PI) / 180;
const toDeg = (r) => (r * 180) / Math.PI;

export function normalize(deg) {
  const d = deg % 360;
  return d < 0 ? d + 360 : d;
}

// Różnica kątów ze znakiem w (-180, 180]: dodatnia = cel na prawo
export function angleDiff(target, from) {
  let d = normalize(target - from);
  if (d > 180) d -= 360;
  return d;
}

export function distance(lat1, lon1, lat2, lon2) {
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function bearing(lat1, lon1, lat2, lon2) {
  const y = Math.sin(toRad(lon2 - lon1)) * Math.cos(toRad(lat2));
  const x = Math.cos(toRad(lat1)) * Math.sin(toRad(lat2)) - Math.sin(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.cos(toRad(lon2 - lon1));
  return normalize(toDeg(Math.atan2(y, x)));
}

// Punkt w odległości dist (m) w kierunku brg (stopnie od północy)
export function destination(lat, lon, brg, dist) {
  const d = dist / R;
  const b = toRad(brg);
  const la = toRad(lat);
  const lo = toRad(lon);
  const la2 = Math.asin(Math.sin(la) * Math.cos(d) + Math.cos(la) * Math.sin(d) * Math.cos(b));
  const lo2 = lo + Math.atan2(Math.sin(b) * Math.sin(d) * Math.cos(la), Math.cos(d) - Math.sin(la) * Math.sin(la2));
  return { lat: toDeg(la2), lon: ((toDeg(lo2) + 540) % 360) - 180 };
}

export const DIRS8 = ["północ", "północny wschód", "wschód", "południowy wschód", "południe", "południowy zachód", "zachód", "północny zachód"];
export function dirName(deg) {
  return DIRS8[Math.round(normalize(deg) / 45) % 8];
}

// --- 16. Szukanie jedzenia (kompas) ------------------------------------------------

export const FORAGE = { foods: 3, time: 90000, tol: 15, hold: 1200 };

export function newForage(seed) {
  const rnd = makeRng(seed);
  const targets = [];
  for (let i = 0; i < FORAGE.foods; i++) {
    let b;
    do b = Math.round(rnd() * 360) % 360;
    while (i > 0 && Math.abs(angleDiff(b, targets[i - 1])) < 60);
    targets.push(b);
  }
  return { targets, found: 0, hold: 0, elapsed: 0, done: false, win: false, diff: null };
}

// heading = kierunek godziny 12 od północy albo null (kompas nieskalibrowany).
// Zwraca "found" | ""
export function forageStep(g, heading, dt) {
  if (g.done) return "";
  g.elapsed += dt;
  if (heading === null || heading === undefined) {
    g.diff = null;
    g.hold = 0;
  } else {
    g.diff = angleDiff(g.targets[g.found], heading);
    if (Math.abs(g.diff) <= FORAGE.tol) g.hold += dt;
    else g.hold = 0;
  }
  if (g.hold >= FORAGE.hold) {
    g.found++;
    g.hold = 0;
    if (g.found >= FORAGE.foods) {
      g.done = true;
      g.win = true;
    }
    return "found";
  }
  if (g.elapsed >= FORAGE.time) {
    g.done = true;
    g.win = false;
  }
  return "";
}

// Co ile ms wibrować: im bliżej celu, tym częściej ("ciepło, cieplej")
export function pulseEvery(diff) {
  if (diff === null || diff === undefined) return 0;
  return Math.round(250 + Math.abs(diff) * 9);
}

// --- 18. Wspinaczka (barometr, zadanie spacerowe) -------------------------------------

export const CLIMB = { need: 3, ttl: 6 * HOUR };

export function newClimb(alt, now) {
  return { alt0: alt, t0: now };
}

export function climbStatus(task, alt, now) {
  if (!task) return { state: "none" };
  if (now - task.t0 > CLIMB.ttl) return { state: "expired" };
  if (alt === null || alt === undefined) return { state: "wait", gain: null };
  const gain = Math.round((alt - task.alt0) * 10) / 10;
  return { state: gain >= CLIMB.need ? "done" : "climbing", gain };
}

// --- 20. Wyprawa (GPS, zadanie spacerowe) -----------------------------------------------

export const TRIP = { min: 200, max: 500, arrive: 25, ttl: 3 * HOUR };

export function newTrip(fix, now, seed) {
  const rnd = makeRng(seed);
  const brg = rnd() * 360;
  const dist = TRIP.min + rnd() * (TRIP.max - TRIP.min);
  const p = destination(fix.lat, fix.lon, brg, dist);
  return { lat: p.lat, lon: p.lon, t0: now, dist: Math.round(dist) };
}

export function tripStatus(task, fix, now) {
  if (!task) return { state: "none" };
  if (now - task.t0 > TRIP.ttl) return { state: "expired" };
  if (!fix) return { state: "wait" };
  const d = distance(fix.lat, fix.lon, task.lat, task.lon);
  return { state: d <= TRIP.arrive ? "done" : "walking", dist: Math.round(d), bearing: bearing(fix.lat, fix.lon, task.lat, task.lon) };
}

// --- 21. Znaczenie terenu (GPS, zadanie spacerowe) ----------------------------------------

export const MARKS = { need: 3, spacing: 100, ttl: 24 * HOUR };

export function marksStatus(task, now) {
  if (!task || now - task.t0 > MARKS.ttl) return { state: "none", count: 0 };
  return { state: task.list.length >= MARKS.need ? "done" : "marking", count: task.list.length };
}

// Zwraca { task, result: "added" | "near" (za blisko poprzedniego, m) | "done" }
export function addMark(task, fix, now) {
  let t = task && now - task.t0 <= MARKS.ttl ? { t0: task.t0, list: task.list.slice() } : { t0: now, list: [] };
  let nearest = Infinity;
  for (const m of t.list) nearest = Math.min(nearest, distance(fix.lat, fix.lon, m.lat, m.lon));
  if (nearest < MARKS.spacing) return { task: t, result: "near", nearest: Math.round(nearest) };
  t.list.push({ lat: fix.lat, lon: fix.lon });
  return { task: t, result: t.list.length >= MARKS.need ? "done" : "added" };
}
