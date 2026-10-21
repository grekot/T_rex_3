// Minigry Pupila - czysta logika (testy w Node: test/games.test.mjs).
// Odczyty akcelerometru w cm/s^2 ({x, y, z}, grawitacja ok. 980), czas w ms.
// Progi ruchu to szacunki - jeśli na zegarku coś nie działa, stroić tutaj.

export const G = 980;

export function makeRng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function magnitude(a) {
  return Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
}

function clamp(v, lo, hi) {
  return v < lo ? lo : v > hi ? hi : v;
}

// --- rzut piłką ----------------------------------------------------------------
// Machnięcie nadgarstkiem = skok przyspieszenia. Od przekroczenia START zbieramy
// szczyt przez WINDOW ms - siła szczytu to odległość rzutu.

export const THROW = {
  start: 600, // odchylenie od grawitacji, od którego zaczyna się machnięcie
  full: 3200, // takie odchylenie = najdalszy rzut
  window: 300,
  cooldown: 900,
  maxDist: 100, // metry
  rounds: 3,
  catchRange: 12, // dinozaur łapie piłkę, jeśli spadnie tyle od niego
  needed: 2,
};

export function throwDistance(peak) {
  const f = clamp((peak - THROW.start) / (THROW.full - THROW.start), 0, 1);
  return Math.round(8 + f * (THROW.maxDist - 8));
}

export function createThrowDetector() {
  let startAt = 0;
  let peak = 0;
  let quietUntil = 0;
  return {
    // Zwraca odległość, gdy machnięcie się skończyło, inaczej null
    feed(a, t) {
      if (!a) return null;
      const dev = Math.abs(magnitude(a) - G);
      if (t < quietUntil) return null;
      if (!startAt) {
        if (dev < THROW.start) return null;
        startAt = t;
        peak = dev;
        return null;
      }
      if (dev > peak) peak = dev;
      if (t - startAt < THROW.window) return null;
      startAt = 0;
      quietUntil = t + THROW.cooldown;
      return throwDistance(peak);
    },
    quiet(t) {
      startAt = 0;
      quietUntil = t + THROW.cooldown;
    },
  };
}

export function newThrowGame(seed) {
  const rnd = makeRng(seed);
  const targets = [];
  for (let i = 0; i < THROW.rounds; i++) targets.push(Math.round(25 + rnd() * 60));
  return { targets, round: 0, throws: [], caught: 0, done: false, win: false };
}

export function throwBall(game, dist) {
  if (game.done) return game;
  const target = game.targets[game.round];
  const ok = Math.abs(dist - target) <= THROW.catchRange;
  const g = { ...game, throws: game.throws.concat([dist]), caught: game.caught + (ok ? 1 : 0), round: game.round + 1 };
  const left = THROW.rounds - g.round;
  if (g.caught >= THROW.needed || g.caught + left < THROW.needed || left === 0) {
    g.done = true;
    g.win = g.caught >= THROW.needed;
  }
  g.last = { dist, target, ok };
  return g;
}

// --- kołysanie do snu ----------------------------------------------------------
// Delikatne bujanie ręką: liczy się "energia" zmian odczytu po odfiltrowaniu wolnego
// tła (grawitacji przy obecnym ułożeniu ręki). Za mało = nie kołyszesz, w sam raz =
// pasek snu rośnie, za mocno albo szarpnięcie = budzi się.

export const ROCK = {
  gentleMin: 35,
  gentleMax: 320,
  hard: 480, // energia, od której jest za mocno
  jerk: 1100, // pojedyncze szarpnięcie (odchylenie od grawitacji)
  need: 8000, // ms delikatnego kołysania do zaśnięcia
  limit: 40000, // ms na całą grę
  strikes: 3, // tyle razy obudzony = przegrana
  strikeCooldown: 1500,
};

