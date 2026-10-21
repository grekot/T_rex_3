import assert from "node:assert/strict";
import {
  MIN,
  HOUR,
  DAY,
  CALLS,
  WHIM_LEN,
  NEGLECT_LIMIT,
  FORMS,
  newEgg,
  restore,
  advance,
  meal,
  snack,
  play,
  toggleLight,
  medicine,
  clean,
  scold,
  restart,
  canPlay,
  nextForm,
  localMinute,
  moodOf,
  statusText,
  needsAttention,
  lastNews,
  ageDays,
} from "../utils/pet.js";

let failed = 0;
function test(name, fn) {
  try {
    fn();
  } catch (e) {
    failed++;
    console.error("BŁĄD: " + name + "\n  " + e.message);
  }
}

// Strefa UTC w testach: at(dzień, godzina, minuta)
const T0 = Date.UTC(2026, 9, 21);
const at = (d, h, m = 0) => T0 + d * DAY + h * HOUR + m * MIN;
const TZ = 0;

function run(s, now) {
  return advance(s, now, TZ).state;
}

// Pupil już po wykluciu, dzień 0 o 8:00 (jajo złożone 7:50)
function hatched(seed = 1) {
  return run(newEgg(at(0, 7, 50), seed), at(0, 8));
}

// Ustawia etap i "pełne" statystyki do testu jednej rzeczy
function adultAt(t, seed = 7) {
  const s = hatched(seed);
  Object.assign(s, {
    form: "rex",
    stageAt: t - DAY,
    t,
    hunger: 4,
    happy: 4,
    discipline: 4,
    weight: 30,
    poops: 0,
    poopAt: 0,
    mistakes: 0,
    totalMistakes: 0,
  });
  s.timers = { hunger: 300, happy: 270, poop: 300, whim: 1200 };
  return s;
}

// Opiekun, który zagląda co jakiś czas i robi wszystko, czego trzeba
function care(s) {
  s = clean(s).state;
  for (let i = 0; i < 3 && s.sick; i++) s = medicine(s).state;
  if (s.whim) s = scold(s).state;
  for (let i = 0; i < 6 && s.hunger < 4; i++) s = meal(s).state;
  for (let i = 0; i < 5 && s.happy < 4 && !canPlay(s); i++) s = play(s, true).state;
  if (!s.asleep || s.light) {
    const r = toggleLight(s, TZ);
    if (r.msg === "Dobranoc") s = r.state;
  }
  return s;
}

// Całe życie od jajka: opiekun zagląda o podanych godzinach
function life(hours, seed, maxDays = 40) {
  let s = newEgg(at(0, 9, 55), seed);
  const forms = [];
  const events = [];
  for (let d = 0; d < maxDays && !s.gone; d++) {
    for (const h of hours) {
      const t = at(d, Math.floor(h), Math.round((h % 1) * 60));
      if (t <= s.t) continue;
      const r = advance(s, t, TZ);
      s = r.state;
      events.push(...r.events);
      if (s.gone) break;
      s = care(s);
    }
  }
  if (!s.gone) s = run(s, at(maxDays, 12));
  for (const e of events) if (e.form) forms.push(e.form);
  return { s, forms, events, days: (s.goneAt - s.hatched) / DAY };
}

test("jajo wykluwa się po 3 minutach", () => {
  const egg = newEgg(at(0, 10), 5);
  assert.equal(run(egg, at(0, 10, 2)).form, "egg");
  const r = advance(egg, at(0, 10, 3), TZ);
  assert.equal(r.state.form, "pisklak");
  assert.equal(r.state.hatched, at(0, 10, 3));
  assert.equal(r.state.hunger, 2);
  assert.equal(r.state.weight, 5);
  assert.deepEqual(r.state.seen, ["pisklak"]);
  assert.equal(lastNews(r.events), "Wykluł się!");
});

test("8 h bez jedzenia w dzień: dorosły traci 1-2 serca głodu", () => {
  for (let seed = 1; seed <= 30; seed++) {
    const s = adultAt(at(1, 8), seed);
    s.timers.hunger = 1 + (seed * 37) % 300;
    const after = run(s, at(1, 16));
    assert.ok(after.hunger >= 2 && after.hunger <= 3, "seed " + seed + ": " + after.hunger);
    assert.equal(after.mistakes, 0);
  }
});

