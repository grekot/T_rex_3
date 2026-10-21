// Geometria na kuli ziemskiej i formatowanie - czyste funkcje, testy w test/geo.test.mjs.

const R = 6371000; // promień Ziemi w metrach




const toRad = (d) => (d * Math.PI) / 180;
const toDeg = (r) => (r * 180) / Math.PI;

export function normalize(deg) {
  const d = deg % 360;
  return d < 0 ? d + 360 : d;
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

// O ile obrócić strzałkę: kierunek do celu minus kierunek, w który patrzy góra zegarka
export function relativeAngle(targetBearing, heading) {
  return normalize(targetBearing - heading);
}

// Wygładzanie drgań kompasu - interpolacja po najkrótszym łuku (359° -> 1° to 2°, nie 358°)
export function smoothAngle(prev, next, factor) {
  if (prev === null || prev === undefined) return normalize(next);
  const diff = ((next - prev + 540) % 360) - 180;
  return normalize(prev + diff * factor);
}

// 7 m, 350 m, 1,25 km, 12,3 km, 152 km
export function formatDistance(m) {
  if (!isFinite(m)) return "-";
  if (m < 1000) return Math.round(m) + " m";
  if (m < 10000) return (m / 1000).toFixed(2).replace(".", ",") + " km";
  if (m < 100000) return (m / 1000).toFixed(1).replace(".", ",") + " km";
  return Math.round(m / 1000) + " km";
}

const CARDINAL = ["Pn", "Pn-Wsch", "Wsch", "Pd-Wsch", "Pd", "Pd-Zach", "Zach", "Pn-Zach"];

// 45 -> "Pn-Wsch"
export function cardinal(deg) {
  return CARDINAL[Math.round(normalize(deg) / 45) % 8];
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

