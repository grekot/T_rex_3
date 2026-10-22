// Kolejne minigry ruchowe (akcelerometr) - czysta logika, testy w test/moves.test.mjs.
// Odczyty w cm/s^2 ({x, y, z}, grawitacja ok. 980), czas w ms. Progi to szacunki do
// dostrojenia na zegarku - wszystkie są w stałych WIELKIMI literami.
import { G, makeRng } from "./games.js";

function clamp(v, lo, hi) {
  return v < lo ? lo : v > hi ? hi : v;
}

function mag(a) {
  return Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
}

// Przechył przód/tył w g: dodatni = "z górki" w stronę godziny 6 (do siebie),
// ujemny = w stronę godziny 12 (od siebie). Znak jak w Labiryncie.
export function vertTilt(a, zero) {
  return a ? (zero.zSign * (a.y - zero.y)) / G : 0;
}

// --- wspólne detektory -------------------------------------------------------------

// Kierunek przechyłu z histerezą: zwraca "left" | "right" | "up" | "down" raz na przechył,
// potem trzeba wrócić do poziomu
export const TILT_DIR = { on: 0.35, off: 0.15 };

export function createTiltReader() {
  let armed = true;
  return {
    feed(tx, ty) {
      const m = Math.max(Math.abs(tx), Math.abs(ty));
      if (!armed) {
        if (m < TILT_DIR.off) armed = true;
        return null;
      }
      if (m < TILT_DIR.on) return null;
      armed = false;
      if (Math.abs(tx) >= Math.abs(ty)) return tx > 0 ? "right" : "left";
      return ty > 0 ? "down" : "up";
    },
  };
}

// Szarpnięcie / machnięcie: true w chwili przekroczenia progu, potem przerwa.
// hits = ile kolejnych odczytów (co 40 ms) musi być ponad progiem - drgania silniczka
// wibracji są krótkie, prawdziwe szarpnięcie ręką trwa dłużej. mute(t) = po własnej
// wibracji zegarka czekaj, aż odczyty się uspokoją (2 spokojne z rzędu), najdłużej do t.
export function createFlick(threshold, cooldown, hits) {
  const need = hits || 1;
  let up = false;
  let quietUntil = 0;
  let run = 0;
  let settling = false;
  let calm = 0;
  return {
    feed(a, t) {
      if (!a) return false;
      const dev = Math.abs(mag(a) - G);
      if (settling) {
        if (t >= quietUntil) settling = false;
        else {
          calm = dev < threshold * 0.3 ? calm + 1 : 0;
          if (calm >= 2) {
            settling = false;
            quietUntil = t;
          }
          return false;
        }
      }
      if (up) {
        if (dev < threshold * 0.5) up = false;
        return false;
      }
      if (t < quietUntil || dev < threshold) {
        run = 0;
        return false;
      }
      if (++run < need) return false;
      run = 0;
      up = true;
      quietUntil = t + cooldown;
      return true;
    },
    mute(until) {
      quietUntil = Math.max(quietUntil, until);
      run = 0;
      settling = true;
      calm = 0;
    },
    dev(a) {
      return a ? Math.abs(mag(a) - G) : 0;
    },
  };
}

// Powtórzenia ruchu (kopanie, pompowanie, bieg, ćwiczenia): siła zmian po odjęciu wolnego
// tła. Ruch tam i z powrotem daje dwa szczyty (w obie strony), więc liczy się tylko szczyt
// w kierunku zapamiętanym przy pierwszym powtórzeniu (oś i znak; po 2 s przerwy od nowa).
export const REPS = { hi: 420, lo: 160, minMs: 220, relock: 2000 };

