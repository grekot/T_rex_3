// Logika wagi bez zależności od zegarka (testy w Node: test/weight.test.mjs).
//
// Wagę trzymamy w dziesiątych częściach kilograma (823 = 82,3 kg), żeby +/- 0,1
// nie zbierało błędów zaokrągleń. Dni to klucze „RRRR-MM-DD” w czasie lokalnym,
// jeden pomiar na dzień (ponowny zapis tego samego dnia nadpisuje).
//
// Dane: { v: 1, e: [{ d: "2026-10-23", w: 823, t: <ms zapisu> }, ...] } rosnąco po dniu.
// w: 0 = pomiar usunięty (nagrobek z synchronizacji, waga/SYNC.md) - zostaje w danych, żeby
// starszy wpis z chmury go nie przywrócił, ale nigdzie się nie pokazuje.

export const MIN_W = 300; // 30,0 kg
export const MAX_W = 2500; // 250,0 kg
export const DEFAULT_W = 800; // pierwszy pomiar startuje od 80,0 kg

export function clampW(w) {
  return Math.max(MIN_W, Math.min(MAX_W, Math.round(w)));
}

export function stepW(w, delta) {
  return clampW(w + delta);
}

// 823 -> "82,3"
export function formatKg(w) {
  const n = Math.round(w);
  return Math.floor(n / 10) + "," + (n % 10);
}

// różnica w dziesiątych: 3 -> "+0,3", -4 -> "−0,4", 0 -> "±0,0"
export function formatDelta(d) {
  const n = Math.round(d);
  if (n === 0) return "±0,0";
  return (n > 0 ? "+" : "−") + formatKg(Math.abs(n));
}

// --- daty ---

const two = (n) => (n < 10 ? "0" : "") + n;

export function dateKey(y, m, d) {
  return y + "-" + two(m) + "-" + two(d);
}

export function parseKey(key) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key || ""));
  if (!m) return null;
  return { y: +m[1], m: +m[2], d: +m[3] };
}

function keyToUtc(key) {
  const p = parseKey(key);
  return p ? Date.UTC(p.y, p.m - 1, p.d) : NaN;
}

const DAY_MS = 86400000;

export function addDays(key, n) {
  const t = new Date(keyToUtc(key) + n * DAY_MS);
  return dateKey(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate());
}

// ile dni od a do b (b później -> dodatnie)
export function daysBetween(a, b) {
  return Math.round((keyToUtc(b) - keyToUtc(a)) / DAY_MS);
}

const WEEKDAYS = ["nd", "pn", "wt", "śr", "cz", "pt", "sb"];

// "2026-10-23" -> "pt 23.10"
export function shortDate(key) {
  const p = parseKey(key);
  if (!p) return "";
  const wd = new Date(keyToUtc(key)).getUTCDay();
  return WEEKDAYS[wd] + " " + two(p.d) + "." + two(p.m);
}

// --- dane ---

export function emptyData() {
  return { v: 1, e: [] };
}

// Poprawna waga albo nagrobek (0)
function validW(w) {
  return typeof w === "number" && (w === 0 || (w >= MIN_W && w <= MAX_W));
}

function live(data) {
  return data.e.filter((x) => x.w > 0);
}

// Cokolwiek przyszło z pliku -> poprawne dane (zły wpis odpada, duplikat dnia: późniejszy zapis wygrywa)
export function normalize(raw) {
  const byDay = {};
  const list = raw && Array.isArray(raw.e) ? raw.e : [];
  list.forEach((x) => {
    if (!x || !parseKey(x.d) || !validW(x.w)) return;
    const t = typeof x.t === "number" ? x.t : 0;
    const prev = byDay[x.d];
    if (!prev || t >= prev.t) byDay[x.d] = { d: x.d, w: Math.round(x.w), t };
  });
  const e = Object.keys(byDay)
    .sort()
    .map((d) => byDay[d]);
  return { v: 1, e };
}

export function upsert(data, day, w, t) {
  const e = data.e.filter((x) => x.d !== day);
  e.push({ d: day, w: clampW(w), t });
  e.sort((a, b) => (a.d < b.d ? -1 : a.d > b.d ? 1 : 0));
  return { v: 1, e };
}

// Pomiar z danego dnia (nagrobek = brak pomiaru)
export function entryFor(data, day) {
  for (let i = 0; i < data.e.length; i++) if (data.e[i].d === day) return data.e[i].w > 0 ? data.e[i] : null;
  return null;
}

// ostatni pomiar sprzed danego dnia
export function lastBefore(data, day) {
  for (let i = data.e.length - 1; i >= 0; i--) if (data.e[i].d < day && data.e[i].w > 0) return data.e[i];
  return null;
}

// Od czego startuje ekran: dzisiejszy zapis, inaczej ostatni pomiar, inaczej 80,0
export function startValue(data, today) {
  const t = entryFor(data, today);
  if (t) return t.w;
  const last = lastBefore(data, today);
  return last ? last.w : DEFAULT_W;
}

