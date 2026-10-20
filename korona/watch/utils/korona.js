// Logika Korony: rozpoznanie szczytu, najbliższe niezdobyte, postęp, daty zdobycia.
// Czyste funkcje bez @zos - testy w test/korona.test.mjs.
import { PEAKS, MY_GROUP, findPeak, groupPeaks } from "./peaks.js";
import { distance } from "./geo.js";

// Promień „jesteś na szczycie”. Błąd GPS zegarka w lesie to 10-30 m, węzeł szczytu w OSM bywa
// przesunięty o kilkanaście-kilkadziesiąt m, a na płaskich, zalesionych wierzchołkach (Lubomir,
// Jagodna, Kłodzka Góra, Łysica) szlak mija najwyższy punkt o kilkadziesiąt metrów. 120 m na
// grzbiecie o nachyleniu 5-10% to 6-12 m poniżej szczytu - nadal „na szczycie”.
// Gdzie wierzchołki stoją gęsto (Tatry, grzbiety Beskidów), tools/fetch_peaks.mjs zmniejsza
// promień szczytu (pole r) do połowy odległości od sąsiada, min. 40 m - strefy się nie nakładają.
export const SUMMIT_RADIUS_M = 120;
// Wyjście ze szczytu dopiero o tyle dalej - żeby skoki GPS na granicy nie migały komunikatem
export const LEAVE_EXTRA_M = 80;
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
// --- własne szczyty: { [id "c<ms>"]: { name, lat, lon, d, gps } } (data zdobycia w środku) ---

export function normalizeClimbs(raw) {
  const out = {};
  if (!raw || typeof raw !== "object") return out;
  Object.keys(raw).forEach((id) => {
    const c = raw[id];
    if (findPeak(id) && c && parseKey(c.d)) out[id] = { d: c.d, gps: !!c.gps };
  });
  return out;
}

export function normalizeCustom(raw) {
  const out = {};
  if (!raw || typeof raw !== "object") return out;
  Object.keys(raw).forEach((id) => {
    const c = raw[id];
    if (/^c\d+$/.test(id) && c && typeof c.name === "string" && c.name.trim() && isFinite(c.lat) && isFinite(c.lon) && parseKey(c.d)) {
      out[id] = { name: c.name.slice(0, 40), lat: +c.lat, lon: +c.lon, d: c.d, gps: !!c.gps };
    }
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

// Zdobycie szczytu z list albo własnego (własny ma datę w sobie)
export function climbOf(id, climbs, custom) {
  const c = custom && custom[id];
  if (c) return { d: c.d, gps: c.gps };
  return climbs[id] || null;
}

export function newCustomId(nowMs, custom) {
  let id = "c" + Math.floor(nowMs);
  while (custom && custom[id]) id = "c" + (Number(id.slice(1)) + 1);
  return id;
}

// Nazwa własnego szczytu, gdy nie da się jej wpisać: „Szczyt 3”
export function autoName(custom) {
  return "Szczyt " + (Object.keys(custom || {}).length + 1);
}

// Postęp listy: { done, total, complete }; „Moje szczyty” = ile dodanych
export function progress(groupId, climbs, custom) {
  if (groupId === MY_GROUP) {
    const n = Object.keys(custom || {}).length;
    return { done: n, total: n, complete: false };
  }
  const peaks = groupPeaks(groupId, custom, true);
  const done = peaks.filter((p) => climbs[p.id]).length;
  return { done, total: peaks.length, complete: peaks.length > 0 && done === peaks.length };
}

// Ile różnych szczytów zdobyto w ogóle (szczyt w dwóch listach liczy się raz)
export function totalClimbed(climbs, custom) {
  return Object.keys(climbs).length + Object.keys(custom || {}).length;
}

// Wiersze listy: zdobyte (od najnowszej daty), potem niezdobyte (od najwyższego), warianty na końcu
export function groupRows(groupId, climbs, custom) {
  const rows = groupPeaks(groupId, custom, false).map((p) => ({ peak: p, climb: climbOf(p.id, climbs, custom) }));
  const rank = (r) => (r.climb ? 0 : r.peak.variantOf ? 2 : 1);
  return rows.sort((a, b) => {
    if (rank(a) !== rank(b)) return rank(a) - rank(b);
    if (a.climb && b.climb && a.climb.d !== b.climb.d) return a.climb.d < b.climb.d ? 1 : -1;
    if (a.peak.h !== b.peak.h) return b.peak.h - a.peak.h;
    return a.peak.name < b.peak.name ? -1 : 1;
  });
}

// --- GPS ---

export function radiusOf(peak) {
  return peak.r || SUMMIT_RADIUS_M;
}

// Najbliższy wierzchołek, w którego promieniu jesteś - albo null
export function summitAt(fix, peaks) {
  if (!fix) return null;
  let best = null;
  let bestD = Infinity;
  for (let i = 0; i < peaks.length; i++) {
    const p = peaks[i];
    // szybkie odrzucenie dalekich (0.01° szer. ~ 1,1 km)
    if (Math.abs(p.lat - fix.lat) > 0.01 || Math.abs(p.lon - fix.lon) > 0.016) continue;
    const d = distance(fix.lat, fix.lon, p.lat, p.lon);
    if (d <= radiusOf(p) && d < bestD) {
      best = p;
      bestD = d;
    }
  }
  return best ? { peak: best, distance: bestD } : null;
}

// Najbliższe niezdobyte (bez wariantów i własnych), posortowane po odległości.
// groupId = null -> ze wszystkich list.
export function nearestUnclimbed(fix, climbs, groupId, count) {
  if (!fix) return [];
  const peaks = groupId ? groupPeaks(groupId, null, true) : PEAKS.filter((p) => !p.variantOf);
  return peaks
    .filter((p) => !climbs[p.id])
    .map((p) => ({ peak: p, distance: distance(fix.lat, fix.lon, p.lat, p.lon) }))
    .sort((a, b) => a.distance - b.distance)
    .slice(0, count || peaks.length);
}

// Rozpoznawanie z histerezą: update(fix, peaks) -> { peak, entered }
// entered = true tylko w chwili wejścia na szczyt (wtedy wibracja). Przejście granią na sąsiedni
// wierzchołek też potrzebuje CONFIRM_FIXES odczytów.
export function createSummitWatcher() {
  let current = null;
  let candidate = null;
  let hits = 0;
  return {
    update(fix, peaks) {
      if (!fix) return { peak: current, entered: false };
      const at = summitAt(fix, peaks);
      if (current && (!at || at.peak.id === current.id)) {
        candidate = null;
        hits = 0;
        if (at || distance(fix.lat, fix.lon, current.lat, current.lon) <= radiusOf(current) + LEAVE_EXTRA_M) {
          return { peak: current, entered: false };
        }
        current = null;
        return { peak: null, entered: false };
      }
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
      return { peak: current, entered: false };
    },
    current() {
      return current;
    },
  };
}

// Podpis szczytu: „2499 m · Tatry”
export function peakLine(peak) {
  return (peak.h ? peak.h + " m · " : "") + peak.range;
}

// Opis wariantu: „wariant dla: Chełmiec”
export function variantLine(peak) {
  const main = peak.variantOf ? findPeak(peak.variantOf) : null;
  return main ? "wariant dla: " + main.name : "";
}

