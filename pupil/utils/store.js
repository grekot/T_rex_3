// Pamięć zegarka: jeden zapis JSON z całym stanem pupila (razem z kolekcją form).
// Każda strona wczytuje stan, przewija czas do teraz (advance) i zapisuje z powrotem,
// więc minigry i strona główna widzą to samo.
import { LocalStorage } from "@zos/storage";
import { newEgg, restore, advance } from "./pet.js";

const storage = new LocalStorage();
const KEY = "pupil_state";

export function tz() {
  try {
    return -new Date().getTimezoneOffset();
  } catch (e) {
    return 0;
  }
}

export function newSeed() {
  return (Date.now() ^ Math.floor(Math.random() * 4294967296)) >>> 0;
}

export function rawState() {
  try {
    return storage.getItem(KEY) || "";
  } catch (e) {
    return "";
  }
}

export function save(state) {
  const raw = JSON.stringify(state);
  try {
    storage.setItem(KEY, raw);
  } catch (e) {}
  return raw;
}

// Stan przewinięty do teraz: { state, events, fresh } (fresh = właśnie złożone pierwsze jajo)
export function load(now) {
  const t = now || Date.now();
  let s = restore(rawState());
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
