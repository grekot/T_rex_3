// Pupil - logika tamagotchi bez zależności od zegarka (testy w Node: test/pet.test.mjs).
//
// Stan to zwykły obiekt JSON zapisywany w LocalStorage razem ze znacznikiem czasu `t`.
// Po otwarciu aplikacji `advance()` przewija czas minuta po minucie od `t` do teraz,
// więc wszystko, co działo się przy zamkniętej aplikacji (głód, kupy, sen, choroba,
// ewolucja, odejście), wylicza się tak samo, jakby aplikacja była cały czas otwarta.
// Losowość pochodzi z generatora zapisanego w stanie (mulberry32), więc ten sam stan
// i ten sam czas zawsze dają ten sam wynik - także przy przewijaniu kawałkami.

export const MIN = 60000;
export const HOUR = 60 * MIN;
export const DAY = 24 * HOUR;
export const TICK = MIN;
export const MAX_HEARTS = 4;
export const MAX_POOPS = 4;

// Najdłuższe przewijanie (po dłuższym czasie i tak nie ma już kogo symulować)
const MAX_CATCHUP = 40 * DAY;

// Pory dnia (minuty od północy, czas lokalny). Od SLEEPY robi się senny - wtedy można
// zgasić światło, o BED zasypia sam, o WAKE wstaje i światło zapala się samo.
export const SLEEP = { sleepy: 20 * 60, bed: 21 * 60 + 30, wake: 7 * 60 + 30 };

// Etapy życia. Odstępy (hunger/happy/poop/whim) to minuty czuwania - w nocy nic nie spada.
// len = jak długo trwa etap (liczy się tylko czuwanie przy przejściu, patrz evolveDue).
export const STAGES = {
  egg: { len: 3 * MIN, weight: 0 },
  baby: { len: 2 * HOUR, hunger: 60, happy: 60, poop: 70, whim: 0, weight: 5 },
  child: { len: DAY, hunger: 180, happy: 180, poop: 200, whim: 600, weight: 10 },
  teen: { len: 3 * DAY, hunger: 240, happy: 210, poop: 260, whim: 720, weight: 20 },
  adult: { len: Infinity, hunger: 300, happy: 270, poop: 300, whim: 1200, weight: 30 },
};

export const FORMS = {
  egg: { stage: "egg", name: "Jajo" },
  pisklak: { stage: "baby", name: "Pisklak" },
  tupek: { stage: "child", name: "Tupek" },
  gapcio: { stage: "child", name: "Gapcio" },
  rogal: { stage: "teen", name: "Rogal" },
  kolec: { stage: "teen", name: "Kolec" },
  lobuz: { stage: "teen", name: "Łobuz" },
  rex: { stage: "adult", name: "Rex" },
  szyjek: { stage: "adult", name: "Szyjek" },
  ptero: { stage: "adult", name: "Ptero" },
  burczek: { stage: "adult", name: "Burczek" },
};
// Kolejność w kolekcji
export const FORM_ORDER = ["pisklak", "tupek", "gapcio", "rogal", "kolec", "lobuz", "rex", "szyjek", "ptero", "burczek"];

// Ile czasu (czuwania) można zwlekać z potrzebą, zanim liczy się błąd opieki,
// i co ile liczy się kolejny, jeśli potrzeba dalej trwa (0 = tylko raz).
export const CALLS = {
  hunger: { grace: 3 * HOUR, repeat: 12 * HOUR },
  happy: { grace: 3 * HOUR, repeat: 12 * HOUR },
  sick: { grace: 6 * HOUR, repeat: 12 * HOUR },
  light: { grace: HOUR, repeat: 0 }, // śpi przy zapalonym świetle (raz na noc)
};
// Marudzenie bez powodu: tyle trwa, potem przechodzi i liczy się jako błąd wychowania
export const WHIM_LEN = 4 * HOUR;

// Kupa leżąca dłużej niż POOP_SAFE grozi chorobą: szansa na godzinę za każdą kupę
const POOP_SAFE = 6 * HOUR;
const POOP_SICK_PER_HOUR = 0.12;
// Nadwaga (ponad normę etapu) - mała szansa na chorobę w ciągu dnia
const OVERWEIGHT = 15;
const OVERWEIGHT_SICK_PER_DAY = 1;
// Długie zaniedbanie (głód, smutek albo choroba bez przerwy) - ucieka do lasu
export const NEGLECT_LIMIT = 24 * HOUR;
// Życie dorosłego: od wyklucia LIFE_BASE dni + premia za dobrą opiekę
const LIFE_BASE = 13;
const LIFE_BONUS = 8;
// Mało dyscypliny: nastolatek i dorosły czasem kręcą nosem na jedzenie
const PICKY_CHANCE = 0.2;