export function createRepCounter(opts) {
  const o = { ...REPS, ...(opts || {}) };
  let bg = null;
  let lastT = 0;
  let up = false;
  let lastRep = -1e9;
  let lock = null; // { axis, sign }
  return {
    count: 0,
    level: 0,
    feed(a, t) {
      if (!a) return false;
      if (!bg) {
        bg = { x: a.x, y: a.y, z: a.z };
        lastT = t;
        return false;
      }
      const k = Math.min(1, clamp(t - lastT, 0, 200) / 600);
      lastT = t;
      bg.x += (a.x - bg.x) * k;
      bg.y += (a.y - bg.y) * k;
      bg.z += (a.z - bg.z) * k;
      const hp = { x: a.x - bg.x, y: a.y - bg.y, z: a.z - bg.z };
      const size = Math.sqrt(hp.x * hp.x + hp.y * hp.y + hp.z * hp.z);
      this.level = Math.round(size);
      if (lock && !up && t - lastRep > o.relock) lock = null;
      if (!up) {
        if (size <= o.hi) return false;
        const axis = Math.abs(hp.x) >= Math.abs(hp.y) && Math.abs(hp.x) >= Math.abs(hp.z) ? "x" : Math.abs(hp.y) >= Math.abs(hp.z) ? "y" : "z";
        const sign = hp[axis] >= 0 ? 1 : -1;
        if (!lock) lock = { axis, sign };
        if (lock.axis === axis && lock.sign === sign) up = true;
        return false;
      }
      if (hp[lock.axis] * lock.sign < o.lo) {
        up = false;
        if (t - lastRep >= o.minMs) {
          lastRep = t;
          this.count++;
          return true;
        }
      }
      return false;
    },
  };
}

// Spokój ręki: energia zmian (do medytacji i celowania)
export function createStillness() {
  let bg = null;
  let lastT = 0;
  let energy = 0;
  return {
    feed(a, t) {
      if (!a) return energy;
      if (!bg) {
        bg = { x: a.x, y: a.y, z: a.z };
        lastT = t;
        return energy;
      }
      const dt = clamp(t - lastT, 0, 200);
      lastT = t;
      const kb = Math.min(1, dt / 1500);
      bg.x += (a.x - bg.x) * kb;
      bg.y += (a.y - bg.y) * kb;
      bg.z += (a.z - bg.z) * kb;
      const hp = Math.sqrt((a.x - bg.x) ** 2 + (a.y - bg.y) ** 2 + (a.z - bg.z) ** 2);
      energy += (hp - energy) * Math.min(1, dt / 400);
      return energy;
    },
  };
}

// --- 1. Powtórz ruch -------------------------------------------------------------

export const SIMON = { start: 2, win: 6, lives: 2 };
const DIRS = ["left", "right", "up", "down"];

export function newSimon(seed) {
  const rnd = makeRng(seed);
  const seq = [];
  for (let i = 0; i < SIMON.win; i++) {
    let d;
    do d = DIRS[Math.floor(rnd() * 4)];
    while (i > 0 && d === seq[i - 1]);
    seq.push(d);
  }
  return { seq, level: SIMON.start, pos: 0, lives: SIMON.lives, done: false, win: false };
}

// Zwraca { game, event }: ok | round | wrong | win | lose
export function simonInput(game, dir) {
  if (game.done) return { game, event: "" };
  const g = { ...game };
  if (dir === g.seq[g.pos]) {
    g.pos++;
    if (g.pos < g.level) return { game: g, event: "ok" };
    g.pos = 0;
    if (g.level >= SIMON.win) {
      g.done = true;
      g.win = true;
      return { game: g, event: "win" };
    }
    g.level++;
    return { game: g, event: "round" };
  }
  g.lives--;
  g.pos = 0;
  if (g.lives <= 0) {
    g.done = true;
    return { game: g, event: "lose" };
  }
  return { game: g, event: "wrong" };
}

// --- 2. Łapanie owoców -------------------------------------------------------------

export const CATCH = {
  w: 320, // szerokość pola (px)
  h: 230, // wysokość spadania
  dinoW: 64,
  gain: 520, // px/s przy przechyle 1 g
  time: 30000,
  need: 10,
  lives: 3,
  fall: 150, // px/s na początku, rośnie
  spawnMs: 950,
  rockChance: 0.3,
  item: 36,
};