test("w nocy nic nie spada, rano światło zapala się samo", () => {
  let s = adultAt(at(1, 21));
  s = toggleLight(s, TZ).state;
  assert.equal(s.asleep, true);
  const before = { hunger: s.hunger, happy: s.happy, poops: s.poops };
  const night = run(s, at(2, 7, 29));
  assert.equal(night.asleep, true);
  assert.deepEqual({ hunger: night.hunger, happy: night.happy, poops: night.poops }, before);
  const morning = run(s, at(2, 7, 31));
  assert.equal(morning.asleep, false);
  assert.equal(morning.light, true);
  assert.equal(morning.mistakes, 0);
});

test("za wcześnie nie da się zgasić światła", () => {
  const s = adultAt(at(1, 15));
  const r = toggleLight(s, TZ);
  assert.equal(r.state.light, true);
  assert.equal(r.anim, "no");
});

test("sam zasypia o 21:30; zapalone światło = jeden błąd na noc", () => {
  const s = adultAt(at(1, 20));
  const asleep = run(s, at(1, 21, 45));
  assert.equal(asleep.asleep, true);
  assert.equal(asleep.mistakes, 0);
  assert.equal(statusText(asleep, TZ), "Zgaś światło!");
  assert.equal(needsAttention(asleep), true);
  const late = run(s, at(2, 6));
  assert.equal(late.mistakes, 1);
  // zgaszone w porę - bez błędu
  const ok = run(toggleLight(asleep, TZ).state, at(2, 6));
  assert.equal(ok.mistakes, 0);
  assert.equal(needsAttention(ok), false);
});

test("głód na zero: błąd po 3 h czuwania, kolejny po 12 h, noc wstrzymuje", () => {
  const s = adultAt(at(1, 9));
  s.hunger = 0;
  s.timers.happy = 100000;
  s.timers.poop = 100000;
  s.timers.whim = 100000;
  assert.equal(run(s, at(1, 11, 59)).mistakes, 0);
  assert.equal(run(s, at(1, 12, 1)).mistakes, 1);
  // 12 h czuwania po 12:00: 12:00-21:30 (9,5 h) + 7:30-10:00 następnego dnia
  const next = run(s, at(2, 9, 59));
  assert.equal(next.mistakes, 1 + 1); // + błąd za zapalone światło w nocy
  assert.equal(run(s, at(2, 10, 1)).mistakes, 3);
  // jedzenie kończy wołanie
  let fed = run(s, at(1, 11));
  for (let i = 0; i < 4; i++) fed = meal(fed).state;
  fed = run(fed, at(1, 14));
  assert.equal(fed.mistakes, 0);
});

test("kupa leżąca długo grozi chorobą, lekarstwo leczy", () => {
  let sickCount = 0;
  for (let seed = 1; seed <= 40; seed++) {
    const s = adultAt(at(1, 8), seed);
    s.poops = 2;
    s.poopAt = at(1, 8);
    s.timers.poop = 100000;
    const early = run(s, at(1, 13, 59));
    assert.equal(early.sick, 0, "przed 6 h nie choruje");
    const later = run(s, at(1, 20));
    if (later.sick) sickCount++;
  }
  // 6 h po kupie, 2 kupy po 12%/h -> ok. 75% szans w ciągu 6 h
  assert.ok(sickCount > 20 && sickCount < 40, "zachorowało " + sickCount + "/40");

  const s = adultAt(at(1, 8), 3);
  s.sick = 2;
  let r = medicine(s);
  assert.equal(r.state.sick, 1);
  r = medicine(r.state);
  assert.equal(r.state.sick, 0);
  assert.equal(r.msg, "Wyzdrowiał!");
  assert.equal(medicine(r.state).anim, "no");
});

test("chory nie bawi się i nie je przekąsek", () => {
  const s = adultAt(at(1, 10));
  s.sick = 1;
  assert.equal(canPlay(s), "Jest chory");
  assert.equal(play(s, true).state.happy, s.happy);
  assert.equal(snack(s).anim, "no");
  assert.equal(moodOf(s), "sad");
});

