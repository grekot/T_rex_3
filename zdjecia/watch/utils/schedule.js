// Losowe pokazywanie zdjęć (sposób D): budzik systemowy otwiera wprost ekran zdjęcia.
// Czysta logika bez API zegarka (testy: test/schedule.test.mjs):
//   - ustawienia: ile razy dziennie i w jakich godzinach,
//   - losowanie godzin: okno dzielone na równe przedziały, w każdym losowa chwila, odstęp co najmniej 2 h,
//   - plan na dziś i HORIZON_DAYS kolejnych dni, uzgadniany z budzikami w systemie,
//   - worek: zdjęcia bez powtórek, dopóki nie pokażą się wszystkie.
// Czas to ms UTC (Date.now()); godziny okna liczymy w czasie lokalnym przez przesunięcie strefy tzMin (minuty).

export const PHOTO_PAGE = "page/gt/photo/index.page";
export const DIRECT = "D";
// Po tylu sekundach zdjęcie z budzika samo się zamyka (powrót do tarczy)
export const AUTO_CLOSE_S = 15;
// Próba z ekranu ustawień: budzik za tyle sekund
export const TEST_DELAY_S = 60;

export const DEFAULT_SETTINGS = { on: true, perDay: 3, from: 9, to: 21, bright: 100 };
// Jasność ekranu podczas pokazu zdjęcia (0 = bez zmian, zostaje systemowa)
export const BRIGHT_STEPS = [0, 60, 80, 100];
export const PER_DAY_MIN = 1;
export const PER_DAY_MAX = 24;
// Kolejne wartości przyciskami +/- (powyżej 6 większymi krokami - dużo pokazów przydaje się do testów)
export const PER_DAY_STEPS = [1, 2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 24];
// Najmniejszy odstęp między zdjęciami; gdy okno jest za krótkie - połowa przedziału
export const MIN_GAP_MIN = 120;
// Plan obejmuje dziś i tyle kolejnych dni (czyli zawsze co najmniej 2 dni naprzód)
export const HORIZON_DAYS = 2;

// Przy wielu pokazach dziennie plan tylko na dziś i jutro, żeby nie zakładać dziesiątek budzików naraz
// (każde wyskoczenie i tak uzupełnia plan, więc łańcuch się nie urywa)
export function horizonDays(perDay) {
  return perDay > 6 ? 1 : HORIZON_DAYS;
}

// Następna / poprzednia wartość z PER_DAY_STEPS (także gdy obecna jest spoza listy)
export function stepPerDay(perDay, delta) {
  if (delta > 0) {
    const up = PER_DAY_STEPS.filter((v) => v > perDay);
    return up.length ? up[0] : PER_DAY_MAX;
  }
  if (delta < 0) {
    const down = PER_DAY_STEPS.filter((v) => v < perDay);
    return down.length ? down[down.length - 1] : PER_DAY_MIN;
  }
  return perDay;
}
// Najbliższy budzik nie wcześniej niż za tyle minut (żeby nie wyskoczył zaraz po zmianie ustawień)
export const LEAD_MIN = 2;

const MIN = 60000;
const DAY_MIN = 1440;

function clampInt(v, lo, hi, def) {
  if (v === undefined || v === null || v === "") return def;
  const n = Math.round(Number(v));
  if (!isFinite(n)) return def;
  return Math.min(hi, Math.max(lo, n));
}

// Ustawienia zawsze poprawne: od 0-23, do 1-24, okno co najmniej 1 h
export function normalizeSettings(settings) {
  const s = settings || {};
  const d = DEFAULT_SETTINGS;
  const from = clampInt(s.from, 0, 23, d.from);
  let to = clampInt(s.to, 1, 24, d.to);
  if (to <= from) to = from + 1;
  return {
    on: s.on === undefined || s.on === null ? d.on : !!s.on,
    perDay: clampInt(s.perDay, PER_DAY_MIN, PER_DAY_MAX, d.perDay),
    from,
    to,
    bright: clampInt(s.bright, 0, 100, d.bright),
  };
}

export function brightText(bright) {
  return bright ? bright + "%" : "bez zmian";
}

function stepBright(bright, delta) {
  if (delta > 0) {
    const up = BRIGHT_STEPS.filter((v) => v > bright);
    return up.length ? up[0] : BRIGHT_STEPS[BRIGHT_STEPS.length - 1];
  }
  const down = BRIGHT_STEPS.filter((v) => v < bright);
  return down.length ? down[down.length - 1] : 0;
}

