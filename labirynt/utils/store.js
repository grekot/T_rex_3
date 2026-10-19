// Pamięć zegarka: poziom, na którym gracz skończył, rekordy i ręczne odwrócenie osi.
import { LocalStorage } from "@zos/storage";

const storage = new LocalStorage();
// v2: od wersji 1.1 poziomy są inne (trudniejsze), więc postęp i rekordy liczymy od nowa
const LEVEL_KEY = "labirynt_level_v2";
const BEST_KEY = "labirynt_best_v2";
const FLIP_KEY = "labirynt_flip";

function readJson(key, fallback) {
  try {
    const raw = storage.getItem(key);
    if (!raw) return fallback;
    const v = JSON.parse(raw);
    return v === null || v === undefined ? fallback : v;
  } catch (e) {
    return fallback;
  }
}

function writeJson(key, value) {
  try {
    storage.setItem(key, JSON.stringify(value));
  } catch (e) {}
}

export function loadLevel() {
  const level = readJson(LEVEL_KEY, 1);
  return typeof level === "number" && level >= 1 ? Math.floor(level) : 1;
}

export function saveLevel(level) {
  writeJson(LEVEL_KEY, level);
}

// { maxLevel: najwyższy ukończony poziom, times: { "3": ms } }
export function loadBest() {
  const best = readJson(BEST_KEY, {});
  return {
    maxLevel: typeof best.maxLevel === "number" ? best.maxLevel : 0,
    times: best.times && typeof best.times === "object" ? best.times : {},
  };
}

// Zapisuje ukończenie poziomu; zwraca true, gdy czas jest nowym rekordem tego poziomu
export function recordLevel(level, ms) {
  const best = loadBest();
  best.maxLevel = Math.max(best.maxLevel, level);
  const old = best.times[level];
  const isRecord = !old || ms < old;
  if (isRecord) best.times[level] = ms;
  writeJson(BEST_KEY, best);
  return isRecord;
}

export function loadFlip() {
  const f = readJson(FLIP_KEY, {});
  return { x: !!f.x, y: !!f.y };
}

export function saveFlip(flip) {
  writeJson(FLIP_KEY, { x: !!flip.x, y: !!flip.y });
}
