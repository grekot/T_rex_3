// Logika Korony: rozpoznanie szczytu, najbliższe niezdobyte, postęp, daty zdobycia.
// Czyste funkcje bez @zos - testy w test/korona.test.mjs.
import { PEAKS, OFFICIAL, findPeak } from "./peaks.js";
import { distance } from "./geo.js";

// Promień „jesteś na szczycie”. Błąd GPS zegarka w lesie to 10-30 m, węzeł szczytu w OSM bywa
// przesunięty o kilkanaście-kilkadziesiąt m, a na płaskich, zalesionych wierzchołkach (Lubomir,
// Jagodna, Kłodzka Góra, Łysica) szlak mija najwyższy punkt o kilkadziesiąt metrów. 120 m na
// grzbiecie o nachyleniu 5-10% to 6-12 m poniżej szczytu - nadal „na szczycie”, a najbliższe
// sobie wierzchołki z listy (Kłodzka Góra - Szeroka Góra, ok. 430 m) się nie nakładają.
export const SUMMIT_RADIUS_M = 120;
// Wyjście ze szczytu dopiero dalej - żeby skoki GPS na granicy nie migały komunikatem
export const LEAVE_RADIUS_M = 200;
// Ile kolejnych odczytów w promieniu potrzeba (pojedynczy skok GPS nie zalicza szczytu)
export const CONFIRM_FIXES = 2;

const MIN_YEAR = 1950;

// --- daty (zapisujemy „RRRR-MM-DD”, bez stref czasowych) ---

const two = (n) => (n < 10 ? "0" : "") + n;

export function dateKey(y, m, d) {
  return y + "-" + two(m) + "-" + two(d);
}

export function todayKey(nowMs) {
  const t = new Date(nowMs);
  return dateKey(t.getFullYear(), t.getMonth() + 1, t.getDate());
}

export function parseKey(key) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key || ""));
  if (!m) return null;
  return { y: +m[1], m: +m[2], d: +m[3] };
}

// „2024-05-12” -> „12.05.2024”
export function formatDate(key) {
  const p = parseKey(key);
  return p ? two(p.d) + "." + two(p.m) + "." + p.y : "";
}

export function daysInMonth(y, m) {
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

// Poprawna data, nie z przyszłości i nie sprzed MIN_YEAR. Dzień przycinany do długości miesiąca.
export function clampDate(y, m, d, nowMs) {
  const today = parseKey(todayKey(nowMs));
  y = Math.max(MIN_YEAR, Math.min(today.y, Math.round(y)));
  m = ((Math.round(m) - 1 + 1200) % 12) + 1;
  d = Math.max(1, Math.min(daysInMonth(y, m), Math.round(d)));
  if (dateKey(y, m, d) > dateKey(today.y, today.m, today.d)) return today;
  return { y, m, d };
}

// Zmiana jednego pola wybieraka daty o +-1 (miesiąc i dzień zawijają się w kółko)
export function stepDate(date, field, delta, nowMs) {
  let { y, m, d } = date;
  if (field === "y") y += delta;
  if (field === "m") m = ((m - 1 + delta + 12) % 12) + 1;
  if (field === "d") {
    const n = daysInMonth(y, m);
    d = ((d - 1 + delta + n) % n) + 1;
  }
  return clampDate(y, m, d, nowMs);
}

// --- zdobycia: { [id]: { d: "RRRR-MM-DD", gps: bool } } ---

export function normalizeClimbs(raw) {
  const out = {};
  if (!raw || typeof raw !== "object") return out;
  Object.keys(raw).forEach((id) => {
    const c = raw[id];
    if (findPeak(id) && c && parseKey(c.d)) out[id] = { d: c.d, gps: !!c.gps };
  });
  return out;
}

export function addClimb(climbs, id, dateKeyValue, gps) {
  const next = { ...climbs };
  if (findPeak(id) && parseKey(dateKeyValue)) next[id] = { d: dateKeyValue, gps: !!gps };
  return next;
}

export function removeClimb(climbs, id) {
  const next = { ...climbs };
  delete next[id];
  return next;
}

export function progress(climbs) {
  const done = OFFICIAL.filter((p) => climbs[p.id]).length;
  return { done, total: OFFICIAL.length, complete: done === OFFICIAL.length };
}

// Wiersze listy: 28 szczytów w kolejności listy (od najwyższego), potem warianty
export function listRows(climbs) {
  return PEAKS.map((p) => ({ peak: p, climb: climbs[p.id] || null }));
}

// --- GPS ---

// Najbliższy wierzchołek (z listy albo wariant) w promieniu - albo null
export function summitAt(fix, radius) {
  if (!fix) return null;
  let best = null;
  let bestD = Infinity;
  PEAKS.forEach((p) => {
    const d = distance(fix.lat, fix.lon, p.lat, p.lon);
    if (d <= radius && d < bestD) {
      best = p;
      bestD = d;
    }
  });
  return best ? { peak: best, distance: bestD } : null;
}

// Najbliższe niezdobyte szczyty z listy (bez wariantów), posortowane po odległości
export function nearestUnclimbed(fix, climbs, count) {
  if (!fix) return [];
  return OFFICIAL.filter((p) => !climbs[p.id])
    .map((p) => ({ peak: p, distance: distance(fix.lat, fix.lon, p.lat, p.lon) }))
    .sort((a, b) => a.distance - b.distance)
    .slice(0, count || OFFICIAL.length);
}

// Rozpoznawanie z histerezą: update(fix) -> { peak, entered }
// entered = true tylko w chwili wejścia na szczyt (wtedy wibracja).
export function createSummitWatcher() {
  let current = null;
  let candidate = null;
  let hits = 0;
  return {
    update(fix) {
      if (!fix) return { peak: current, entered: false };
      if (current) {
        if (distance(fix.lat, fix.lon, current.lat, current.lon) <= LEAVE_RADIUS_M) {
          return { peak: current, entered: false };
        }
        current = null;
      }
      const at = summitAt(fix, SUMMIT_RADIUS_M);
      if (!at) {
        candidate = null;
        hits = 0;
        return { peak: null, entered: false };
      }
      if (candidate && candidate.id === at.peak.id) hits += 1;
      else {
        candidate = at.peak;
        hits = 1;
      }
      if (hits >= CONFIRM_FIXES) {
        current = candidate;
        candidate = null;
        hits = 0;
        return { peak: current, entered: true };
      }
      return { peak: null, entered: false };
    },
    current() {
      return current;
    },
  };
}

// Podpis szczytu: „2499 m · Tatry”
export function peakLine(peak) {
  return peak.h + " m · " + peak.range;
}

// Opis wariantu: „wariant: Chełmiec”
export function variantLine(peak) {
  const main = peak.variantOf ? findPeak(peak.variantOf) : null;
  return main ? "wariant dla: " + main.name : "";
}