export function newCatch(seed) {
  return { x: CATCH.w / 2, items: [], caught: 0, lives: CATCH.lives, elapsed: 0, spawnIn: 600, done: false, win: false, rnd: makeRng(seed), next: 1 };
}

// Zwraca listę zdarzeń: "fruit" | "rock"
export function stepCatch(g, tilt, dt) {
  const ev = [];
  if (g.done) return ev;
  const s = clamp(dt, 0, 100) / 1000;
  g.elapsed += dt;
  g.x = clamp(g.x + clamp(tilt, -1, 1) * CATCH.gain * s, CATCH.dinoW / 2, CATCH.w - CATCH.dinoW / 2);
  g.spawnIn -= dt;
  if (g.spawnIn <= 0) {
    g.spawnIn = CATCH.spawnMs * (0.7 + 0.6 * g.rnd());
    g.items.push({ id: g.next++, x: CATCH.item / 2 + g.rnd() * (CATCH.w - CATCH.item), y: 0, kind: g.rnd() < CATCH.rockChance ? "rock" : "fruit" });
  }
  const speed = CATCH.fall * (1 + g.elapsed / CATCH.time);
  const keep = [];
  for (const it of g.items) {
    it.y += speed * s;
    if (it.y >= CATCH.h - 40 && it.y < CATCH.h && Math.abs(it.x - g.x) < CATCH.dinoW / 2 + CATCH.item / 3) {
      if (it.kind === "fruit") g.caught++;
      else g.lives--;
      ev.push(it.kind);
      continue;
    }
    if (it.y < CATCH.h + 10) keep.push(it);
  }
  g.items = keep;
  if (g.lives <= 0) {
    g.done = true;
    g.win = false;
  } else if (g.elapsed >= CATCH.time) {
    g.done = true;
    g.win = g.caught >= CATCH.need;
  }
  return ev;
}

// --- 3. Skoki przez przeszkody -----------------------------------------------------

export const RUNNER = {
  w: 360,
  dinoX: 70,
  dinoW: 40,
  speed: 170, // px/s, rośnie do 1,6x
  jumpMs: 800,
  jumpH: 80,
  clear: 30, // tyle wysokości wystarczy nad przeszkodą
  obstW: 22,
  gapMin: 1.1, // odstęp między przeszkodami w sekundach (przy każdej prędkości da się zdążyć)
  gapMax: 1.9,
  time: 25000,
  flick: 700, // podrzut nadgarstka
};

export function newRunner(seed) {
  return { obstacles: [], jumpT: -1, elapsed: 0, jumped: 0, done: false, win: false, rnd: makeRng(seed), next: 1, spawnAt: RUNNER.w };
}

export function jump(g) {
  if (g.done || g.jumpT >= 0) return false;
  g.jumpT = 0;
  return true;
}

export function jumpHeight(g) {
  if (g.jumpT < 0) return 0;
  const f = g.jumpT / RUNNER.jumpMs;
  return RUNNER.jumpH * 4 * f * (1 - f);
}

export function runnerSpeed(g) {
  return RUNNER.speed * (1 + (0.6 * g.elapsed) / RUNNER.time);
}

export function stepRunner(g, dt) {
  if (g.done) return "";
  const s = clamp(dt, 0, 100) / 1000;
  g.elapsed += dt;
  if (g.jumpT >= 0) {
    g.jumpT += dt;
    if (g.jumpT >= RUNNER.jumpMs) g.jumpT = -1;
  }
  const speed = runnerSpeed(g);
  const last = g.obstacles[g.obstacles.length - 1];
  if (!last || last.x < RUNNER.w - last.gap * speed) {
    g.obstacles.push({ id: g.next++, x: RUNNER.w + 10, passed: false, gap: RUNNER.gapMin + g.rnd() * (RUNNER.gapMax - RUNNER.gapMin) });
  }
  const h = jumpHeight(g);
  let ev = "";
  for (const o of g.obstacles) {
    o.x -= speed * s;
    const overlap = o.x < RUNNER.dinoX + RUNNER.dinoW / 2 && o.x + RUNNER.obstW > RUNNER.dinoX - RUNNER.dinoW / 2;
    if (overlap && h < RUNNER.clear) {
      g.done = true;
      g.win = false;
      return "hit";
    }
    if (!o.passed && o.x + RUNNER.obstW < RUNNER.dinoX - RUNNER.dinoW / 2) {
      o.passed = true;
      g.jumped++;
      ev = "pass";
    }
  }
  g.obstacles = g.obstacles.filter((o) => o.x > -RUNNER.obstW - 10);
  if (g.elapsed >= RUNNER.time) {
    g.done = true;
    g.win = true;
  }
  return ev;
}

