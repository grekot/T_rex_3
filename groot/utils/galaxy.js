// Kroki z zegarka i podróż Milano po galaktyce - czysta logika, testy w test/galaxy.test.mjs.
//
// Zegarek liczy kroki z całego dnia (Step.getCurrent()). Przy każdym otwarciu aplikacji
// dopisujemy przyrost od poprzedniego odczytu tego samego dnia:
// - co ENERGY.steps kroków Groot dostaje +1 wody/energii (licznik hunger), najwyżej
//   ENERGY.maxPerDay razy na dzień;
// - wszystkie kroki pchają Milano do kolejnej planety z filmów. Po przylocie Groot przez
//   VISIT_MS stoi na tle tej planety, a pocztówka trafia do kolekcji. Po ostatniej
//   planecie podróż zaczyna się od nowa (rounds + 1).
// Kroki z dnia, w którym aplikacja nie była otwarta, przepadają (zegarek podaje tylko dzisiejsze).

import { MIN, HOUR, MAX_HEARTS, clone, stageOf } from "./pet.js";

export const PLANETS = [
  { id: "xandar", name: "Xandar", need: 6000, note: "stolica Imperium Nova" },
  { id: "contraxia", name: "Contraxia", need: 8000, note: "lodowa planeta Ravagerów" },
  { id: "berhert", name: "Berhert", need: 10000, note: "tu rozbiło się Milano" },
  { id: "ego", name: "Planeta Ego", need: 12000, note: "żywa planeta ojca Quilla" },
  { id: "nidavellir", name: "Nidavellir", need: 15000, note: "kuźnia, gdzie Groot dał rękę na trzonek" },
  { id: "knowhere", name: "Knowhere", need: 18000, note: "dom Strażników w głowie Niebiańskiego" },
];

export const ENERGY = { steps: 2000, maxPerDay: 3 };
export const VISIT_MS = 24 * HOUR;

function dayOf(t, tz) {
  return Math.floor((Math.floor(t / MIN) + (tz || 0)) / 1440);
}

export function emptyTrip() {
  return { day: -1, seen: 0, energy: 0, leg: 0, progress: 0, visited: [], visit: null, rounds: 0 };
}

export function tripOf(s) {
  return s.trip || emptyTrip();
}

export function planetById(id) {
  return PLANETS.find((p) => p.id === id) || null;
}

// Planeta, na której Groot właśnie gości (tło ekranu), albo null
export function visiting(s) {
  const tr = s.trip;
  if (!tr || !tr.visit || s.t >= tr.visit.until) return null;
  return tr.visit.id;
}

// Dopisuje kroki z dzisiejszego licznika zegarka. Zwraca { state, msgs, arrived, energy }.
export function addSteps(state, stepsToday, now, tz) {
  const s = clone(state);
  const out = { state: s, msgs: [], arrived: [], energy: 0 };
  if (s.gone || stageOf(s) === "egg" || typeof stepsToday !== "number" || !(stepsToday >= 0)) return out;
  const tr = (s.trip = { ...emptyTrip(), ...(s.trip || {}), visited: ((s.trip && s.trip.visited) || []).slice() });
  const day = dayOf(now, tz);
  if (tr.day !== day) {
    tr.day = day;
    tr.seen = 0;
    tr.energy = 0;
  }
  // licznik zegarka spadł (inny zegarek, reset) - liczymy od nowa od tego odczytu
  const delta = stepsToday >= tr.seen ? stepsToday - tr.seen : stepsToday;
  tr.seen = stepsToday;

  const units = Math.min(ENERGY.maxPerDay, Math.floor(stepsToday / ENERGY.steps));
  const gain = Math.max(0, units - tr.energy);
  if (gain > 0) {
    tr.energy = units;
    const before = s.hunger;
    s.hunger = Math.min(MAX_HEARTS, s.hunger + gain);
    out.energy = s.hunger - before;
    out.msgs.push("Spacer: energia +" + gain);
  }

  tr.progress += delta;
  for (let guard = 0; guard < 20 && tr.progress >= PLANETS[tr.leg].need; guard++) {
    const p = PLANETS[tr.leg];
    tr.progress -= p.need;
    if (tr.visited.indexOf(p.id) < 0) tr.visited.push(p.id);
    tr.visit = { id: p.id, until: now + VISIT_MS };
    out.arrived.push(p.id);
    out.msgs.push("Milano ląduje: " + p.name + "!");
    tr.leg++;
    if (tr.leg >= PLANETS.length) {
      tr.leg = 0;
      tr.rounds++;
    }
  }
  return out;
}

// Opis do strony Galaktyka
export function tripInfo(s) {
  const tr = tripOf(s);
  const next = PLANETS[tr.leg];
  return {
    today: tr.seen,
    energy: tr.energy,
    next,
    progress: Math.min(tr.progress, next.need),
    visited: tr.visited.slice(),
    rounds: tr.rounds,
    visiting: visiting(s),
  };
}