// Zmiana jednego pola na ekranie ustawień; „od” i „do” przesuwają się nawzajem (okno co najmniej 1 h)
export function adjust(settings, field, delta) {
  const s = normalizeSettings(settings);
  if (field === "on") return { ...s, on: !s.on };
  if (field === "perDay") return { ...s, perDay: stepPerDay(s.perDay, delta) };
  if (field === "bright") return { ...s, bright: stepBright(s.bright, delta) };
  if (field === "from") {
    const from = clampInt(s.from + delta, 0, 23, s.from);
    return { ...s, from, to: Math.max(s.to, from + 1) };
  }
  if (field === "to") {
    const to = clampInt(s.to + delta, 1, 24, s.to);
    return { ...s, to, from: Math.min(s.from, to - 1) };
  }
  return s;
}

// Plan powstał dla tych ustawień - inne ustawienia = plan od nowa
export function settingsKey(settings) {
  const s = normalizeSettings(settings);
  return s.on ? s.perDay + "x" + s.from + "-" + s.to : "off";
}

// Numer dnia w czasie lokalnym (dni od 1970-01-01)
export function localDay(ms, tzMin) {
  return Math.floor((Math.floor(ms / MIN) + tzMin) / DAY_MIN);
}

// Przesunięcie strefy z odczytu zegara (lokalna data i godzina) i czasu UTC, zaokrąglone do 15 min
export function tzFromClock(year, month, date, hours, minutes, utcMs) {
  const local = Date.UTC(year, month - 1, date, hours, minutes);
  return Math.round((local - utcMs) / (15 * MIN)) * 15;
}

// Chwile pokazania zdjęć w jednym dniu (ms UTC, rosnąco). Okno dzielimy na równe przedziały
// i w każdym losujemy minutę, ale nie bliżej poprzedniej niż odstęp. random() jak Math.random.
// notBefore (ms UTC): dziś tylko później; wtedy zdjęć proporcjonalnie mniej (pozostała część okna).
export function dayTimes(day, settings, tzMin, random, notBefore) {
  const s = normalizeSettings(settings);
  const base = day * DAY_MIN - tzMin; // minuta UTC lokalnej północy
  const from = s.from * 60;
  const to = s.to * 60;
  let start = from;
  let count = s.perDay;
  if (notBefore) {
    const nb = Math.ceil(notBefore / MIN) - base;
    if (nb >= to) return [];
    if (nb > from) {
      start = nb;
      count = Math.round((s.perDay * (to - nb)) / (to - from));
    }
  }
  if (count < 1) return [];
  const slot = (to - start) / count;
  const gap = Math.min(MIN_GAP_MIN, Math.floor(slot / 2));
  const out = [];
  let prev = -Infinity;
  for (let i = 0; i < count; i++) {
    const lo = Math.max(Math.ceil(start + i * slot), prev + gap);
    const hi = Math.floor(start + (i + 1) * slot);
    const t = lo + Math.floor(random() * Math.max(1, hi - lo));
    out.push((base + t) * MIN);
    prev = t;
  }
  return out;
}

function unique(list) {
  return list.filter((v, i) => list.indexOf(v) === i);
}

// Uzgodnienie planu z budzikami w systemie (przy każdym starcie aplikacji i ekranu zdjęcia).
// plan: { key, until, items: [{ alarm, at }] } z pamięci; alarms: id budzików aplikacji z systemu
// (null = nie wiadomo). Wynik: co anulować, co zostaje i jakie chwile dodać (nowe dni + zgubione budziki).
// Najpierw anulować, potem ustawiać - system może dać nowemu budzikowi numer anulowanego.
export function topUp(plan, alarms, settings, now, tzMin, random) {
  const s = normalizeSettings(settings);
  const key = settingsKey(s);
  const p = plan || {};
  const items = Array.isArray(p.items) ? p.items : [];
  const known = Array.isArray(alarms) ? alarms.map(Number) : null;
  const same = p.key === key && s.on;
  const keep = [];
  const add = [];
  items.forEach((it) => {
    if (!it || !(it.at > now)) return; // już był (albo właśnie jest)
    const alive = it.alarm && (!known || known.indexOf(Number(it.alarm)) >= 0);
    // Próba z ekranu ustawień zostaje niezależnie od ustawień (zgubiona przepada)
    if (it.test) {
      if (alive) keep.push(it);
    } else if (same) {
      if (alive) keep.push(it);
      // Budzik zginął albo się nie ustawił - jeszcze raz; ale nie ten, który właśnie dzwoni
      // (budzik potrafi zadzwonić ułamek sekundy przed czasem i już go nie ma w systemie)
      else if (it.at > now + LEAD_MIN * MIN) add.push(it.at);
    }
  });
  // Wszystko inne w systemie (stary plan, zmiana ustawień, próby z wersji 0.3) idzie do kosza
  const keepIds = keep.map((it) => Number(it.alarm));
  const pool = known || items.map((it) => it && Number(it.alarm)).filter(Boolean);
  const cancel = unique(pool.filter((id) => keepIds.indexOf(id) < 0));
  if (!s.on) return { key, until: null, cancel, keep, add: [] };

  const today = localDay(now, tzMin);
  const last = today + horizonDays(s.perDay);
  const until = same && typeof p.until === "number" ? p.until : null;
  const first = until === null ? today : Math.max(until + 1, today);
  for (let day = first; day <= last; day++) {
    dayTimes(day, s, tzMin, random, now + LEAD_MIN * MIN).forEach((at) => add.push(at));
  }
  add.sort((a, b) => a - b);
  return { key, until: Math.max(last, until === null ? last : until), cancel, keep, add };
}