test("jedzenie, przekąska i zabawa zmieniają wagę", () => {
  let s = adultAt(at(1, 10));
  s.hunger = 2;
  s.happy = 2;
  s = meal(s).state;
  assert.equal(s.hunger, 3);
  assert.equal(s.weight, 31);
  s = snack(s).state;
  assert.equal(s.happy, 3);
  assert.equal(s.weight, 33);
  s = play(s, true).state;
  assert.equal(s.happy, 4);
  assert.equal(s.weight, 32);
  s = play(s, false).state;
  assert.equal(s.weight, 31);
  s = play(play(s, false).state, false).state;
  assert.equal(s.weight, 30, "nie schodzi poniżej normy etapu");
  s.hunger = 4;
  assert.equal(meal(s).msg, "Już najedzony");
});

test("dyscyplina: zganienie marudzenia pomaga, niesłuszne smuci, przeoczone to błąd", () => {
  const s = adultAt(at(1, 10));
  s.discipline = 1;
  s.whim = s.t;
  const ok = scold(s);
  assert.equal(ok.state.discipline, 2);
  assert.equal(ok.state.whim, 0);
  const unfair = scold(ok.state);
  assert.equal(unfair.state.happy, 3);
  assert.equal(unfair.anim, "sad");
  s.timers.hunger = s.timers.happy = s.timers.poop = s.timers.whim = 100000;
  const missed = run(s, s.t + WHIM_LEN + MIN);
  assert.equal(missed.whim, 0);
  assert.equal(missed.mistakes, 1);
});

test("mało dyscypliny: dorosły czasem kręci nosem na jedzenie", () => {
  let refused = 0;
  for (let seed = 1; seed <= 200; seed++) {
    const s = adultAt(at(1, 10), seed);
    s.hunger = 1;
    s.discipline = 0;
    if (meal(s).msg === "Kręci nosem…") refused++;
  }
  assert.ok(refused > 20 && refused < 70, "odmów " + refused);
});

test("ewolucja według błędów opieki", () => {
  const s = hatched();
  assert.equal(s.form, "pisklak");
  const good = run(care(s), at(0, 10, 5));
  assert.equal(good.form, "tupek");
  const bad = clone(s);
  bad.mistakes = 1;
  assert.equal(nextForm(bad), "gapcio");
  for (const [m, form] of [
    [0, "rogal"],
    [1, "rogal"],
    [2, "kolec"],
    [3, "kolec"],
    [4, "lobuz"],
  ])
    assert.equal(nextForm({ ...s, form: "tupek", mistakes: m }), form);
  assert.equal(nextForm({ ...s, form: "rogal", mistakes: 0, discipline: 2 }), "rex");
  assert.equal(nextForm({ ...s, form: "rogal", mistakes: 0, discipline: 1 }), "szyjek");
  assert.equal(nextForm({ ...s, form: "kolec", mistakes: 5 }), "ptero");
  assert.equal(nextForm({ ...s, form: "lobuz", mistakes: 9 }), "burczek");
  assert.equal(nextForm({ ...s, form: "rex" }), null);
});

function clone(o) {
  return JSON.parse(JSON.stringify(o));
}

test("ewolucja czeka, aż się obudzi", () => {
  const egg = newEgg(at(0, 21), 9);
  const baby = run(egg, at(0, 21, 5));
  assert.equal(baby.form, "pisklak");
  assert.equal(baby.asleep, false);
  const night = run(baby, at(1, 6));
  assert.equal(night.asleep, true);
  assert.equal(night.form, "pisklak");
  const morning = run(baby, at(1, 8));
  assert.notEqual(morning.form, "pisklak");
});

test("przewijanie kawałkami daje ten sam wynik co od razu", () => {
  const s = hatched(42);
  const whole = run(s, at(3, 15, 30));
  let parts = s;
  for (let t = s.t; t < at(3, 15, 30); t += 37 * MIN + 13000) parts = run(parts, t);
  parts = run(parts, at(3, 15, 30));
  assert.deepEqual(parts, whole);
});

test("cofnięty zegar niczego nie psuje", () => {
  const s = run(hatched(), at(0, 12));
  const back = advance(s, at(0, 9), TZ);
  assert.equal(back.events.length, 0);
  assert.equal(back.state.hunger, s.hunger);
  const again = run(back.state, at(0, 9, 30));
  assert.ok(again.t <= at(0, 9, 30));
});

