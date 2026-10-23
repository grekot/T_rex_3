// Pamięć zegarka: jeden zapis JSON z całym stanem Groota (razem z kolekcją form).
// Każda strona wczytuje stan, przewija czas do teraz (advance) i zapisuje z powrotem,
// więc minigry i strona główna widzą to samo.
//
// Stan leży w pliku pupil_state.json (+ kopia .bak na wypadek przerwanego zapisu).
// Wersja 1.0.0 trzymała go w LocalStorage - stamtąd tylko jednorazowy odczyt.
import { LocalStorage } from "@zos/storage";
import { readText, writeText } from "./files.js";
import { Time } from "@zos/sensor";
import { newEgg, restore, advance, tzFrom } from "./pet.js";

const KEY = "groot_state";
const FILE = "groot_state.json";
const BACKUP = "groot_state.bak";

// getTimezoneOffset() w silniku zegarka może zwracać 0 - wtedy pora dnia byłaby w UTC,
// więc strefę liczymy z systemowego zegara (Time), który zna godzinę lokalną.
export function tz() {
  try {
    const t = new Time();
    const h = t.getHours();
    const m = t.getMinutes();
    if (typeof h === "number" && typeof m === "number") return tzFrom(h * 60 + m, Date.now());
  } catch (e) {}
  try {
    return -new Date().getTimezoneOffset();
  } catch (e) {
    return 0;
  }
}

export function newSeed() {
  return (Date.now() ^ Math.floor(Math.random() * 4294967296)) >>> 0;
}

function legacyState() {
  try {
    const v = new LocalStorage().getItem(KEY);
    return v ? String(v) : "";
  } catch (e) {
    return "";
  }
}

export function rawState() {
  return readText(FILE);
}

function readState() {
  return restore(readText(FILE)) || restore(readText(BACKUP)) || restore(legacyState());
}

export function save(state) {
  const raw = JSON.stringify(state);
  if (writeText(FILE, raw)) writeText(BACKUP, raw);
  else {
    // pliki nie działają - lepsze to niż nic (świeża instancja przy każdym zapisie)
    try {
      new LocalStorage().setItem(KEY, raw);
    } catch (e) {}
  }
  return raw;
}

// Stan przewinięty do teraz: { state, events, fresh } (fresh = właśnie złożone pierwsze jajo)
export function load(now) {
  const t = now || Date.now();
  let s = readState();
  const fresh = !s;
  if (!s) s = newEgg(t, newSeed(), null);
  const r = advance(s, t, tz());
  save(r.state);
  return { state: r.state, events: r.events, fresh };
}

// Wczytaj, przewiń, zastosuj akcję (fn: stan -> { state, msg, anim }) i zapisz
export function apply(fn) {
  const { state } = load();
  const r = fn(state);
  save(r.state);
  return r;
}
