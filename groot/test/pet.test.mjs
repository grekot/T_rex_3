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
  nextReminder,
  tzFrom,
  LINES,
  LINE_ORDER,
  FORM_ORDER,
  NAMES,
  chooseEgg,
  setName,
  displayName,
  setWalk,
  getWalk,
  treat,
  REQUEST,
  setBonus,
  activeRequest,
  requestText,
  canPlay as canPlayFor,
  localMinute as lm,
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
    form: "groot",
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
function life(hours, seed, maxDays = 40, line = "classic") {
  let s = newEgg(at(0, 9, 55), seed, null, line);
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
  assert.equal(r.state.form, "kielek");
  assert.equal(r.state.hatched, at(0, 10, 3));
  assert.equal(r.state.hunger, 2);
  assert.equal(r.state.weight, 5);
  assert.deepEqual(r.state.seen, ["kielek"]);
  assert.equal(lastNews(r.events), "Wykiełkował!");
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

test("światło: drugie naciśnięcie w nocy go nie zapala", () => {
  let s = toggleLight(adultAt(at(1, 21)), TZ).state;
  assert.equal(s.light, false);
  const again = toggleLight(s, TZ);
  assert.equal(again.state.light, false);
  assert.equal(again.state.asleep, true);
  // zgaszone wieczorem zostaje zgaszone do rana, także po przewinięciu czasu
  s = run(s, at(2, 3));
  assert.equal(s.light, false);
  assert.equal(s.asleep, true);
  // śpi przy zapalonym (o 21:30 sam zasnął) - wtedy można zgasić
  const lit = run(adultAt(at(1, 21)), at(1, 22));
  assert.equal(lit.asleep && lit.light, true);
  assert.equal(toggleLight(lit, TZ).state.light, false);
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
  assert.equal(r.msg, "Mszyce zniknęły!");
  assert.equal(medicine(r.state).anim, "no");
});

test("chory nie bawi się i nie je przekąsek", () => {
  const s = adultAt(at(1, 10));
  s.sick = 1;
  assert.equal(canPlay(s), "Ma mszyce");
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
  assert.equal(meal(s).msg, "Już podlany");
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
  assert.equal(s.form, "kielek");
  const good = run(care(s), at(0, 10, 5));
  assert.equal(good.form, "grocik");
  const bad = clone(s);
  bad.mistakes = 1;
  assert.equal(nextForm(bad), "suchar");
  for (const [m, form] of [
    [0, "nastek"],
    [2, "nastek"],
    [3, "kolczak"],
  ])
    assert.equal(nextForm({ ...s, form: "grocik", mistakes: m }), form);
  assert.equal(nextForm({ ...s, form: "suchar", mistakes: 1 }), "nastek", "z Gapcia da się wyjść");
  assert.equal(nextForm({ ...s, form: "suchar", mistakes: 2 }), "kolczak");
  assert.equal(nextForm({ ...s, form: "nastek", mistakes: 0, discipline: 2 }), "groot");
  assert.equal(nextForm({ ...s, form: "nastek", mistakes: 0, discipline: 1 }), "mszak");
  assert.equal(nextForm({ ...s, form: "nastek", mistakes: 4 }), "mszak");
  assert.equal(nextForm({ ...s, form: "nastek", mistakes: 5 }), "prochniak");
  assert.equal(nextForm({ ...s, form: "kolczak", mistakes: 1 }), "mszak");
  assert.equal(nextForm({ ...s, form: "kolczak", mistakes: 2 }), "prochniak");
  assert.equal(nextForm({ ...s, form: "groot" }), null);
});

function clone(o) {
  return JSON.parse(JSON.stringify(o));
}

test("linie: każde jajko ma własne formy, zaniedbane są wspólne", () => {
  for (const line of LINE_ORDER) {
    const L = LINES[line];
    const egg = newEgg(at(0, 10), 5, null, line, "Kiwi");
    assert.equal(egg.line, line);
    assert.equal(egg.name, "Kiwi");
    const baby = run(egg, at(0, 10, 4));
    assert.equal(baby.form, L.baby);
    assert.equal(displayName(baby), "Kiwi");
    assert.equal(nextForm({ ...baby, mistakes: 0 }), L.child);
    assert.equal(nextForm({ ...baby, mistakes: 1 }), "suchar");
    assert.equal(nextForm({ ...baby, form: L.child, mistakes: 0 }), L.teen);
    assert.equal(nextForm({ ...baby, form: L.teen, mistakes: 0, discipline: 3 }), L.best);
    assert.equal(nextForm({ ...baby, form: L.teen, mistakes: 3 }), L.good);
    assert.equal(nextForm({ ...baby, form: "kolczak", mistakes: 0 }), L.good);
    for (const f of [L.baby, L.child, L.teen, L.best, L.good]) assert.ok(FORMS[f], f);
    // troskliwy opiekun dochodzi do formy z tej linii
    const l = life([8, 13, 20.5], 3, 40, line);
    assert.equal(l.s.gone, "old");
    assert.deepEqual(l.forms.slice(0, 3), [L.baby, L.child, L.teen]);
    assert.ok([L.best, L.good].includes(l.forms[3]), l.forms.join(">"));
  }
  assert.equal(FORM_ORDER.length, 18);
  assert.equal(new Set(FORM_ORDER).size, 18);
  // stary stan bez linii = drapieżniki, bez imienia = nazwa formy
  const old = hatched();
  delete old.line;
  delete old.name;
  assert.equal(nextForm({ ...old, mistakes: 0 }), "grocik");
  assert.equal(displayName(old), "Kiełek");
});

test("wybór jajka i imienia", () => {
  const egg = newEgg(at(0, 10), 5);
  const chosen = chooseEgg(run(egg, at(0, 10, 2)), at(0, 10, 2), 9, "autumn", "Figa");
  assert.equal(chosen.line, "autumn");
  assert.equal(chosen.name, "Figa");
  assert.equal(chosen.gen, 1);
  assert.equal(run(chosen, at(0, 10, 4)).form, "egg", "wylęganie od nowa od wyboru");
  assert.equal(run(chosen, at(0, 10, 5)).form, "zoladz");
  // dorosły pupil: tylko zmiana imienia
  const s = adultAt(at(1, 10));
  const renamed = chooseEgg(s, at(1, 10), 1, "bloom", "Bruno");
  assert.equal(renamed.form, "groot");
  assert.equal(renamed.name, "Bruno");
  assert.equal(setName(renamed, "").name, "");
  // po odejściu: nowe jajo z wybranej linii, kolekcja zostaje
  const gone = { ...s, gone: "old", seen: ["kielek", "groot"] };
  const next = chooseEgg(gone, at(20, 9), 4, "bloom", "Pestka");
  assert.equal(next.form, "egg");
  assert.equal(next.line, "bloom");
  assert.equal(next.gen, s.gen + 1);
  assert.deepEqual(next.seen, ["kielek", "groot"]);
  assert.ok(NAMES.includes("") && NAMES.length > 10);
});

test("ewolucja czeka, aż się obudzi", () => {
  const egg = newEgg(at(0, 21), 9);
  const baby = run(egg, at(0, 21, 5));
  assert.equal(baby.form, "kielek");
  assert.equal(baby.asleep, false);
  const night = run(baby, at(1, 6));
  assert.equal(night.asleep, true);
  assert.equal(night.form, "kielek");
  const morning = run(baby, at(1, 8));
  assert.notEqual(morning.form, "kielek");
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
  assert.equal(statusText(r.state, TZ), "Odszedł do lasu…");
  assert.equal(lastNews(r.events), "Odszedł do lasu");
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
  s.seen = ["kielek", "grocik", "nastek", "groot"];
  const gone = run(s, at(10, 8));
  const egg = restart(gone, at(10, 9), 77);
  assert.equal(egg.gen, gone.gen + 1);
  assert.equal(egg.form, "egg");
  assert.deepEqual(egg.seen, s.seen);
  assert.equal(egg.history.length, 1);
  assert.equal(egg.history[0].reason, "forest");
  assert.equal(egg.history[0].form, "groot");
});

test("restore odrzuca śmieci", () => {
  assert.equal(restore(""), null);
  assert.equal(restore("{zepsute"), null);
  assert.equal(restore('{"v":2}'), null);
  const s = hatched();
  assert.deepEqual(restore(JSON.stringify(s)), s);
});

test("tzFrom: strefa z godziny lokalnej", () => {
  const u = (h, m) => Date.UTC(2026, 9, 22, h, m);
  assert.equal(tzFrom(22 * 60 + 5, u(20, 5)), 120, "Polska latem: UTC+2");
  assert.equal(tzFrom(30, u(22, 30)), 120, "przez północ");
  assert.equal(tzFrom(21 * 60, u(20, 0)), 60, "zimą UTC+1");
  assert.equal(tzFrom(23 * 60, u(4, 0)), -300, "strefa ujemna");
  assert.equal(tzFrom(22 * 60 + 6, u(20, 5) + 59000), 120, "zegary minimalnie przesunięte");
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
    assert.equal(l.forms[1], "grocik");
    assert.equal(l.forms[2], "nastek");
  }
  const adults = lives.map((l) => l.forms[3]);
  assert.ok(adults.every((f) => f === "groot" || f === "mszak"), adults.join(","));
  assert.ok(adults.filter((f) => f === "groot").length >= 4, adults.join(","));
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

test("przypomnienie: pierwsza potrzeba w dzień, nigdy w nocy", () => {
  const s = adultAt(at(1, 9));
  s.timers = { hunger: 100000, happy: 100000, poop: 120, whim: 100000 };
  // kupa za 2 h -> przypomnienie wtedy
  assert.equal(nextReminder(s, at(1, 9), TZ), at(1, 11));
  // kupa wypadłaby w nocy... (sen wstrzymuje liczniki) - zostaje światło o 21:30
  const evening = adultAt(at(1, 20, 30));
  evening.timers = { hunger: 100000, happy: 100000, poop: 100000, whim: 100000 };
  assert.equal(nextReminder(evening, at(1, 20, 30), TZ), at(1, 21, 30));
  // po zgaszeniu światła: rano, po pobudce coś znowu spadnie
  const night = toggleLight(adultAt(at(1, 21)), TZ).state;
  night.timers = { hunger: 30, happy: 100000, poop: 100000, whim: 100000 };
  night.hunger = 1;
  // rano pierwsze jest zaproszenie na rozgrzewkę (7:45, przypomnienia nie wcześniej)
  assert.equal(nextReminder(night, at(1, 21), TZ), at(2, 7, 45));
  // już czegoś potrzebuje: za 2 h, ale nie w nocy
  const dirty = adultAt(at(1, 12));
  dirty.poops = 1;
  dirty.poopAt = dirty.t;
  assert.equal(nextReminder(dirty, at(1, 12), TZ), at(1, 14));
  const late = adultAt(at(1, 21, 30));
  late.poops = 1;
  const lr = nextReminder(late, at(1, 21, 30), TZ);
  assert.ok(lm(lr, TZ) >= 7 * 60 + 45 && lr < at(2, 9), new Date(lr).toISOString());
  // jajo i odejście - bez przypomnień
  assert.equal(nextReminder(newEgg(at(1, 9), 1), at(1, 9), TZ), 0);
  assert.equal(nextReminder({ ...s, gone: "old" }, at(1, 9), TZ), 0);
  // stan wejściowy się nie zmienia
  assert.equal(s.t, at(1, 9));
});

test("zadania spacerowe i nagroda za spacer", () => {
  const s = adultAt(at(1, 10));
  s.happy = 1;
  const w = setWalk(s, "trip", { lat: 50, lon: 20, t0: 1 });
  assert.deepEqual(getWalk(w, "trip"), { lat: 50, lon: 20, t0: 1 });
  assert.equal(getWalk(s, "trip"), null, "stan wejściowy bez zmian");
  assert.equal(getWalk(setWalk(w, "trip", null), "trip"), null);
  const t = treat(w, 2);
  assert.equal(t.state.happy, 3);
  assert.equal(t.state.weight, 30);
  assert.equal(treat(newEgg(at(1, 9), 1), 2).anim, "no");
  // przewijanie czasu zachowuje zadania
  assert.deepEqual(run(w, at(1, 12)).walks, w.walks);
});

test("prośba o zabawę: mniej więcej raz dziennie, wygasa bez kary", () => {
  const s = adultAt(at(1, 8));
  s.timers = { hunger: 100000, happy: 100000, poop: 100000, whim: 100000, ask: 60 };
  const r = advance(s, at(1, 9, 30), TZ);
  const req = activeRequest(r.state);
  assert.ok(req, "brak prośby");
  assert.equal(req.kind, "ask");
  assert.ok(requestText(req).startsWith("Chce zagrać: "));
  assert.equal(statusText(r.state, TZ), requestText(req));
  assert.equal(lastNews(r.events), requestText(req));
  // po 3 godzinach przechodzi, bez błędu opieki
  const later = run(r.state, at(1, 9) + REQUEST.ttl + 5 * MIN);
  assert.equal(activeRequest(later), null);
  assert.equal(later.mistakes, 0);
  // przez tydzień troskliwego życia: około jednej prośby na dzień
  const l = life([8, 13, 20.5], 5);
  const asks = l.events.filter((e) => e.type === "ask").length;
  const days = l.days;
  assert.ok(asks > days * 0.5 && asks < days * 2, asks + " próśb przez " + days.toFixed(1) + " dni");
});

test("spełniona prośba daje dodatkowy humor, przegrana jej nie zabiera", () => {
  const s = adultAt(at(1, 10));
  s.happy = 1;
  s.request = { game: "reflex", kind: "ask", t: s.t, until: s.t + REQUEST.ttl };
  const lost = play(s, false, "reflex");
  assert.ok(activeRequest(lost.state), "po przegranej można spróbować jeszcze raz");
  const other = play(s, true, "catch");
  assert.equal(other.state.happy, 2);
  assert.ok(activeRequest(other.state));
  const won = play(s, true, "reflex");
  assert.equal(won.state.happy, 3);
  assert.equal(won.msg, "Prośba spełniona!");
  assert.equal(activeRequest(won.state), null);
});

test("poranna rozgrzewka po pobudce", () => {
  const s = toggleLight(adultAt(at(1, 21)), TZ).state;
  s.timers = { hunger: 100000, happy: 100000, poop: 100000, whim: 100000, ask: 100000 };
  const r = advance(s, at(2, 8), TZ);
  const req = activeRequest(r.state);
  assert.equal(req.kind, "morning");
  assert.equal(req.game, "warmup");
  assert.equal(lastNews(r.events), "Poranna rozgrzewka!");
  assert.equal(statusText(r.state, TZ), "Poranna rozgrzewka!");
  const done = play(r.state, true, "warmup");
  assert.equal(done.msg, "Poranna premia!");
  // przechodzi koło 11:30
  assert.equal(activeRequest(run(r.state, at(2, 11, 31))), null);
  // maluch nie dostaje zaproszeń
  const baby = toggleLight({ ...adultAt(at(1, 21)), form: "kielek" }, TZ).state;
  assert.equal(activeRequest(run(baby, at(2, 8))), null);
});

test("gra o premię po akcji", () => {
  let s = adultAt(at(1, 10));
  s.happy = 1;
  s = setBonus(s, "snack", s.t);
  assert.equal(s.bonus.game, "catch");
  const won = play(s, true, "catch");
  assert.equal(won.state.happy, 3);
  assert.equal(won.msg, "Premia!");
  assert.equal(won.state.bonus, null);
  // przegrana zużywa premię
  assert.equal(play(s, false, "catch").state.bonus, null);
  // wygasa po kwadransie
  assert.equal(run(s, at(1, 10, 20)).bonus, null);
  // lekarstwo: chory może zagrać w celowanie, wygrana leczy od razu
  let sick = adultAt(at(1, 10));
  sick.sick = 1;
  assert.equal(canPlayFor(sick, "aim"), "Ma mszyce");
  sick = setBonus(sick, "medicine", sick.t);
  assert.equal(canPlayFor(sick, "aim"), "");
  assert.equal(canPlayFor(sick, "catch"), "Ma mszyce");
  const cured = play(sick, true, "aim");
  assert.equal(cured.state.sick, 0);
  assert.equal(cured.msg, "Bez mszyc!");
});

if (failed) {
  console.error(failed + " test(y) nie przeszły");
  process.exit(1);
}
console.log("pet: wszystkie testy przeszły");