// --- 4. Potrząśnij drzewem -----------------------------------------------------------

export const TREE = { time: 15000, need: 12, soft: 600, hard: 2300, hardMax: 2, cooldown: 170 };

export function newTree() {
  return { fruits: 0, bees: 0, elapsed: 0, done: false, win: false, soft: createFlick(TREE.soft, TREE.cooldown), hardQuiet: 0 };
}

// Zwraca "fruit" | "bees" | ""
export function feedTree(g, a, t, dt) {
  if (g.done) return "";
  g.elapsed += dt;
  let ev = "";
  const dev = g.soft.dev(a);
  if (a && dev > TREE.hard && t >= g.hardQuiet) {
    g.hardQuiet = t + 900;
    g.bees++;
    ev = "bees";
  } else if (g.soft.feed(a, t)) {
    g.fruits++;
    ev = "fruit";
  }
  if (g.bees >= TREE.hardMax) {
    g.done = true;
    g.win = false;
  } else if (g.fruits >= TREE.need) {
    g.done = true;
    g.win = true;
  } else if (g.elapsed >= TREE.time) {
    g.done = true;
    g.win = false;
  }
  return ev;
}

// --- 5. Wykopywanie kości ------------------------------------------------------------

export const DIG = { need: 15, time: 25000, layers: 3 };

export function newDig() {
  return { digs: 0, elapsed: 0, done: false, win: false, reps: createRepCounter() };
}

export function feedDig(g, a, t, dt) {
  if (g.done) return false;
  g.elapsed += dt;
  const rep = g.reps.feed(a, t);
  if (rep) g.digs++;
  if (g.digs >= DIG.need) {
    g.done = true;
    g.win = true;
  } else if (g.elapsed >= DIG.time) {
    g.done = true;
    g.win = false;
  }
  return rep;
}

// --- 6. Pompowanie balonu ------------------------------------------------------------

export const BALLOON = { band: 15, minLo: 55, maxLo: 72, pumpMin: 5, pumpMax: 11, idleRelease: 3000 };

export function newBalloon(seed) {
  const rnd = makeRng(seed);
  const lo = Math.round(BALLOON.minLo + rnd() * (BALLOON.maxLo - BALLOON.minLo));
  return { lo, hi: lo + BALLOON.band, size: 0, done: false, win: false, popped: false, rnd, reps: createRepCounter(), lastPump: 0 };
}

export function pump(g, t) {
  if (g.done) return g;
  g.size += BALLOON.pumpMin + g.rnd() * (BALLOON.pumpMax - BALLOON.pumpMin);
  g.lastPump = t || 0;
  if (g.size > 100) {
    g.size = 100;
    g.done = true;
    g.popped = true;
    g.win = false;
  }
  return g;
}

export function releaseBalloon(g) {
  if (g.done) return g;
  g.done = true;
  g.win = g.size >= g.lo && g.size <= g.hi;
  return g;
}

// --- 7. Labirynt jajka -------------------------------------------------------------

export const EGGROLL = { size: 300, r: 15, nestR: 18, gain: 900, friction: 1.4, maxSpeed: 420, time: 40000 };
// Trzy plansze: przeszkody (prostokąty w polu 300 x 300), start i gniazdo
export const EGG_LEVELS = [
  { start: [40, 40], nest: [255, 255], walls: [[0, 90, 200, 18], [100, 190, 200, 18]] },
  { start: [40, 260], nest: [255, 40], walls: [[90, 60, 18, 240], [190, 0, 18, 220]] },
  { start: [150, 40], nest: [150, 260], walls: [[40, 100, 220, 18], [0, 180, 120, 18], [180, 180, 120, 18]] },
];