// Wartości z ostatnich `days` dni (stare -> nowe, null = brak pomiaru).
// `current` (gdy podany) zastępuje dzisiejszy dzień - widać wykres razem z niezapisaną wagą.
export function series(data, today, days, current) {
  const out = [];
  for (let i = days - 1; i >= 0; i--) {
    const day = addDays(today, -i);
    if (i === 0 && typeof current === "number") out.push(current);
    else {
      const x = entryFor(data, day);
      out.push(x ? x.w : null);
    }
  }
  return out;
}

// Średnia (w dziesiątych, zaokrąglona) z pomiarów z ostatnich `days` dni; null gdy brak
export function average(values) {
  const v = values.filter((x) => typeof x === "number");
  if (!v.length) return null;
  return Math.round(v.reduce((a, b) => a + b, 0) / v.length);
}

// Opis zmiany względem poprzedniego pomiaru: { text, sign } albo null (pierwszy pomiar)
export function changeInfo(data, today, current) {
  const prev = lastBefore(data, today);
  if (!prev) return null;
  const d = current - prev.w;
  const gap = daysBetween(prev.d, today);
  const since = gap === 1 ? "od wczoraj" : "od " + shortDate(prev.d);
  return { text: formatDelta(d) + " kg " + since, sign: Math.sign(Math.round(d)) };
}

// Wiersze historii, od najnowszego: { d, w, delta } (delta względem poprzedniego pomiaru, null dla pierwszego)
export function historyRows(data, limit) {
  const e = live(data);
  const out = [];
  for (let i = e.length - 1; i >= 0 && out.length < limit; i--) {
    out.push({ d: e[i].d, w: e[i].w, delta: i > 0 ? e[i].w - e[i - 1].w : null });
  }
  return out;
}

// Zmiana w ostatnich `days` dniach: najnowszy pomiar minus najstarszy z tego okresu
// (null, gdy w okresie są mniej niż dwa pomiary)
export function periodChange(data, today, days) {
  const from = addDays(today, -(days - 1));
  const inRange = live(data).filter((x) => x.d >= from && x.d <= today);
  if (inRange.length < 2) return null;
  return inRange[inRange.length - 1].w - inRange[0].w;
}

// Wysokości słupków wykresu w px (null = brak pomiaru). Najniższy pomiar ma `minH`,
// najwyższy `height`; zakres co najmniej `minSpan` dziesiątych, żeby 0,1 kg nie wyglądało jak skok.
export function barHeights(values, height, minH, minSpan) {
  const v = values.filter((x) => typeof x === "number");
  if (!v.length) return values.map(() => null);
  let lo = Math.min.apply(null, v);
  let hi = Math.max.apply(null, v);
  if (hi - lo < minSpan) {
    const mid = (hi + lo) / 2;
    lo = mid - minSpan / 2;
    hi = mid + minSpan / 2;
  }
  return values.map((x) => (typeof x === "number" ? Math.round(minH + ((x - lo) / (hi - lo)) * (height - minH)) : null));
}

// Przytrzymanie +/-: po ilu ms następny krok (n = numer powtórzenia od 1)
export function repeatDelay(n) {
  if (n <= 1) return 450;
  if (n <= 10) return 120;
  return 50;
}

// --- synchronizacja (waga/SYNC.md) ---

// Scalenie z wpisami z chmury (remote: { "RRRR-MM-DD": { w, t } } albo null).
// Dla każdego dnia wygrywa większe t (nagrobek w: 0 też). Wynik:
//   data    - scalone dane do zapisania w pliku,
//   push    - wpisy, w których lokalne dane są nowsze (do wysłania), [{ d, w, t }],
//   changed - czy coś z chmury zmieniło lokalne dane.
export function mergeRemote(local, remote) {
  const byDay = {};
  local.e.forEach((x) => {
    byDay[x.d] = x;
  });
  const push = [];
  let changed = false;
  const r = remote && typeof remote === "object" ? remote : {};
  Object.keys(r).forEach((d) => {
    const x = r[d];
    if (!parseKey(d) || !x || !validW(x.w) || typeof x.t !== "number") return;
    const mine = byDay[d];
    if (!mine || x.t > mine.t) {
      if (!mine || mine.w !== x.w || mine.t !== x.t) changed = true;
      byDay[d] = { d, w: Math.round(x.w), t: x.t };
    }
  });
  Object.keys(byDay).forEach((d) => {
    const mine = byDay[d];
    const x = r[d];
    const remoteT = x && typeof x.t === "number" && validW(x.w) ? x.t : -1;
    if (mine.t > remoteT) push.push({ d, w: mine.w, t: mine.t });
  });
  push.sort((a, b) => (a.d < b.d ? -1 : a.d > b.d ? 1 : 0));
  return { data: normalize({ e: Object.keys(byDay).map((d) => byDay[d]) }), push, changed };
}

// Plan synchronizacji w Side Service: sent = wpisy z zegarka, remote = mapa z chmury.
// push - dni do zapisania w chmurze, apply - dni do odesłania zegarkowi (chmura nowsza albo
// dzień, którego zegarek nie ma).
export function syncPlan(sent, remote) {
  const local = normalize({ e: sent });
  const merged = mergeRemote(local, remote);
  const mine = {};
  local.e.forEach((x) => {
    mine[x.d] = x;
  });
  const apply = merged.data.e.filter((x) => !mine[x.d] || mine[x.d].t !== x.t || mine[x.d].w !== x.w);
  return { push: merged.push, apply };
}
