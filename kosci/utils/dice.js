// Logika kości (bez API zegarka - testowana w Node): ustawienia, rzut z zatrzymanymi
// kośćmi, podsumowanie, oczka K6, rozmieszczenie kości na okrągłym ekranie.

export const DICE_TYPES = [4, 6, 8, 10, 12, 20];
export const MAX_DICE = 6;

export const DEFAULT_CONFIG = { count: 2, sides: 6, shake: true };

export function normalizeConfig(cfg) {
  const c = cfg && typeof cfg === "object" ? cfg : {};
  const count = Math.round(Number(c.count));
  return {
    count: count >= 1 && count <= MAX_DICE ? count : DEFAULT_CONFIG.count,
    sides: DICE_TYPES.indexOf(Number(c.sides)) >= 0 ? Number(c.sides) : DEFAULT_CONFIG.sides,
    shake: typeof c.shake === "boolean" ? c.shake : DEFAULT_CONFIG.shake,
  };
}

export function typeLabel(sides) {
  return "K" + sides;
}

// Napis na przycisku ustawień, np. "2 × K6"
export function configLabel(cfg) {
  return cfg.count + " × " + typeLabel(cfg.sides);
}

export function rollDie(sides, rand) {
  const r = (rand || Math.random)();
  return Math.min(sides, Math.floor(r * sides) + 1);
}

// Stan stołu: wyniki (null = jeszcze nie rzucono), zatrzymane kości, poprzednia suma
export function newHand(cfg) {
  return { count: cfg.count, sides: cfg.sides, values: null, locked: fill(cfg.count, false), prev: null };
}

function fill(n, v) {
  const a = [];
  for (let i = 0; i < n; i++) a.push(v);
  return a;
}

// Rzut: zatrzymane kości zostają, reszta losowana. Zwraca nowy stan.
export function rollHand(hand, rand) {
  const old = hand.values;
  const values = [];
  for (let i = 0; i < hand.count; i++) {
    values.push(old && hand.locked[i] ? old[i] : rollDie(hand.sides, rand));
  }
  return { ...hand, values, prev: old ? sum(old) : hand.prev };
}

// Przypadkowe ścianki do animacji toczenia (zatrzymane kości się nie ruszają)
export function tumbleFaces(hand, rand) {
  const out = [];
  for (let i = 0; i < hand.count; i++) {
    out.push(hand.values && hand.locked[i] ? hand.values[i] : rollDie(hand.sides, rand));
  }
  return out;
}

// Zatrzymanie / puszczenie kości - dopiero po pierwszym rzucie, gdy wszystkie byłyby
// zatrzymane, rzut nic by nie zmienił, więc to też dozwolone (można puścić z powrotem)
export function toggleLock(hand, index) {
  if (!hand.values || index < 0 || index >= hand.count) return hand;
  const locked = hand.locked.slice();
  locked[index] = !locked[index];
  return { ...hand, locked };
}

export function allLocked(hand) {
  return !!hand.values && hand.locked.every((l) => l);
}

export function sum(values) {
  return values.reduce((a, b) => a + b, 0);
}

// Tekst pod kośćmi: suma i ewentualnie "Dublet!" (2 takie same), "Wszystkie N!" (3+)
export function summary(hand) {
  if (!hand.values) return { main: "", extra: "" };
  const v = hand.values;
  const same = v.every((x) => x === v[0]);
  let extra = "";
  if (v.length === 2 && same) extra = "Dublet!";
  else if (v.length >= 3 && same) extra = "Wszystkie " + v[0] + "!";
  else if (v.length === 1 && v[0] === hand.sides && hand.sides >= 10) extra = "Maksimum!";
  return { main: v.length > 1 ? "Suma " + sum(v) : "", extra };
}