export function newEggRoll(seed) {
  const L = EGG_LEVELS[Math.abs(seed) % EGG_LEVELS.length];
  return { level: L, x: L.start[0], y: L.start[1], vx: 0, vy: 0, elapsed: 0, done: false, win: false };
}

export function stepEggRoll(g, tx, ty, dt) {
  if (g.done) return;
  const s = clamp(dt, 0, 50) / 1000;
  g.elapsed += dt;
  g.vx += (clamp(tx, -1, 1) * EGGROLL.gain - g.vx * EGGROLL.friction) * s;
  g.vy += (clamp(ty, -1, 1) * EGGROLL.gain - g.vy * EGGROLL.friction) * s;
  const sp = Math.hypot(g.vx, g.vy);
  if (sp > EGGROLL.maxSpeed) {
    g.vx *= EGGROLL.maxSpeed / sp;
    g.vy *= EGGROLL.maxSpeed / sp;
  }
  g.x += g.vx * s;
  g.y += g.vy * s;
  const r = EGGROLL.r;
  if (g.x < r) (g.x = r), (g.vx = -g.vx * 0.3);
  if (g.y < r) (g.y = r), (g.vy = -g.vy * 0.3);
  if (g.x > EGGROLL.size - r) (g.x = EGGROLL.size - r), (g.vx = -g.vx * 0.3);
  if (g.y > EGGROLL.size - r) (g.y = EGGROLL.size - r), (g.vy = -g.vy * 0.3);
  for (const [wx, wy, ww, wh] of g.level.walls) {
    const nx = clamp(g.x, wx, wx + ww);
    const ny = clamp(g.y, wy, wy + wh);
    const dx = g.x - nx;
    const dy = g.y - ny;
    const d = Math.hypot(dx, dy);
    if (d < r) {
      if (d === 0) {
        g.y = wy - r;
        g.vy = 0;
        continue;
      }
      g.x = nx + (dx / d) * r;
      g.y = ny + (dy / d) * r;
      const vn = (g.vx * dx + g.vy * dy) / d;
      if (vn < 0) {
        g.vx -= (1.3 * vn * dx) / d;
        g.vy -= (1.3 * vn * dy) / d;
      }
    }
  }
  if (Math.hypot(g.x - g.level.nest[0], g.y - g.level.nest[1]) < EGGROLL.nestR) {
    g.done = true;
    g.win = true;
  } else if (g.elapsed >= EGGROLL.time) {
    g.done = true;
    g.win = false;
  }
}

// --- 8. Refleks i 10. Wędkowanie (czekaj na sygnał, potem szybko) ---------------------

// Refleks: sygnał tylko na ekranie (bez wibracji). Wędkowanie: sygnałem jest wibracja,
// przez mute ms po niej akcelerometr jest ignorowany, okno odpowiednio dłuższe.
export const REFLEX = { rounds: 3, waitMin: 1500, waitMax: 4500, maxAvg: 650, flick: 700, timeout: 2000, hits: 2, vibrate: false, mute: 0 };
export const FISH = { rounds: 3, waitMin: 2500, waitMax: 7000, window: 2000, need: 2, flick: 900, hits: 2, vibrate: true, mute: 800 };

export function newSignalGame(seed, cfg, now) {
  const rnd = makeRng(seed);
  const g = { cfg, rnd, round: 0, phase: "wait", goAt: 0, results: [], done: false, win: false };
  scheduleSignal(g, now);
  return g;
}

function scheduleSignal(g, now) {
  g.phase = "wait";
  g.goAt = now + g.cfg.waitMin + g.rnd() * (g.cfg.waitMax - g.cfg.waitMin);
}

