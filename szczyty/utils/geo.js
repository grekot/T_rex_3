// Geometria na kuli ziemskiej i formatowanie - czyste funkcje, testy w test/geo.test.mjs.
// Część skopiowana z powrot/watch/utils/geo.js.

export const R = 6371000; // promień Ziemi w metrach
// Współczynnik refrakcji atmosferycznej (standardowo 0,13): promień światła zakrzywia się
// razem z Ziemią, więc dalekie szczyty "chowają się" za horyzontem wolniej niż bez powietrza
export const REFRACTION = 0.13;

const toRad = (d) => (d * Math.PI) / 180;
const toDeg = (r) => (r * 180) / Math.PI;

export function normalize(deg) {
  const d = deg % 360;
  return d < 0 ? d + 360 : d;
}

// Różnica kątów ze znakiem w (-180, 180]: dodatnia = cel jest na prawo od kierunku
export function angleDiff(target, from) {
  let d = normalize(target - from);
  if (d > 180) d -= 360;
  return d;
}

// Odległość w metrach (wzór haversine)
export function distance(lat1, lon1, lat2, lon2) {
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  return 2 * R * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// Kierunek do celu: stopnie od północy, zgodnie z ruchem wskazówek (0 = N, 90 = E)
export function bearing(lat1, lon1, lat2, lon2) {
  const y = Math.sin(toRad(lon2 - lon1)) * Math.cos(toRad(lat2));
  const x =
    Math.cos(toRad(lat1)) * Math.sin(toRad(lat2)) -
    Math.sin(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.cos(toRad(lon2 - lon1));
  return normalize(toDeg(Math.atan2(y, x)));
}

// O ile metrów obiekt w odległości d "zapada się" przez krzywiznę Ziemi (z refrakcją)
export function curvatureDrop(d) {
  return ((1 - REFRACTION) * d * d) / (2 * R);
}

// Kąt wzniesienia szczytu nad poziomem oka obserwatora (stopnie; ujemny = poniżej)
export function elevationAngle(observerEle, peakEle, d) {
  return toDeg(Math.atan2(peakEle - observerEle - curvatureDrop(d), d));
}

// Zasięg widnokręgu z wysokości h (m n.p.m., teren płaski jak morze) - z refrakcją
export function horizonDistance(h) {
  return Math.sqrt((2 * R * Math.max(0, h)) / (1 - REFRACTION));
}

// Wygładzanie drgań kompasu - interpolacja po najkrótszym łuku (359° -> 1° to 2°, nie 358°)
export function smoothAngle(prev, next, factor) {
  if (prev === null || prev === undefined) return normalize(next);
  return normalize(prev + angleDiff(next, prev) * factor);
}

// 350 m, 1,2 km, 12 km, 152 km - na szlaku dokładność do kilometra wystarcza
export function formatDistance(m) {
  if (!isFinite(m)) return "-";
  if (m < 1000) return Math.round(m / 10) * 10 + " m";
  if (m < 10000) return (m / 1000).toFixed(1).replace(".", ",") + " km";
  return Math.round(m / 1000) + " km";
}

const CARDINAL = ["Pn", "Pn-Wsch", "Wsch", "Pd-Wsch", "Pd", "Pd-Zach", "Zach", "Pn-Zach"];

// 45 -> "Pn-Wsch"
export function cardinal(deg) {
  return CARDINAL[Math.round(normalize(deg) / 45) % 8];
}

// 213.4 -> "213°"
export function formatDeg(deg) {
  return (Math.round(normalize(deg)) % 360) + "°";
}

// Współrzędna ze znakiem: wartość w stopniach dziesiętnych + litera kierunku z formatu DMS
// (S i W = ujemne). Dokumentacja Zepp nie mówi, czy DD ma znak - liczymy go sami.
export function signedCoord(dd, dms) {
  const value = Math.abs(Number(dd));
  const dir = dms && typeof dms === "object" ? String(dms.direction || "").toUpperCase() : "";
  return dir === "S" || dir === "W" ? -value : value;
}

export function validCoords(lat, lon) {
  return isFinite(lat) && isFinite(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180 && !(lat === 0 && lon === 0);
}

const two = (n) => (n < 10 ? "0" : "") + n;

// "dziś 14:05", "wczoraj 18:30", "16.10 14:05"
export function formatWhen(ms, nowMs) {
  const d = new Date(ms);
  const now = new Date(nowMs);
  const time = two(d.getHours()) + ":" + two(d.getMinutes());
  const day = (x) => Math.floor(Date.UTC(x.getFullYear(), x.getMonth(), x.getDate()) / 86400000);
  const diff = day(now) - day(d);
  if (diff === 0) return "dziś " + time;
  if (diff === 1) return "wczoraj " + time;
  return two(d.getDate()) + "." + two(d.getMonth() + 1) + " " + time;
}