// Parametr budzika: sposób D i planowana chwila (zdjęcie losuje ekran zdjęcia z worka)
export function alarmParam(at) {
  return JSON.stringify({ m: DIRECT, at: Math.round(at / 1000) });
}

// Worek: { used: [id], last: id }. Losujemy spośród zdjęć, których w tej rundzie jeszcze nie było;
// nowe zdjęcia od razu trafiają do worka, usunięte z niego znikają. Gdy były już wszystkie - nowa runda,
// ale bez powtórzenia ostatniego. wanted: konkretne zdjęcie (np. wskazane w budziku), jeśli jest na zegarku.
export function drawFromBag(bag, ids, random, wanted) {
  const all = ids || [];
  const b = bag || {};
  if (!all.length) return { id: "", bag: { used: [], last: b.last || "" } };
  let used = (b.used || []).filter((id) => all.indexOf(id) >= 0);
  let left = all.filter((id) => used.indexOf(id) < 0);
  if (!left.length) {
    left = all;
    used = [];
  }
  let id;
  if (wanted && all.indexOf(wanted) >= 0) {
    id = wanted;
  } else {
    const fresh = left.length > 1 ? left.filter((x) => x !== b.last) : left;
    id = fresh[Math.floor(random() * fresh.length)];
  }
  return { id, bag: { used: used.indexOf(id) >= 0 ? used : used.concat([id]), last: id } };
}

// --- teksty planu na ekranie ---

function two(n) {
  return (n < 10 ? "0" : "") + n;
}

export function hourText(h) {
  return h + ":00";
}

// Godzina lokalna, np. "9:05"
export function clockText(at, tzMin) {
  const m = (((Math.floor(at / MIN) + tzMin) % DAY_MIN) + DAY_MIN) % DAY_MIN;
  return Math.floor(m / 60) + ":" + two(m % 60);
}

function dayText(day, today) {
  if (day === today) return "dziś";
  if (day === today + 1) return "jutro";
  if (day === today - 1) return "wczoraj";
  const d = new Date(day * DAY_MIN * MIN);
  return two(d.getUTCDate()) + "." + two(d.getUTCMonth() + 1);
}

// Najbliższe pokazy pogrupowane po dniach, np. ["dziś 14:23, 18:51", "jutro 10:12, 13:40, 19:05"]
export function upcomingLines(items, now, tzMin) {
  const today = localDay(now, tzMin);
  const days = [];
  const byDay = {};
  (items || [])
    .filter((it) => it && it.at > now)
    .sort((a, b) => a.at - b.at)
    .forEach((it) => {
      const day = localDay(it.at, tzMin);
      if (!byDay[day]) {
        byDay[day] = [];
        days.push(day);
      }
      byDay[day].push(clockText(it.at, tzMin));
    });
  return days.map((day) => dayText(day, today) + " " + byDay[day].join(", "));
}

// Najbliższy pokaz jedną linią, np. "dziś 14:23"
export function nextText(items, now, tzMin) {
  const lines = upcomingLines(items, now, tzMin);
  return lines.length ? lines[0].split(", ")[0] : "";
}

// Dowolna chwila względem dziś, np. "wczoraj 19:40"
export function whenText(at, now, tzMin) {
  return dayText(localDay(at, tzMin), localDay(now, tzMin)) + " " + clockText(at, tzMin);
}

function upcoming(plan, now) {
  return ((plan && plan.items) || []).filter((it) => it && it.at > now);
}

// Linia na panelu domowym
export function nextLine(plan, now, tzMin) {
  if (plan && plan.key === "off") return "Losowe zdjęcia wyłączone";
  const next = nextText(upcoming(plan, now).filter((it) => it.alarm), now, tzMin);
  return next ? "Następne zdjęcie: " + next : "Brak zaplanowanych zdjęć";
}

// Stan planu na ekranie ustawień
export function planLines(plan, now, tzMin) {
  if (plan && plan.key === "off") return ["Wyłączone - zegarek sam nie pokaże zdjęć."];
  const items = upcoming(plan, now);
  const days = upcomingLines(items.filter((it) => it.alarm), now, tzMin);
  const lines = days.length ? ["Najbliższe zdjęcia:"].concat(days) : ["Brak zaplanowanych zdjęć."];
  const failed = items.filter((it) => !it.alarm).length;
  if (failed) lines.push("Nie ustawiono budzików: " + failed);
  return lines;
}