// --- losowanie -------------------------------------------------------------------

export function rand(s) {
  s.rng = (s.rng + 0x6d2b79f5) >>> 0;
  let t = s.rng;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

// Odstęp w minutach z rozrzutem ±25%
function jitter(s, minutes) {
  return Math.max(1, Math.round(minutes * (0.75 + 0.5 * rand(s))));
}

// --- czas ------------------------------------------------------------------------

// Minuta doby w czasie lokalnym; tz = przesunięcie strefy w minutach (-getTimezoneOffset())
export function localMinute(t, tz) {
  const m = Math.floor(t / MIN) + (tz || 0);
  return ((m % 1440) + 1440) % 1440;
}

function inWindow(m, from, to) {
  return from <= to ? m >= from && m < to : m >= from || m < to;
}

export function isNight(m) {
  return inWindow(m, SLEEP.bed, SLEEP.wake);
}
export function isSleepy(m) {
  return inWindow(m, SLEEP.sleepy, SLEEP.bed);
}
function isDay(m) {
  return inWindow(m, SLEEP.wake, SLEEP.sleepy);
}

// --- tworzenie -------------------------------------------------------------------

function emptyCalls() {
  return { hunger: 0, happy: 0, sick: 0, light: 0 };
}

// Nowe jajo. prev = poprzedni pupil (zostaje kolekcja form i historia)
export function newEgg(now, seed, prev) {
  return {
    v: 1,
    gen: prev ? prev.gen + 1 : 1,
    rng: seed >>> 0,
    t: now,
    born: now,
    hatched: 0,
    form: "egg",
    stageAt: now,
    hunger: MAX_HEARTS,
    happy: MAX_HEARTS,
    discipline: 0,
    weight: 0,
    poops: 0,
    poopAt: 0,
    sick: 0,
    asleep: false,
    light: true,
    lightMiss: false,
    timers: { hunger: 0, happy: 0, poop: 0, whim: 0 },
    calls: emptyCalls(),
    due: emptyCalls(),
    whim: 0,
    mistakes: 0,
    totalMistakes: 0,
    neglect: 0,
    gone: "",
    goneAt: 0,
    seen: prev ? prev.seen.slice() : [],
    history: prev ? prev.history.slice(-9) : [],
  };
}

// Sprawdza stan wczytany z pamięci (null = trzeba zacząć od nowego jaja)
export function restore(raw) {
  try {
    const s = typeof raw === "string" ? JSON.parse(raw) : raw;
    if (!s || s.v !== 1 || !FORMS[s.form] || typeof s.t !== "number" || !s.timers || !s.calls) return null;
    if (!Array.isArray(s.seen)) s.seen = [];
    if (!Array.isArray(s.history)) s.history = [];
    return s;
  } catch (e) {
    return null;
  }
}

export function clone(s) {
  return JSON.parse(JSON.stringify(s));
}

export function stageOf(s) {
  return FORMS[s.form].stage;
}

export function baseWeight(s) {
  return STAGES[stageOf(s)].weight;
}

// Wiek w pełnych dniach od wyklucia
export function ageDays(s) {
  return s.hatched ? Math.max(0, Math.floor((s.t - s.hatched) / DAY)) : 0;
}

// --- przemiany -------------------------------------------------------------------

function resetTimers(s) {
  const st = STAGES[stageOf(s)];
  s.timers.hunger = jitter(s, st.hunger);
  s.timers.happy = jitter(s, st.happy);
  s.timers.poop = jitter(s, st.poop);
  s.timers.whim = st.whim ? jitter(s, st.whim) : 0;
}

function becomeForm(s, form, events) {
  const oldBase = baseWeight(s);
  s.form = form;
  s.stageAt = s.t;
  s.mistakes = 0;
  s.weight = Math.max(baseWeight(s), s.weight + baseWeight(s) - oldBase);
  if (s.seen.indexOf(form) < 0) s.seen.push(form);
  resetTimers(s);
  events.push({ t: s.t, type: "evolve", form });
}

// W co ewoluuje: decyduje liczba błędów opieki w kończącym się etapie
export function nextForm(s) {
  const m = s.mistakes;
  switch (stageOf(s)) {
    case "egg":
      return "pisklak";
    case "baby":
      return m === 0 ? "tupek" : "gapcio";
    case "child":
      return m <= 1 ? "rogal" : m <= 3 ? "kolec" : "lobuz";
    case "teen":
      if (m <= 1 && s.discipline >= 2) return "rex";
      return m <= 3 ? "szyjek" : m <= 6 ? "ptero" : "burczek";
    default:
      return null;
  }
}

function evolve(s, events) {
  const form = nextForm(s);
  if (!form) return;
  if (stageOf(s) === "egg") {
    s.hatched = s.t;
    becomeForm(s, form, events);
    s.hunger = 2;
    s.happy = 2;
    events[events.length - 1].type = "hatch";
    return;
  }
  becomeForm(s, form, events);
}

// Ile dni od wyklucia pożyje: każde 2 błędy opieki (przez całe życie) zabierają dzień premii
export function lifeDays(s) {
  return LIFE_BASE + Math.max(0, LIFE_BONUS - Math.floor(s.totalMistakes / 2));
}

function depart(s, reason, events) {
  s.gone = reason;
  s.goneAt = s.t;
  s.history.push({ gen: s.gen, form: s.form, days: ageDays(s), reason });
  if (s.history.length > 10) s.history.shift();
  events.push({ t: s.t, type: "gone", reason });
}

function mistake(s, kind, events) {
  s.mistakes++;
  s.totalMistakes++;
  events.push({ t: s.t, type: "mistake", kind });
}

// Czy dana potrzeba jest teraz niezaspokojona
function needs(s, kind) {
  switch (kind) {
    case "hunger":
      return s.hunger === 0;
    case "happy":
      return s.happy === 0;
    case "sick":
      return s.sick > 0;
    case "light":
      return s.asleep && s.light && !s.lightMiss;
  }
  return false;
}

function getSick(s, events) {
  if (s.sick) return;
  s.sick = rand(s) < 0.5 ? 1 : 2; // ile dawek lekarstwa
  events.push({ t: s.t, type: "sick" });
}

// --- jedna minuta ----------------------------------------------------------------

function tick(s, tz, events) {
  const stage = stageOf(s);
  if (stage === "egg") {
    if (s.t - s.stageAt >= STAGES.egg.len) evolve(s, events);
    return;
  }
  const st = STAGES[stage];
  const m = localMinute(s.t, tz);

  // Sen: zasypia sam o BED (albo wcześniej po zgaszeniu światła), wstaje o WAKE
  if (s.asleep && isDay(m)) {
    s.asleep = false;
    s.light = true;
    s.lightMiss = false;
    events.push({ t: s.t, type: "wake" });
    if (stage === "adult" && s.t >= s.hatched + lifeDays(s) * DAY) {
      depart(s, "old", events);
      return;
    }
  } else if (!s.asleep && (isNight(m) || (isSleepy(m) && !s.light))) {
    s.asleep = true;
    events.push({ t: s.t, type: "sleep" });
  }

  if (!s.asleep) {
    if (--s.timers.hunger <= 0) {
      s.hunger = Math.max(0, s.hunger - 1);
      s.timers.hunger = jitter(s, st.hunger);
    }
    s.timers.happy -= s.sick ? 2 : 1;
    if (s.timers.happy <= 0) {
      s.happy = Math.max(0, s.happy - 1);
      s.timers.happy = jitter(s, st.happy);
    }
    if (--s.timers.poop <= 0) {
      if (s.poops === 0) s.poopAt = s.t;
      if (s.poops < MAX_POOPS) {
        s.poops++;
        events.push({ t: s.t, type: "poop" });
      }
      s.timers.poop = jitter(s, st.poop);
    }
    if (st.whim && !s.whim && --s.timers.whim <= 0) {
      s.whim = s.t;
      s.timers.whim = jitter(s, st.whim);
      events.push({ t: s.t, type: "whim" });
    }
  }

  // Choroba: od kupy leżącej za długo albo (rzadko) od nadwagi
  if (!s.sick) {
    let p = 0;
    if (s.poops && s.t - s.poopAt >= POOP_SAFE) p += (POOP_SICK_PER_HOUR * s.poops) / 60;
    if (!s.asleep && s.weight - st.weight >= OVERWEIGHT) p += OVERWEIGHT_SICK_PER_DAY / 1440;
    if (p > 0 && rand(s) < p) getSick(s, events);
  }

  // Wołanie o opiekę - w nocy zegar zwłoki stoi (oprócz światła)
  for (const kind in CALLS) {
    if (!needs(s, kind)) {
      s.calls[kind] = 0;
      continue;
    }
    if (!s.calls[kind]) {
      s.calls[kind] = s.t;
      s.due[kind] = s.t + CALLS[kind].grace;
    } else if (s.asleep && kind !== "light") {
      s.due[kind] += TICK;
    }
    if (s.due[kind] && s.t >= s.due[kind]) {
      mistake(s, kind, events);
      if (kind === "light") s.lightMiss = true;
      s.due[kind] = CALLS[kind].repeat ? s.t + CALLS[kind].repeat : 0;
    }
  }
  if (s.whim) {
    if (s.asleep) s.whim += TICK;
    else if (s.t - s.whim >= WHIM_LEN) {
      s.whim = 0;
      mistake(s, "whim", events);
    }
  }

  // Zaniedbanie liczone tylko w czasie czuwania
  if (s.hunger === 0 || s.happy === 0 || s.sick) {
    if (!s.asleep) s.neglect += TICK;
    if (s.neglect >= NEGLECT_LIMIT) {
      depart(s, "forest", events);
      return;
    }
  } else {
    s.neglect = 0;
  }

  // Ewolucja w czasie czuwania (nie budzimy śpiącego)
  if (!s.asleep && s.t - s.stageAt >= st.len) evolve(s, events);
}

// Przewija czas do `now`. Zwraca { state, events } - wejściowy stan się nie zmienia.
export function advance(state, now, tz) {
  const s = clone(state);
  const events = [];
  if (now < s.t) {
    // zegar cofnięty (zmiana czasu ręcznie) - nie cofamy życia, tylko czekamy
    s.t = now - ((now - s.t) % TICK);
    return { state: s, events };
  }
  if (s.gone) return { state: s, events };
  if (now - s.t > MAX_CATCHUP) s.t = now - MAX_CATCHUP;
  while (s.t + TICK <= now && !s.gone) {
    s.t += TICK;
    tick(s, tz, events);
  }
  return { state: s, events };
}

// --- akcje użytkownika ------------------------------------------------------------
// Każda akcja dostaje stan już przewinięty do teraz i zwraca
// { state, msg, anim } - anim to krótka animacja: "eat", "happy", "sad", "no" albo "".

function result(s, msg, anim) {
  return { state: s, msg, anim: anim || "" };
}

function blocked(s) {
  if (s.gone) return result(s, "", "no");
  if (stageOf(s) === "egg") return result(s, "To jeszcze jajo", "no");
  if (s.asleep) return result(s, "Śpi…", "no");
  return null;
}

export const ACTIONS = ["meal", "snack", "light", "play", "medicine", "clean", "scold", "stats"];

export function meal(state) {
  const s = clone(state);
  const b = blocked(s);
  if (b) return b;
  if (s.hunger >= MAX_HEARTS) return result(s, "Już najedzony", "no");
  const stage = stageOf(s);
  if ((stage === "teen" || stage === "adult") && s.discipline < 2 && rand(s) < PICKY_CHANCE)
    return result(s, "Kręci nosem…", "no");
  s.hunger++;
  s.weight++;
  return result(s, "Mniam!", "eat");
}

export function snack(state) {
  const s = clone(state);
  const b = blocked(s);
  if (b) return b;
  if (s.sick) return result(s, "Nie ma apetytu", "no");
  s.happy = Math.min(MAX_HEARTS, s.happy + 1);
  s.weight += 2;
  return result(s, "Pycha!", "eat");
}

export function canPlay(s) {
  if (s.gone || stageOf(s) === "egg") return "To jeszcze jajo";
  if (s.asleep) return "Śpi…";
  if (s.sick) return "Jest chory";
  return "";
}

// Wynik minigry: zabawa zawsze odchudza, wygrana poprawia humor
export function play(state, win) {
  const s = clone(state);
  const why = canPlay(s);
  if (why) return result(s, why, "no");
  s.weight = Math.max(baseWeight(s), s.weight - 1);
  if (!win) return result(s, "Może następnym razem", "sad");
  s.happy = Math.min(MAX_HEARTS, s.happy + 1);
  return result(s, "Wygrana!", "happy");
}

export function toggleLight(state, tz) {
  const s = clone(state);
  if (s.gone || stageOf(s) === "egg") return result(s, "", "no");
  if (s.asleep) {
    s.light = !s.light;
    return result(s, s.light ? "Światło zapalone" : "Dobranoc", "");
  }
  if (s.light && isSleepy(localMinute(s.t, tz))) {
    s.light = false;
    s.asleep = true;
    return result(s, "Dobranoc", "");
  }
  return result(s, "Jeszcze nie pora spać", "no");
}

export function medicine(state) {
  const s = clone(state);
  if (s.gone || stageOf(s) === "egg") return result(s, "", "no");
  if (!s.sick) return result(s, "Jest zdrowy", "no");
  s.sick--;
  return s.sick ? result(s, "Jeszcze jedna dawka", "") : result(s, "Wyzdrowiał!", "happy");
}

export function clean(state) {
  const s = clone(state);
  if (s.gone || stageOf(s) === "egg") return result(s, "", "no");
  if (!s.poops) return result(s, "Już czysto", "no");
  s.poops = 0;
  s.poopAt = 0;
  return result(s, "Posprzątane", "happy");
}

// Zganienie: pomaga tylko, gdy marudzi bez powodu; inaczej jest mu przykro
export function scold(state) {
  const s = clone(state);
  const b = blocked(s);
  if (b) return b;
  if (s.whim) {
    s.whim = 0;
    s.discipline = Math.min(MAX_HEARTS, s.discipline + 1);
    return result(s, "Grzeczny!", "");
  }
  s.happy = Math.max(0, s.happy - 1);
  return result(s, "Za co?!", "sad");
}

// Po odejściu: nowe jajo (kolekcja i historia zostają)
export function restart(state, now, seed) {
  return newEgg(now, seed, state);
}

// --- opis dla ekranu -------------------------------------------------------------

// Czy pupil czegoś potrzebuje (wykrzyknik na ekranie)
export function needsAttention(s) {
  if (s.gone || stageOf(s) === "egg") return false;
  if (s.asleep) return s.light;
  return s.hunger === 0 || s.happy === 0 || s.sick > 0 || s.whim > 0 || s.poops > 0;
}

// Nastrój do animacji: egg, sleep, sad, idle
export function moodOf(s) {
  if (stageOf(s) === "egg") return "egg";
  if (s.asleep) return "sleep";
  if (s.sick || s.hunger === 0 || s.happy === 0 || s.whim) return "sad";
  return "idle";
}

// Najważniejsza wiadomość na dole ekranu
export function statusText(s, tz) {
  if (s.gone === "old") return "Zostawił ci jajo i odszedł";
  if (s.gone) return "Uciekł do lasu…";
  if (stageOf(s) === "egg") return "Coś się rusza w jajku";
  if (s.asleep) return s.light ? "Zgaś światło!" : "Zzz…";
  if (s.sick) return "Chory - daj lekarstwo";
  if (s.hunger === 0) return "Głodny!";
  if (s.happy === 0) return "Smutno mu";
  if (s.whim) return "Marudzi bez powodu";
  if (s.poops) return "Trzeba posprzątać";
  if (isSleepy(localMinute(s.t, tz))) return "Ziewa… zgaś światło";
  return "";
}

// Teksty zdarzeń, które warto pokazać po otwarciu aplikacji
export function eventText(e) {
  switch (e.type) {
    case "hatch":
      return "Wykluł się!";
    case "evolve":
      return "Teraz to " + FORMS[e.form].name + "!";
    case "sick":
      return "Zachorował";
    case "gone":
      return e.reason === "old" ? "Odszedł ze starości" : "Uciekł do lasu";
  }
  return "";
}

export function lastNews(events) {
  for (let i = events.length - 1; i >= 0; i--) {
    const txt = eventText(events[i]);
    if (txt) return txt;
  }
  return "";
}