test("porzucony dorosły ucieka do lasu po długim zaniedbaniu", () => {
  const s = adultAt(at(1, 8));
  const r = advance(s, at(10, 8), TZ);
  assert.equal(r.state.gone, "forest");
  const days = (r.state.goneAt - s.t) / DAY;
  assert.ok(days > 2 && days < 5, "po " + days.toFixed(1) + " dniach");
  assert.equal(statusText(r.state, TZ), "Uciekł do lasu…");
  assert.equal(lastNews(r.events), "Uciekł do lasu");
  // po odejściu czas już nic nie zmienia
  assert.deepEqual(run(r.state, at(20, 8)), r.state);
});

test("zaniedbanie zeruje się po opiece", () => {
  const s = adultAt(at(1, 8));
  s.hunger = 0;
  const hungry = run(s, at(1, 20));
  assert.ok(hungry.neglect > 0);
  const fed = run(meal(hungry).state, at(1, 20, 1));
  assert.equal(fed.neglect, 0);
  assert.ok(NEGLECT_LIMIT > 12 * HOUR);
});

test("nowe jajo zachowuje kolekcję i historię", () => {
  const s = adultAt(at(1, 8));
  s.seen = ["pisklak", "tupek", "rogal", "rex"];
  const gone = run(s, at(10, 8));
  const egg = restart(gone, at(10, 9), 77);
  assert.equal(egg.gen, gone.gen + 1);
  assert.equal(egg.form, "egg");
  assert.deepEqual(egg.seen, s.seen);
  assert.equal(egg.history.length, 1);
  assert.equal(egg.history[0].reason, "forest");
  assert.equal(egg.history[0].form, "rex");
});

test("restore odrzuca śmieci", () => {
  assert.equal(restore(""), null);
  assert.equal(restore("{zepsute"), null);
  assert.equal(restore('{"v":2}'), null);
  const s = hatched();
  assert.deepEqual(restore(JSON.stringify(s)), s);
});

test("localMinute uwzględnia strefę", () => {
  assert.equal(localMinute(at(0, 22), 0), 22 * 60);
  assert.equal(localMinute(at(0, 22), 120), 0);
  assert.equal(localMinute(at(0, 1), -120), 23 * 60);
});

test("troskliwy opiekun (3 razy dziennie): długie życie i najlepsze formy", () => {
  const lives = [];
  for (let seed = 1; seed <= 12; seed++) lives.push(life([8, 13, 20.5], seed));
  for (const l of lives) {
    assert.equal(l.s.gone, "old", "seed: " + l.s.gone + " " + l.forms);
    assert.ok(l.days >= 17 && l.days <= 22, "żył " + l.days.toFixed(1));
    assert.equal(l.forms[1], "tupek");
    assert.equal(l.forms[2], "rogal");
  }
  const adults = lives.map((l) => l.forms[3]);
  assert.ok(adults.filter((f) => f === "rex" || f === "szyjek").length >= 10, adults.join(","));
});

test("zaglądanie raz dziennie wystarcza, żeby przeżył", () => {
  for (let seed = 1; seed <= 8; seed++) {
    // pierwsze godziny po wykluciu ktoś przy nim jest, potem wieczorem raz dziennie
    const l = life([10.5, 11, 11.5, 12, 20.5], seed, 1);
    let s = l.s;
    for (let d = 1; d < 40 && !s.gone; d++) s = care(run(s, at(d, 20, 30)));
    assert.equal(s.gone, "old", "seed " + seed + " -> " + s.gone);
    const days = (s.goneAt - s.hatched) / DAY;
    assert.ok(days >= 13 && days <= 22, "żył " + days.toFixed(1));
  }
});

test("zapomniany zaraz po wykluciu odchodzi w ciągu kilku dni", () => {
  const r = advance(newEgg(at(0, 10), 3), at(30, 10), TZ);
  assert.equal(r.state.gone, "forest");
  const days = (r.state.goneAt - r.state.born) / DAY;
  assert.ok(days < 4, "po " + days.toFixed(1));
});

test("wszystkie formy mają etap i nazwę, wiek liczy się od wyklucia", () => {
  for (const id in FORMS) assert.ok(FORMS[id].stage && FORMS[id].name);
  const s = hatched();
  assert.equal(ageDays({ ...s, t: at(2, 9) }), 2);
  assert.equal(ageDays({ ...s, t: at(2, 7) }), 1);
  assert.ok(CALLS.light.grace <= HOUR);
});

if (failed) {
  console.error(failed + " test(y) nie przeszły");
  process.exit(1);
}
console.log("pet: wszystkie testy przeszły");