function finishSignal(g) {
  const cfg = g.cfg;
  if (cfg === FISH) {
    g.win = g.results.filter((r) => r.ok).length >= FISH.need;
  } else {
    const ok = g.results.filter((r) => r.ok);
    const avg = ok.length ? ok.reduce((s, r) => s + r.ms, 0) / ok.length : Infinity;
    g.avg = Math.round(avg);
    g.win = ok.length >= 2 && avg <= REFLEX.maxAvg;
  }
  g.done = true;
}

// Krok gry: flicked = było szarpnięcie w tej chwili. Zwraca zdarzenie:
// "go" (sygnał), "ok" (w porę), "early" (za wcześnie), "late" (za późno), ""
export function stepSignal(g, now, flicked) {
  if (g.done) return "";
  const cfg = g.cfg;
  const limit = cfg === FISH ? FISH.window : REFLEX.timeout;
  let ev = "";
  if (g.phase === "wait") {
    if (flicked) {
      g.results.push({ ok: false, early: true });
      ev = "early";
    } else if (now >= g.goAt) {
      g.phase = "go";
      return "go";
    } else return "";
  } else if (g.phase === "go") {
    if (flicked) {
      g.results.push({ ok: true, ms: Math.round(now - g.goAt) });
      ev = "ok";
    } else if (now - g.goAt > limit) {
      g.results.push({ ok: false, late: true });
      ev = "late";
    } else return "";
  } else return "";
  g.round++;
  if (g.round >= cfg.rounds) finishSignal(g);
  else {
    g.phase = "pause";
    g.resumeAt = now + 1500;
  }
  return ev;
}

// Po przerwie między rundami
export function resumeSignal(g, now) {
  if (g.phase === "pause" && now >= g.resumeAt) {
    scheduleSignal(g, now);
    return true;
  }
  return false;
}

// --- 12. Celowanie -------------------------------------------------------------------

export const AIM = { shots: 5, need: 3, gain: 260, smooth: 0.25, targetR: 30, field: 130 };

export function newAim(seed) {
  const rnd = makeRng(seed);
  const g = { rnd, x: 0, y: 0, shots: 0, hits: 0, done: false, win: false, tx: 0, ty: 0 };
  placeTarget(g);
  return g;
}

function placeTarget(g) {
  const a = g.rnd() * Math.PI * 2;
  const d = 40 + g.rnd() * (AIM.field - 40);
  g.tx = Math.round(Math.cos(a) * d);
  g.ty = Math.round(Math.sin(a) * d * 0.75); // pole celowania jest niższe niż szersze
}

// Celownik idzie za przechyłem (wygładzony), względem środka ekranu
export function aimStep(g, tx, ty) {
  const nx = clamp(tx, -0.6, 0.6) * AIM.gain;
  const ny = clamp(ty, -0.6, 0.6) * AIM.gain;
  g.x += (nx - g.x) * AIM.smooth;
  g.y += (ny - g.y) * AIM.smooth;
}

export function shoot(g) {
  if (g.done) return false;
  const hit = Math.hypot(g.x - g.tx, g.y - g.ty) <= AIM.targetR;
  g.shots++;
  if (hit) g.hits++;
  if (g.hits >= AIM.need) {
    g.done = true;
    g.win = true;
  } else if (g.hits + (AIM.shots - g.shots) < AIM.need) {
    g.done = true;
    g.win = false;
  } else placeTarget(g);
  return hit;
}

// --- 22. Wyścig z dinozaurem -----------------------------------------------------------

export const RACE = { time: 15000, rival: 1.4 }; // rywal: powtórzeń na sekundę

export function newRace() {
  return { you: 0, rival: 0, elapsed: 0, done: false, win: false, reps: createRepCounter({ hi: 380, lo: 150, minMs: 180 }) };
}

export function feedRace(g, a, t, dt) {
  if (g.done) return false;
  g.elapsed += dt;
  const rep = g.reps.feed(a, t);
  if (rep) g.you++;
  g.rival = (RACE.rival * g.elapsed) / 1000;
  if (g.elapsed >= RACE.time) {
    g.done = true;
    g.win = g.you >= g.rival;
  }
  return rep;
}

