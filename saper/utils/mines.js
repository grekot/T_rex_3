// Czysta logika Sapera - bez UI, dzięki temu da się ją przetestować w Node.
// Stan gry to zwykły obiekt JSON (zapisywany w pamięci zegarka między uruchomieniami).
import { LEVELS } from "./geometry.js";

// Co gracz widzi na polu
export const HIDDEN = 0;
export const OPEN = 1;
export const FLAG = 2;

// Etapy partii: miny losujemy dopiero przy pierwszym odkryciu (pierwszy ruch nigdy nie trafia na minę)
export const READY = "ready";
export const PLAYING = "playing";
export const WON = "won";
export const LOST = "lost";

export function levelById(id) {
  for (const level of LEVELS) {
    if (level.id === id) return level;
  }
  return null;
}

export function levelOf(game) {
  return levelById(game.level);
}

export function isActive(level, i) {
  return level.active.charAt(i) === "1";
}

// Sąsiedzi pola w grze (pola wycięte z okrągłej planszy się nie liczą)
export function neighbors(level, i) {
  const { cols, rows } = level;
  const r = Math.floor(i / cols);
  const c = i % cols;
  const out = [];
  for (let dr = -1; dr <= 1; dr++) {
    for (let dc = -1; dc <= 1; dc++) {
      if (dr === 0 && dc === 0) continue;
      const rr = r + dr;
      const cc = c + dc;
      if (rr < 0 || rr >= rows || cc < 0 || cc >= cols) continue;
      const j = rr * cols + cc;
      if (isActive(level, j)) out.push(j);
    }
  }
  return out;
}

export function activeCells(level) {
  const out = [];
  for (let i = 0; i < level.active.length; i++) {
    if (isActive(level, i)) out.push(i);
  }
  return out;
}

export function newGame(levelId) {
  const level = levelById(levelId) || LEVELS[0];
  const view = [];
  for (let i = 0; i < level.cols * level.rows; i++) view.push(HIDDEN);
  return { level: level.id, mines: null, view, status: READY, boom: -1, elapsed: 0 };
}

export function isOver(game) {
  return game.status === WON || game.status === LOST;
}

// Losuje miny z pominięciem pierwszego pola i jego sąsiadów, żeby pierwszy ruch
// odsłonił kawałek planszy. Na ciasnej planszy chroni tylko samo pole.
export function placeMines(game, first, rnd = Math.random) {
  const level = levelOf(game);
  const safe = [first].concat(neighbors(level, first));
  let candidates = activeCells(level).filter((i) => safe.indexOf(i) === -1);
  if (candidates.length < level.mines) {
    candidates = activeCells(level).filter((i) => i !== first);
  }
  const mines = [];
  for (let i = 0; i < level.cols * level.rows; i++) mines.push(0);
  for (let k = 0; k < level.mines && candidates.length; k++) {
    const pick = Math.floor(rnd() * candidates.length);
    mines[candidates[pick]] = 1;
    candidates.splice(pick, 1);
  }
  game.mines = mines;
}

export function countAt(game, i) {
  if (!game.mines) return 0;
  let n = 0;
  for (const j of neighbors(levelOf(game), i)) n += game.mines[j];
  return n;
}

export function flagCount(game) {
  let n = 0;
  for (const v of game.view) if (v === FLAG) n++;
  return n;
}

// Licznik w rogu ekranu: miny minus postawione flagi (może zejść poniżej zera)
export function minesLeft(game) {
  return levelOf(game).mines - flagCount(game);
}

// Odkrywa pole. Zwraca listę pól, których wygląd się zmienił.
export function reveal(game, i, rnd = Math.random) {
  const level = levelOf(game);
  if (isOver(game) || !isActive(level, i) || game.view[i] !== HIDDEN) return [];
  if (!game.mines) {
    placeMines(game, i, rnd);
    game.status = PLAYING;
  }
  if (game.mines[i]) return lose(game, i);

  const changed = [];
  const stack = [i];
  while (stack.length) {
    const j = stack.pop();
    if (game.view[j] !== HIDDEN) continue;
    game.view[j] = OPEN;
    changed.push(j);
    // "zero" odsłania sąsiadów sam; flag nie ruszamy
    if (countAt(game, j) === 0) {
      for (const k of neighbors(level, j)) {
        if (game.view[k] === HIDDEN) stack.push(k);
      }
    }
  }
  return changed.concat(checkWin(game));
}

