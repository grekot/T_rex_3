// Kosmiczne gry na dotyk (bez ruchu ręką) - czysta logika, testy w test/space.test.mjs.
// Zegarek zostaje na ręce, więc obie gry są na stuknięcia: ekran cały czas przed oczami.
import { makeRng } from "./games.js";

// --- Obrona Milano: statki Ravagerów lecą z brzegów tarczy do Milano na środku -------------
// Stuknij statek, zanim doleci. Wygrana: DEFEND.need zestrzelonych, zanim DEFEND.lives
// statków dotrze do Milano albo minie czas.

export const DEFEND = {
  time: 45000,
  need: 12,
  lives: 3,
  r0: 205, // promień startu (brzeg tarczy 480 px)
  hit: 36, // zasięg Milano: statek bliżej = trafił
  touch: 44, // promień trafienia palcem
  speed0: 48, // px/s na początku
  speed1: 90, // px/s pod koniec
  spawn0: 1700, // ms między statkami na początku
  spawn1: 800,
  max: 5, // najwięcej statków naraz (tyle widżetów na stronie)
  cx: 240,
  cy: 240,
};

export function newDefend(seed) {
  return { rng: makeRng(seed), ships: [], next: 1200, elapsed: 0, killed: 0, lives: DEFEND.lives, done: false, win: false, id: 0 };
}

function lerp(a, b, f) {
  return a + (b - a) * Math.max(0, Math.min(1, f));
}

// Krok gry; zwraca listę zdarzeń: "spawn", "hit" (statek doleciał do Milano), "end"
export function defendStep(g, dt) {
  const ev = [];
  if (g.done) return ev;
  g.elapsed += dt;
  const f = g.elapsed / DEFEND.time;
  const speed = lerp(DEFEND.speed0, DEFEND.speed1, f);
  g.next -= dt;
  if (g.next <= 0 && g.ships.length < DEFEND.max) {
    const a = g.rng() * Math.PI * 2;
    g.ships.push({ id: ++g.id, a, d: DEFEND.r0 });
    g.next = lerp(DEFEND.spawn0, DEFEND.spawn1, f) * (0.8 + 0.4 * g.rng());
    ev.push("spawn");
  }
  for (const sh of g.ships) sh.d -= (speed * dt) / 1000;
  const reached = g.ships.filter((sh) => sh.d <= DEFEND.hit);
  if (reached.length) {
    g.ships = g.ships.filter((sh) => sh.d > DEFEND.hit);
    g.lives = Math.max(0, g.lives - reached.length);
    ev.push("hit");
  }
  if (g.killed >= DEFEND.need) {
    g.done = true;
    g.win = true;
  } else if (g.lives <= 0 || g.elapsed >= DEFEND.time) {
    g.done = true;
    g.win = false;
  }
  if (g.done) ev.push("end");
  return ev;
}

export function shipPos(sh) {
  return { x: DEFEND.cx + Math.cos(sh.a) * sh.d, y: DEFEND.cy + Math.sin(sh.a) * sh.d };
}

// Stuknięcie w punkt (x, y) albo w konkretny statek (id). Zwraca true, gdy zestrzelony.
export function defendTap(g, x, y, id) {
  if (g.done) return false;
  let best = -1;
  let bestD = Infinity;
  g.ships.forEach((sh, i) => {
    if (id !== undefined && sh.id !== id) return;
    const p = shipPos(sh);
    const d = id !== undefined ? 0 : Math.hypot(p.x - x, p.y - y);
    if (d <= DEFEND.touch && d < bestD) {
      best = i;
      bestD = d;
    }
  });
  if (best < 0) return false;
  g.ships.splice(best, 1);
  g.killed++;
  if (g.killed >= DEFEND.need) {
    g.done = true;
    g.win = true;
  }
  return true;
}

// --- Awesome Mix: zegarek wystukuje rytm (wibracja + kropki), ty go powtarzasz stuknięciami --
// Rytm to odstępy w jednostkach: 1 = krótki, 2 = długi. Ocenia się proporcje odstępów, nie
// tempo - liczy się, czy długie są dłuższe od krótkich. 3 rundy (4, 5, 6 uderzeń), 2 trafione.

export const MIX = { rounds: 3, need: 2, unit: 420, tol: 0.3, first: 4, gapAfter: 900, timeout: 2600 };

export function newMix(seed) {
  return { rng: makeRng(seed), round: 0, wins: 0, pattern: null, done: false, win: false, last: null };
}

// Nowy rytm na bieżącą rundę: odstępy (beats - 1 liczb 1 albo 2), co najmniej jeden długi i jeden krótki
export function mixPattern(g) {
  const beats = MIX.first + g.round;
  let p;
  do {
    p = [];
    for (let i = 0; i < beats - 1; i++) p.push(g.rng() < 0.5 ? 1 : 2);
  } while (p.indexOf(1) < 0 || p.indexOf(2) < 0);
  g.pattern = p;
  return p;
}

// Czasy uderzeń (ms od początku) do odtworzenia wibracją
export function beatTimes(pattern, unit) {
  const out = [0];
  pattern.forEach((u) => out.push(out[out.length - 1] + u * (unit || MIX.unit)));
  return out;
}

// Ocena stuknięć (czasy w ms): tyle samo uderzeń, a każdy odstęp w proporcji do wzoru
export function judgeTaps(pattern, taps) {
  if (taps.length !== pattern.length + 1) return { ok: false, why: taps.length < pattern.length + 1 ? "few" : "many" };
  const gaps = [];
  for (let i = 1; i < taps.length; i++) gaps.push(taps[i] - taps[i - 1]);
  const units = pattern.reduce((a, b) => a + b, 0);
  const unit = gaps.reduce((a, b) => a + b, 0) / units;
  if (unit < 80) return { ok: false, why: "fast" };
  for (let i = 0; i < gaps.length; i++) {
    if (Math.abs(gaps[i] / unit - pattern[i]) > MIX.tol * pattern[i]) return { ok: false, why: "rhythm", at: i };
  }
  return { ok: true };
}

// Wynik rundy; zwraca stan gry z polem last = { ok, why }
export function mixRound(g, taps) {
  const r = judgeTaps(g.pattern, taps);
  g.last = r;
  if (r.ok) g.wins++;
  g.round++;
  const left = MIX.rounds - g.round;
  if (g.wins >= MIX.need) {
    g.done = true;
    g.win = true;
  } else if (g.wins + left < MIX.need) {
    g.done = true;
    g.win = false;
  }
  return g;
}
