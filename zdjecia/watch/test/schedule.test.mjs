// `node test/schedule.test.mjs` - losowe godziny, plan budzików na kilka dni, worek bez powtórek
import assert from "node:assert/strict";
import {
  DEFAULT_SETTINGS,
  MIN_GAP_MIN,
  HORIZON_DAYS,
  LEAD_MIN,
  normalizeSettings,
  adjust,
  settingsKey,
  localDay,
  tzFromClock,
  dayTimes,
  topUp,
  alarmParam,
  drawFromBag,
  clockText,
  upcomingLines,
  nextText,
  whenText,
  nextLine,
  planLines,
} from "../utils/schedule.js";

const MIN = 60000;
const TZ = 120; // Polska latem (UTC+2)

// Przewidywalny „los”
function seq(...values) {
  let i = 0;
  return () => values[i++ % values.length];
}

// Prosty generator z ziarnem (mulberry32) - wiele losowań do sprawdzania zasad
function seeded(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Chwila w czasie lokalnym (UTC+2) jako ms UTC
function at(y, mo, d, h, mi) {
  return Date.UTC(y, mo - 1, d, h, mi) - TZ * MIN;
}

// Minuta lokalnego dnia
function minuteOfDay(ms) {
  return (((Math.floor(ms / MIN) + TZ) % 1440) + 1440) % 1440;
}

// --- ustawienia ---

assert.deepEqual(normalizeSettings(undefined), DEFAULT_SETTINGS);
assert.deepEqual(DEFAULT_SETTINGS, { on: true, perDay: 3, from: 9, to: 21, bright: 70 });
assert.deepEqual(normalizeSettings({ on: false, perDay: 30, from: -3, to: 30 }), { on: false, perDay: 24, from: 0, to: 24, bright: 70 });
assert.equal(normalizeSettings({ perDay: 9 }).perDay, 9);
assert.deepEqual(normalizeSettings({ perDay: 0, from: 22, to: 8 }), { on: true, perDay: 1, from: 22, to: 23, bright: 70 });
assert.deepEqual(normalizeSettings({ perDay: "x", from: null }), DEFAULT_SETTINGS);

assert.equal(adjust(DEFAULT_SETTINGS, "on").on, false);
assert.equal(adjust(DEFAULT_SETTINGS, "perDay", 1).perDay, 4);
// Powyżej 6 większe kroki, do 24 dziennie (testy pierwszych dni)
assert.equal(adjust({ ...DEFAULT_SETTINGS, perDay: 6 }, "perDay", 1).perDay, 8);
assert.equal(adjust({ ...DEFAULT_SETTINGS, perDay: 8 }, "perDay", -1).perDay, 6);
assert.equal(adjust({ ...DEFAULT_SETTINGS, perDay: 20 }, "perDay", 1).perDay, 24);
assert.equal(adjust({ ...DEFAULT_SETTINGS, perDay: 24 }, "perDay", 1).perDay, 24);
assert.equal(adjust({ ...DEFAULT_SETTINGS, perDay: 7 }, "perDay", 1).perDay, 8);
assert.equal(adjust({ ...DEFAULT_SETTINGS, perDay: 7 }, "perDay", -1).perDay, 6);
assert.equal(adjust({ ...DEFAULT_SETTINGS, perDay: 1 }, "perDay", -1).perDay, 1);
// „od” dosuwa „do” i odwrotnie
assert.deepEqual(adjust({ ...DEFAULT_SETTINGS, from: 20, to: 21 }, "from", 1), { on: true, perDay: 3, from: 21, to: 22, bright: 70 });
assert.deepEqual(adjust({ ...DEFAULT_SETTINGS, from: 9, to: 10 }, "to", -1), { on: true, perDay: 3, from: 8, to: 9, bright: 70 });
assert.equal(adjust({ ...DEFAULT_SETTINGS, from: 0 }, "from", -1).from, 0);
assert.equal(adjust({ ...DEFAULT_SETTINGS, to: 24 }, "to", 1).to, 24);
assert.equal(adjust({ ...DEFAULT_SETTINGS, from: 23, to: 24 }, "from", 1).from, 23);

assert.equal(settingsKey(DEFAULT_SETTINGS), "3x9-21");
assert.equal(settingsKey({ on: false }), "off");

// --- czas lokalny ---

assert.equal(localDay(at(2026, 10, 19, 0, 0), TZ), localDay(at(2026, 10, 19, 23, 59), TZ));
assert.equal(localDay(at(2026, 10, 20, 0, 0), TZ), localDay(at(2026, 10, 19, 23, 59), TZ) + 1);
assert.equal(tzFromClock(2026, 10, 19, 14, 5, Date.UTC(2026, 9, 19, 12, 5, 37)), 120);
assert.equal(tzFromClock(2026, 12, 31, 23, 30, Date.UTC(2026, 11, 31, 22, 30)), 60);
assert.equal(tzFromClock(2027, 1, 1, 0, 10, Date.UTC(2026, 11, 31, 23, 10)), 60);
assert.equal(clockText(at(2026, 10, 19, 9, 5), TZ), "9:05");
assert.equal(clockText(at(2026, 10, 19, 21, 0), TZ), "21:00");

// --- godziny w jednym dniu ---

const day = localDay(at(2026, 10, 20, 12, 0), TZ);

// Domyślnie 3 razy w 9-21: przedziały 9-13, 13-17, 17-21, odstęp co najmniej 2 h
assert.deepEqual(
  dayTimes(day, DEFAULT_SETTINGS, TZ, seq(0, 0, 0)).map((t) => clockText(t, TZ)),
  ["9:00", "13:00", "17:00"]
);
assert.deepEqual(
  dayTimes(day, DEFAULT_SETTINGS, TZ, seq(0.99, 0, 0.99)).map((t) => clockText(t, TZ)),
  // 12:57 → drugi nie wcześniej niż 14:57; ostatni tuż przed 21:00
  ["12:57", "14:57", "20:57"]
);

function checkDay(times, s, notBefore) {
  const from = s.from * 60;
  const to = s.to * 60;
  // Dziś po części okna przedziały liczone są od „teraz”
  const start = notBefore ? Math.max(from, minuteOfDay(Math.ceil(notBefore / MIN) * MIN)) : from;
  const slot = (to - start) / s.perDay;
  for (let i = 0; i < times.length; i++) {
    const m = minuteOfDay(times[i]);
    assert.ok(m >= from && m < to, "w oknie: " + clockText(times[i], TZ));
    assert.equal(times[i] % MIN, 0, "pełne minuty");
    if (notBefore) assert.ok(times[i] >= notBefore, "nie wcześniej niż teraz");
    if (i > 0) {
      const gap = (times[i] - times[i - 1]) / MIN;
      assert.ok(gap >= Math.min(MIN_GAP_MIN, Math.floor(slot / 2)), "odstęp " + gap + " min");
    }
  }
}

const settingsCases = [
  DEFAULT_SETTINGS,
  { on: true, perDay: 1, from: 9, to: 21 },
  { on: true, perDay: 6, from: 9, to: 21 },
  { on: true, perDay: 6, from: 14, to: 15 },
  { on: true, perDay: 4, from: 0, to: 24 },
  { on: true, perDay: 5, from: 7, to: 10 },
  { on: true, perDay: 24, from: 9, to: 21 },
  { on: true, perDay: 24, from: 14, to: 15 },
  { on: true, perDay: 12, from: 0, to: 24 },
];
for (const s of settingsCases) {
  for (let seed = 1; seed <= 300; seed++) {
    const times = dayTimes(day, s, TZ, seeded(seed));
    assert.equal(times.length, s.perDay);
    checkDay(times, s);
  }
}
// Domyślne ustawienia: zawsze co najmniej 2 h i w każdym z trzech przedziałów jedno zdjęcie
for (let seed = 1; seed <= 500; seed++) {
  const times = dayTimes(day, DEFAULT_SETTINGS, TZ, seeded(seed));
  times.forEach((t, i) => {
    const m = minuteOfDay(t);
    assert.ok(m >= 540 + i * 240 && m < 540 + (i + 1) * 240);
    if (i) assert.ok(t - times[i - 1] >= 120 * MIN);
  });
}
// Losowanie pokrywa całe okno (nie tylko środek przedziałów)
{
  const hours = new Set();
  for (let seed = 1; seed <= 400; seed++) {
    dayTimes(day, DEFAULT_SETTINGS, TZ, seeded(seed)).forEach((t) => hours.add(Math.floor(minuteOfDay(t) / 60)));
  }
  assert.deepEqual([...hours].sort((a, b) => a - b), [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]);
}

// Dziś po części okna: tylko później i proporcjonalnie mniej zdjęć
assert.equal(dayTimes(day, DEFAULT_SETTINGS, TZ, Math.random, at(2026, 10, 20, 8, 0)).length, 3);
assert.equal(dayTimes(day, DEFAULT_SETTINGS, TZ, Math.random, at(2026, 10, 20, 15, 0)).length, 2);
assert.equal(dayTimes(day, DEFAULT_SETTINGS, TZ, Math.random, at(2026, 10, 20, 19, 30)).length, 0);
assert.equal(dayTimes(day, DEFAULT_SETTINGS, TZ, Math.random, at(2026, 10, 20, 21, 0)).length, 0);
for (let seed = 1; seed <= 200; seed++) {
  const nb = at(2026, 10, 20, 14, 20);
  const s = { on: true, perDay: 6, from: 14, to: 15 };
  const times = dayTimes(day, s, TZ, seeded(seed), nb);
  assert.equal(times.length, 4); // 40 z 60 minut → 4 z 6
  checkDay(times, { ...s, perDay: 4 }, nb);
}

// --- plan: uzupełnianie i uzgadnianie z budzikami w systemie ---

const now = at(2026, 10, 19, 14, 30);
const today = localDay(now, TZ);

// Pierwszy plan: dziś (od 14:32) + 2 kolejne dni
const first = topUp({}, [], DEFAULT_SETTINGS, now, TZ, seeded(7));
assert.equal(first.key, "3x9-21");
assert.equal(first.until, today + HORIZON_DAYS);
assert.deepEqual(first.cancel, []);
assert.deepEqual(first.keep, []);
assert.ok(first.add.length >= 2 * 3 && first.add.length <= 3 * 3);
assert.ok(first.add.every((t) => t >= now + LEAD_MIN * MIN));
assert.ok(first.add.every((t, i) => i === 0 || t > first.add[i - 1]), "rosnąco");
assert.ok(localDay(first.add[first.add.length - 1], TZ) === today + 2);
// Plan sięga co najmniej 2 dni naprzód
assert.ok(first.add[first.add.length - 1] - now >= 2 * 24 * 3600000 - 12 * 3600000);

// Zapisany plan: budziki 101, 102, ... w systemie
let n = 100;
const plan = { key: first.key, until: first.until, items: first.add.map((t) => ({ alarm: ++n, at: t })) };
const allIds = plan.items.map((it) => it.alarm);

// Nic się nie zmieniło: wszystko zostaje, nic nowego
const again = topUp(plan, allIds, DEFAULT_SETTINGS, now + MIN, TZ, Math.random);
assert.deepEqual(again.cancel, []);
assert.deepEqual(again.add, []);
assert.equal(again.keep.length, plan.items.length);
assert.equal(again.until, plan.until);

// Budzik zadzwonił (pierwszy minął i zniknął z systemu) - plan dzień dalej, gdy minie północ
{
  const later = plan.items[0].at + MIN;
  const r = topUp(plan, allIds.slice(1), DEFAULT_SETTINGS, later, TZ, Math.random);
  assert.equal(r.keep.length, plan.items.length - 1);
  assert.deepEqual(r.cancel, []);
  if (localDay(later, TZ) === today) assert.deepEqual(r.add, []);
}
// Następnego dnia rano: dochodzi kolejny dzień, przeszłe budziki odpadają
{
  const morning = at(2026, 10, 20, 8, 0);
  const alive = plan.items.filter((it) => it.at > morning).map((it) => it.alarm);
  const r = topUp(plan, alive, DEFAULT_SETTINGS, morning, TZ, seeded(3));
  assert.equal(r.until, today + 3);
  assert.equal(r.add.length, 3);
  assert.ok(r.add.every((t) => localDay(t, TZ) === today + 3));
  assert.equal(r.keep.length, alive.length);
}
// Zgubiony budzik (system go nie ma) i nieudany (alarm 0) - ustawiamy jeszcze raz na tę samą chwilę
{
  const broken = { ...plan, items: plan.items.map((it, i) => (i === 1 ? { ...it, alarm: 0 } : it)) };
  const ids = allIds.filter((id, i) => i !== 1 && i !== 2);
  const r = topUp(broken, ids, DEFAULT_SETTINGS, now, TZ, Math.random);
  assert.deepEqual(r.add, [plan.items[1].at, plan.items[2].at]);
  assert.equal(r.keep.length, plan.items.length - 2);
}
// Budzik zadzwonił ułamek sekundy przed czasem i już go nie ma w systemie - nie ustawiamy go drugi raz
{
  const ringing = plan.items[0].at - 500;
  const r = topUp(plan, allIds.slice(1), DEFAULT_SETTINGS, ringing, TZ, Math.random);
  assert.ok(r.add.indexOf(plan.items[0].at) < 0);
  assert.equal(r.keep.length, plan.items.length - 1);
}
// Numery budzików jako tekst (gdyby system tak je podał) - te same budziki
{
  const r = topUp(plan, allIds.map(String), DEFAULT_SETTINGS, now, TZ, Math.random);
  assert.equal(r.keep.length, plan.items.length);
  assert.deepEqual(r.cancel, []);
  assert.deepEqual(r.add, []);
}
// Obce budziki aplikacji (stary plan, próby z wersji 0.3) są usuwane
{
  const r = topUp(plan, allIds.concat([7, 8]), DEFAULT_SETTINGS, now, TZ, Math.random);
  assert.deepEqual(r.cancel, [7, 8]);
}
// System nie podał listy budzików: ufamy zapisowi
{
  const r = topUp(plan, null, DEFAULT_SETTINGS, now, TZ, Math.random);
  assert.equal(r.keep.length, plan.items.length);
  assert.deepEqual(r.cancel, []);
}
// Zmiana ustawień: wszystkie stare budziki do kosza, plan od nowa
{
  const s = { ...DEFAULT_SETTINGS, perDay: 5 };
  const r = topUp(plan, allIds, s, now, TZ, seeded(9));
  assert.deepEqual(r.cancel, allIds);
  assert.deepEqual(r.keep, []);
  assert.equal(r.key, "5x9-21");
  assert.ok(r.add.length >= 2 * 5);
  // Bez listy z systemu - anulujemy to, co jest w zapisie
  assert.deepEqual(topUp(plan, null, s, now, TZ, Math.random).cancel, allIds);
}
// Wyłączone: wszystko anulowane, nic nowego
{
  const r = topUp(plan, allIds.concat([5]), { ...DEFAULT_SETTINGS, on: false }, now, TZ, Math.random);
  assert.deepEqual(r.cancel, allIds.concat([5]));
  assert.deepEqual(r.add, []);
  assert.deepEqual(r.keep, []);
  assert.equal(r.until, null);
  assert.equal(r.key, "off");
}
// Długo nieużywany zegarek (plan wygasł): od dziś
{
  const weekLater = now + 7 * 24 * 3600000;
  const r = topUp(plan, [], DEFAULT_SETTINGS, weekLater, TZ, seeded(1));
  assert.equal(r.until, localDay(weekLater, TZ) + HORIZON_DAYS);
  assert.ok(r.add.every((t) => t > weekLater));
  assert.ok(r.add.length >= 2 * 3);
}
// Próba z ekranu ustawień jest częścią planu i zostaje
{
  const withTest = { ...plan, items: plan.items.concat([{ alarm: 999, at: now + 60000, test: true }]) };
  const r = topUp(withTest, allIds.concat([999]), DEFAULT_SETTINGS, now, TZ, Math.random);
  assert.ok(r.keep.some((it) => it.test && it.alarm === 999));
  assert.deepEqual(r.cancel, []);
  // ... także po zmianie ustawień i po wyłączeniu
  const changed = topUp(withTest, allIds.concat([999]), { ...DEFAULT_SETTINGS, perDay: 2 }, now, TZ, Math.random);
  assert.deepEqual(changed.cancel, allIds);
  assert.ok(changed.keep.length === 1 && changed.keep[0].alarm === 999);
  const off = topUp(withTest, allIds.concat([999]), { on: false }, now, TZ, Math.random);
  assert.deepEqual(off.keep.map((it) => it.alarm), [999]);
  assert.deepEqual(off.add, []);
  // Zgubiona próba nie wraca, a minięta odpada
  assert.ok(!topUp(withTest, allIds, DEFAULT_SETTINGS, now, TZ, Math.random).keep.some((it) => it.test));
  assert.deepEqual(topUp(withTest, allIds.concat([999]), DEFAULT_SETTINGS, now + 90000, TZ, Math.random).cancel, [999]);
}

assert.deepEqual(JSON.parse(alarmParam(at(2026, 10, 19, 14, 0))), { m: "D", at: at(2026, 10, 19, 14, 0) / 1000 });

// --- worek ---

{
  const ids = ["a", "b", "c", "d", "e"];
  let bag = {};
  const round = [];
  for (let i = 0; i < ids.length; i++) {
    const r = drawFromBag(bag, ids, seeded(i + 1));
    round.push(r.id);
    bag = r.bag;
  }
  assert.deepEqual([...round].sort(), ids, "bez powtórek, dopóki nie było wszystkich");
  // Nowa runda: znowu wszystkie, ale nie zaczyna od ostatniego
  for (let seed = 1; seed <= 50; seed++) {
    const r = drawFromBag(bag, ids, seeded(seed));
    assert.notEqual(r.id, round[round.length - 1]);
    assert.deepEqual(r.bag.used, [r.id]);
  }
}
// Nowe zdjęcia trafiają od razu do worka, usunięte znikają
{
  const bag = { used: ["a", "b", "x"], last: "b" };
  const r = drawFromBag(bag, ["a", "b", "c", "d"], seq(0.99));
  assert.equal(r.id, "d");
  assert.deepEqual(r.bag, { used: ["a", "b", "d"], last: "d" });
}
// Zdjęcie wskazane w budziku ma pierwszeństwo, jeśli jest na zegarku
assert.equal(drawFromBag({}, ["a", "b"], seq(0), "b").id, "b");
assert.equal(drawFromBag({}, ["a", "b"], seq(0), "zz").id, "a");
assert.deepEqual(drawFromBag({ used: ["a"], last: "a" }, ["a", "b"], seq(0), "a").bag, { used: ["a"], last: "a" });
// Jedno zdjęcie - zawsze ono; brak zdjęć - pusto
assert.equal(drawFromBag({ used: ["a"], last: "a" }, ["a"], Math.random).id, "a");
assert.equal(drawFromBag({ used: ["a"], last: "a" }, [], Math.random).id, "");

// --- teksty ---

{
  const items = [
    { alarm: 1, at: at(2026, 10, 19, 10, 0) }, // już było
    { alarm: 4, at: at(2026, 10, 20, 10, 12) },
    { alarm: 2, at: at(2026, 10, 19, 15, 7) },
    { alarm: 3, at: at(2026, 10, 19, 19, 40) },
    { alarm: 5, at: at(2026, 10, 21, 9, 5) },
  ];
  assert.deepEqual(upcomingLines(items, now, TZ), ["dziś 15:07, 19:40", "jutro 10:12", "21.10 9:05"]);
  assert.equal(nextText(items, now, TZ), "dziś 15:07");
  assert.equal(nextText([], now, TZ), "");
  assert.equal(whenText(at(2026, 10, 18, 19, 40), now, TZ), "wczoraj 19:40");

  const p = { key: "3x9-21", items };
  assert.equal(nextLine(p, now, TZ), "Następne zdjęcie: dziś 15:07");
  assert.equal(nextLine({ key: "off", items: [] }, now, TZ), "Losowe zdjęcia wyłączone");
  assert.equal(nextLine({}, now, TZ), "Brak zaplanowanych zdjęć");
  assert.deepEqual(planLines(p, now, TZ), ["Najbliższe zdjęcia:", "dziś 15:07, 19:40", "jutro 10:12", "21.10 9:05"]);
  // Budzik, którego system nie ustawił (0), nie jest „najbliższy”, tylko liczony osobno
  const failed = { key: "3x9-21", items: items.map((it) => (it.alarm === 2 ? { ...it, alarm: 0 } : it)) };
  assert.equal(nextLine(failed, now, TZ), "Następne zdjęcie: dziś 19:40");
  assert.deepEqual(planLines(failed, now, TZ), [
    "Najbliższe zdjęcia:",
    "dziś 19:40",
    "jutro 10:12",
    "21.10 9:05",
    "Nie ustawiono budzików: 1",
  ]);
  assert.deepEqual(planLines({ key: "off" }, now, TZ), ["Wyłączone - zegarek sam nie pokaże zdjęć."]);
  assert.deepEqual(planLines(undefined, now, TZ), ["Brak zaplanowanych zdjęć."]);
}

console.log("schedule OK");

// --- dużo pokazów dziennie: plan tylko na dziś i jutro ---
import { horizonDays } from "../utils/schedule.js";
{
  assert.equal(horizonDays(6), HORIZON_DAYS);
  assert.equal(horizonDays(8), 1);
  const nowMany = at(2026, 10, 19, 8, 0);
  const many = topUp({}, [], { on: true, perDay: 24, from: 9, to: 21 }, nowMany, TZ, seeded(3));
  assert.equal(many.until, localDay(nowMany, TZ) + 1);
  assert.equal(many.add.length, 48);
  assert.ok(many.add.every((t, i) => i === 0 || t > many.add[i - 1]), "rosnąco, bez powtórek");
  console.log("schedule many OK");
}

// --- jasność przy zdjęciu (0 = bez zmian) ---
import { brightText, migrateSettings, BRIGHT_VERSION } from "../utils/schedule.js";
{
  // Domyślnie 70%, kroki co 10% od 50 do 100, poniżej 50 - bez zmian
  assert.equal(DEFAULT_SETTINGS.bright, 70);
  assert.equal(adjust(DEFAULT_SETTINGS, "bright", -1).bright, 60);
  assert.equal(adjust(DEFAULT_SETTINGS, "bright", 1).bright, 80);
  assert.equal(adjust({ ...DEFAULT_SETTINGS, bright: 50 }, "bright", -1).bright, 0);
  assert.equal(adjust({ ...DEFAULT_SETTINGS, bright: 0 }, "bright", -1).bright, 0);
  assert.equal(adjust({ ...DEFAULT_SETTINGS, bright: 0 }, "bright", 1).bright, 50);
  assert.equal(adjust({ ...DEFAULT_SETTINGS, bright: 90 }, "bright", 1).bright, 100);
  assert.equal(adjust({ ...DEFAULT_SETTINGS, bright: 100 }, "bright", 1).bright, 100);
  // Wartość spoza kroków (np. 65) idzie do najbliższego kroku w danym kierunku
  assert.equal(adjust({ ...DEFAULT_SETTINGS, bright: 65 }, "bright", 1).bright, 70);
  assert.equal(adjust({ ...DEFAULT_SETTINGS, bright: 65 }, "bright", -1).bright, 60);
  assert.equal(normalizeSettings({ bright: 250 }).bright, 100);
  // Zapisane 100% ze starszej wersji zmienia się raz na 70%; inne wartości i nowe zapisy zostają
  const old = { on: true, perDay: 24, from: 9, to: 21, bright: 100 };
  assert.deepEqual(migrateSettings(old, 0), { ...old, bright: 70 });
  assert.deepEqual(migrateSettings(old, BRIGHT_VERSION), old);
  assert.deepEqual(migrateSettings({ ...old, bright: 60 }, 0), { ...old, bright: 60 });
  assert.deepEqual(migrateSettings({ ...old, bright: 0 }, 0), { ...old, bright: 0 });
  assert.equal(migrateSettings(null, 0), null);
  assert.equal(normalizeSettings(migrateSettings({ perDay: 3 }, 0)).bright, 70);
  assert.equal(brightText(0), "bez zmian");
  assert.equal(brightText(80), "80%");
  // Jasność nie zmienia planu pokazów
  assert.equal(settingsKey({ ...DEFAULT_SETTINGS, bright: 60 }), settingsKey(DEFAULT_SETTINGS));
  console.log("schedule bright OK");
}