// Stawia albo zdejmuje flagę
export function toggleFlag(game, i) {
  if (isOver(game) || !isActive(levelOf(game), i)) return [];
  if (game.view[i] === HIDDEN) game.view[i] = FLAG;
  else if (game.view[i] === FLAG) game.view[i] = HIDDEN;
  else return [];
  return [i];
}

// Stuknięcie w odkrytą cyfrę: gdy wokół stoi tyle flag, ile pokazuje cyfra,
// odkrywamy resztę sąsiadów (jak klik obydwoma przyciskami myszy w klasycznym Saperze).
export function chord(game, i, rnd = Math.random) {
  if (game.status !== PLAYING || game.view[i] !== OPEN) return [];
  const around = neighbors(levelOf(game), i);
  const flags = around.filter((j) => game.view[j] === FLAG).length;
  const hidden = around.filter((j) => game.view[j] === HIDDEN);
  if (flags !== countAt(game, i) || hidden.length === 0) return [];
  let changed = [];
  for (const j of hidden) {
    changed = changed.concat(reveal(game, j, rnd));
    if (isOver(game)) break;
  }
  return changed;
}

function lose(game, i) {
  game.status = LOST;
  game.boom = i;
  const changed = [];
  for (let j = 0; j < game.view.length; j++) {
    if (game.mines[j] || game.view[j] === FLAG) changed.push(j);
  }
  return changed;
}

function checkWin(game) {
  const level = levelOf(game);
  for (const j of activeCells(level)) {
    if (!game.mines[j] && game.view[j] !== OPEN) return [];
  }
  game.status = WON;
  // jak w klasycznym Saperze: po wygranej wszystkie miny dostają flagi
  const changed = [];
  for (const j of activeCells(level)) {
    if (game.mines[j] && game.view[j] !== FLAG) {
      game.view[j] = FLAG;
      changed.push(j);
    }
  }
  return changed;
}

// Nazwa kafelka (pliku PNG) do narysowania na polu
export function tileName(game, i) {
  const v = game.view[i];
  if (game.status === LOST) {
    if (i === game.boom) return "boom";
    if (v === FLAG) return game.mines[i] ? "flag" : "wrong";
    if (game.mines[i]) return "mine";
  }
  if (v === FLAG) return "flag";
  if (v === OPEN) return "n" + countAt(game, i);
  return "hidden";
}

// Odtwarza zapisaną partię; null, gdy zapis jest uszkodzony albo z innej wersji planszy
export function restoreGame(json) {
  try {
    const g = typeof json === "string" ? JSON.parse(json) : json;
    const level = g && levelById(g.level);
    if (!level) return null;
    const n = level.cols * level.rows;
    if (!Array.isArray(g.view) || g.view.length !== n) return null;
    if (g.mines !== null && (!Array.isArray(g.mines) || g.mines.length !== n)) return null;
    if ([READY, PLAYING, WON, LOST].indexOf(g.status) === -1) return null;
    return {
      level: level.id,
      mines: g.mines,
      view: g.view,
      status: g.status,
      boom: typeof g.boom === "number" ? g.boom : -1,
      elapsed: typeof g.elapsed === "number" ? g.elapsed : 0,
    };
  } catch (e) {
    return null;
  }
}

// Rekordy: { [levelId]: { best: ms, wins: n } }. Zwraca true, gdy padł nowy rekord.
export function recordWin(stats, levelId, ms) {
  const entry = stats[levelId] || { best: 0, wins: 0 };
  entry.wins = (entry.wins || 0) + 1;
  const isRecord = !entry.best || ms < entry.best;
  if (isRecord) entry.best = ms;
  stats[levelId] = entry;
  return isRecord;
}

// 83 500 ms -> "1:23"
export function formatClock(ms) {
  const total = Math.floor(ms / 1000);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return m + ":" + (s < 10 ? "0" : "") + s;
}

// Licznik czasu na planszy: same sekundy, jak w klasycznym Saperze (max 999)
export function formatSeconds(ms) {
  return String(Math.min(999, Math.floor(ms / 1000)));
}