export function createRocker() {
  let bg = null;
  let energy = 0;
  let lastT = 0;
  let quietUntil = 0;
  const st = { level: "still", progress: 0, strikes: 0, elapsed: 0, done: false, win: false, energy: 0 };
  return {
    state: st,
    feed(a, t) {
      if (!a || st.done) return st;
      if (!bg) {
        bg = { x: a.x, y: a.y, z: a.z };
        lastT = t;
        return st;
      }
      const dt = clamp(t - lastT, 0, 200);
      lastT = t;
      st.elapsed += dt;
      const kb = Math.min(1, dt / 1500);
      bg.x += (a.x - bg.x) * kb;
      bg.y += (a.y - bg.y) * kb;
      bg.z += (a.z - bg.z) * kb;
      const hp = Math.sqrt((a.x - bg.x) ** 2 + (a.y - bg.y) ** 2 + (a.z - bg.z) ** 2);
      const ke = Math.min(1, dt / 500);
      energy += (hp - energy) * ke;
      st.energy = Math.round(energy);
      const jerk = Math.abs(magnitude(a) - G) > ROCK.jerk;
      if ((energy > ROCK.hard || jerk) && t >= quietUntil) {
        st.level = "hard";
        st.strikes++;
        st.progress = Math.max(0, st.progress - ROCK.need / 4);
        quietUntil = t + ROCK.strikeCooldown;
      } else if (t < quietUntil) {
        st.level = "hard";
      } else if (energy >= ROCK.gentleMin && energy <= ROCK.gentleMax) {
        st.level = "gentle";
        st.progress = Math.min(ROCK.need, st.progress + dt);
      } else {
        st.level = energy > ROCK.gentleMax ? "strong" : "still";
      }
      if (st.progress >= ROCK.need) {
        st.done = true;
        st.win = true;
      } else if (st.strikes >= ROCK.strikes || st.elapsed >= ROCK.limit) {
        st.done = true;
        st.win = false;
      }
      return st;
    },
  };
}

// --- balansowanie --------------------------------------------------------------
// Dinozaur stoi na kłodzie. Jego położenie samo ucieka od środka (równowaga chwiejna)
// i dmucha wiatr; przechylasz zegarek w bok (oś x), żeby go utrzymać. Spadnie przy |pos| >= 1.

export const BALANCE = {
  unstable: 1.6, // jak szybko ucieka od środka (1/s^2)
  gain: 5.5, // przechył 1 g -> przyspieszenie
  damping: 1.2,
  gust: 0.9,
  deadZone: 0.04, // w g
  time: 15000, // tyle trzeba wytrzymać
};

export function newBalance(seed) {
  return { pos: 0, vel: 0, wind: 0, elapsed: 0, done: false, win: false, rnd: makeRng(seed) };
}

// tilt = przechył w bok w jednostkach g (x po kalibracji / 980), dt w ms
export function stepBalance(b, tilt, dt) {
  if (b.done) return b;
  const s = clamp(dt, 0, 100) / 1000;
  let t = clamp(tilt, -1, 1);
  if (Math.abs(t) < BALANCE.deadZone) t = 0;
  b.wind += (b.rnd() - 0.5) * BALANCE.gust * 2 * s - b.wind * 0.5 * s;
  b.wind = clamp(b.wind, -0.6, 0.6);
  const acc = BALANCE.unstable * b.pos + BALANCE.gain * t + b.wind - BALANCE.damping * b.vel;
  b.vel += acc * s;
  b.pos += b.vel * s;
  b.elapsed += dt;
  if (Math.abs(b.pos) >= 1) {
    b.pos = b.pos > 0 ? 1 : -1;
    b.done = true;
    b.win = false;
  } else if (b.elapsed >= BALANCE.time) {
    b.done = true;
    b.win = true;
  }
  return b;
}

// Kalibracja jak w Labiryncie: średnia z drugiej połowy pomiaru = "poziomo"
export function calibrate(samples) {
  const half = samples.slice(Math.floor(samples.length / 2)).filter(Boolean);
  if (!half.length) return { x: 0, y: 0, z: G };
  const sum = half.reduce((acc, a) => ({ x: acc.x + a.x, y: acc.y + a.y, z: acc.z + a.z }), { x: 0, y: 0, z: 0 });
  return { x: sum.x / half.length, y: sum.y / half.length, z: sum.z / half.length };
}

export function sideTilt(a, zero) {
  return a ? (a.x - zero.x) / G : 0;
}

// --- lewo czy prawo (bez ruchu) --------------------------------------------------

export const GUESS = { rounds: 5, needed: 3 };

export function newGuess(seed) {
  const rnd = makeRng(seed);
  const dirs = [];
  for (let i = 0; i < GUESS.rounds; i++) dirs.push(rnd() < 0.5 ? "left" : "right");
  return { dirs, round: 0, hits: 0, done: false, win: false, last: null };
}

export function guess(game, side) {
  if (game.done) return game;
  const dir = game.dirs[game.round];
  const ok = dir === side;
  const g = { ...game, round: game.round + 1, hits: game.hits + (ok ? 1 : 0), last: { side, dir, ok } };
  const left = GUESS.rounds - g.round;
  if (g.hits >= GUESS.needed || g.hits + left < GUESS.needed || left === 0) {
    g.done = true;
    g.win = g.hits >= GUESS.needed;
  }
  return g;
}