// Restore z pamięci zegarka; null gdy zapis nie pasuje do ustawień
export function restoreHand(raw, cfg) {
  try {
    const h = typeof raw === "string" ? JSON.parse(raw) : raw;
    if (!h || h.count !== cfg.count || h.sides !== cfg.sides) return null;
    const ok = (a) => Array.isArray(a) && a.length === cfg.count;
    if (!ok(h.locked)) return null;
    if (h.values !== null && !(ok(h.values) && h.values.every((x) => x >= 1 && x <= cfg.sides))) return null;
    return {
      count: cfg.count,
      sides: cfg.sides,
      values: h.values,
      locked: h.locked.map((l) => !!l),
      prev: typeof h.prev === "number" ? h.prev : null,
    };
  } catch (e) {
    return null;
  }
}

// Oczka K6: 7 pozycji - lewa góra, prawa góra, lewa środek, prawa środek, lewa dół, prawa dół, środek
export const PIP_SPOTS = [
  [-1, -1],
  [1, -1],
  [-1, 0],
  [1, 0],
  [-1, 1],
  [1, 1],
  [0, 0],
];

const PIPS = {
  1: [6],
  2: [0, 5],
  3: [0, 6, 5],
  4: [0, 1, 4, 5],
  5: [0, 1, 4, 5, 6],
  6: [0, 1, 2, 3, 4, 5],
};

// Które z 7 oczek widać na danej ściance
export function pipsFor(face) {
  const on = PIPS[face] || [];
  return PIP_SPOTS.map((_, i) => on.indexOf(i) >= 0);
}

// Rozmieszczenie kości w projekcie 480 px (środki i bok), środek obszaru kości w (240, cy)
export function layoutDice(count, cy) {
  const c = cy === undefined ? 218 : cy;
  const row = (n, size, gap, y) => {
    const out = [];
    const w = n * size + (n - 1) * gap;
    for (let i = 0; i < n; i++) out.push({ cx: 240 - w / 2 + size / 2 + i * (size + gap), cy: y, size });
    return out;
  };
  switch (count) {
    case 1:
      return row(1, 170, 0, c);
    case 2:
      return row(2, 140, 30, c);
    case 3:
      return row(3, 118, 18, c);
    case 4:
      return [...row(2, 110, 20, c - 65), ...row(2, 110, 20, c + 65)];
    case 5:
      return [...row(3, 100, 16, c - 58), ...row(2, 100, 16, c + 58)];
    default:
      return [...row(3, 100, 16, c - 58), ...row(3, 100, 16, c + 58)];
  }
}

// Wykrywanie potrząśnięcia z akcelerometru (cm/s^2, grawitacja ok. 980):
// kilka mocnych odchyleń od 1 g w krótkim czasie, potem przerwa, żeby jeden
// potrząs nie dał dwóch rzutów.
export const SHAKE = { threshold: 900, hits: 3, windowMs: 700, cooldownMs: 1500 };

export function createShakeDetector(opts) {
  const o = { ...SHAKE, ...(opts || {}) };
  let times = [];
  let quietUntil = 0;
  return {
    // true = właśnie potrząśnięto
    feed(sample, now) {
      if (!sample || typeof sample.x !== "number") return false;
      if (now < quietUntil) return false;
      const mag = Math.sqrt(sample.x * sample.x + sample.y * sample.y + sample.z * sample.z);
      times = times.filter((t) => now - t <= o.windowMs);
      if (Math.abs(mag - 980) > o.threshold) times.push(now);
      if (times.length >= o.hits) {
        times = [];
        quietUntil = now + o.cooldownMs;
        return true;
      }
      return false;
    },
    // Po rzucie przyciskiem też chwila spokoju (ręka jeszcze się rusza)
    quiet(now, ms) {
      quietUntil = Math.max(quietUntil, now + (ms === undefined ? o.cooldownMs : ms));
      times = [];
    },
  };
}

// Odstępy kolejnych klatek toczenia (ms): coraz wolniej, ok. 0,7 s razem
export const TUMBLE_DELAYS = [45, 50, 55, 65, 75, 90, 110, 140];