// --- 23. Medytacja ---------------------------------------------------------------------

export const CALM = { need: 20000, limit: 60000, max: 28 };

export function newCalm() {
  return { progress: 0, elapsed: 0, done: false, win: false, still: createStillness(), energy: 0 };
}

export function feedCalm(g, a, t, dt) {
  if (g.done) return;
  g.elapsed += dt;
  g.energy = g.still.feed(a, t);
  if (g.elapsed < 600) return; // filtr się ustala
  if (g.energy <= CALM.max) g.progress = Math.min(CALM.need, g.progress + dt);
  else g.progress = Math.max(0, g.progress - dt * 2);
  if (g.progress >= CALM.need) {
    g.done = true;
    g.win = true;
  } else if (g.elapsed >= CALM.limit) {
    g.done = true;
    g.win = false;
  }
}

// --- 24. Rozgrzewka poranna --------------------------------------------------------------

export const WARMUP = {
  limit: 120000,
  steps: [
    { name: "Krążenia ramion", reps: 8, kind: "reps" },
    { name: "Wymachy rąk", reps: 8, kind: "reps" },
    { name: "Skłony do ziemi", reps: 5, kind: "bend" },
  ],
  bendDown: 60, // stopni od pozycji startowej
  bendUp: 25,
  back: 45, // albo tyle stopni wstecz od najgłębszego punktu skłonu
  settle: 600, // ms bez ruchu poza skłonem = nowa pozycja wyprostowana
};

function angleBetween(a, b) {
  const c = (a.x * b.x + a.y * b.y + a.z * b.z) / (mag(a) * mag(b) || 1);
  return (Math.acos(clamp(c, -1, 1)) * 180) / Math.PI;
}

export function newWarmup() {
  return { step: 0, count: 0, elapsed: 0, done: false, win: false, reps: createRepCounter(), ref: null, down: false };
}

// Zwraca "rep" | "next" (kolejne ćwiczenie) | ""
export function feedWarmup(g, a, t, dt) {
  if (g.done || !a) return "";
  g.elapsed += dt;
  const st = WARMUP.steps[g.step];
  let rep = false;
  if (st.kind === "reps") rep = g.reps.feed(a, t);
  else {
    // Pozycja "wyprostowany" dopasowuje się powoli do ręki, gdy nie ma skłonu - start
    // w dowolnej pozycji (albo w ruchu) nie psuje liczenia
    if (!g.ref) g.ref = { ...a };
    const ang = angleBetween(a, g.ref);
    // powrót = blisko pozycji wyjściowej albo cofnięcie o "back" stopni od najgłębszego punktu
    if (!g.down && ang > WARMUP.bendDown) {
      g.down = true;
      g.peak = ang;
    } else if (g.down) {
      g.peak = Math.max(g.peak, ang);
      if (ang < WARMUP.bendUp || ang < g.peak - WARMUP.back) {
        g.down = false;
        rep = true;
      }
    }
    // ręka nieruchomo przez chwilę (poza skłonem) = nowa pozycja wyprostowana
    const p = g.prev || a;
    const still = Math.abs(a.x - p.x) + Math.abs(a.y - p.y) + Math.abs(a.z - p.z) < 80;
    g.prev = { ...a };
    g.calmMs = still ? (g.calmMs || 0) + dt : 0;
    if (!g.down && g.calmMs >= WARMUP.settle) g.ref = { ...a };
  }
  let ev = "";
  if (rep) {
    g.count++;
    ev = "rep";
    if (g.count >= st.reps) {
      g.step++;
      g.count = 0;
      g.reps = createRepCounter();
      g.ref = null;
      ev = "next";
      if (g.step >= WARMUP.steps.length) {
        g.done = true;
        g.win = true;
        return "next";
      }
    }
  }
  if (g.elapsed >= WARMUP.limit) {
    g.done = true;
    g.win = false;
  }
  return ev;
}
