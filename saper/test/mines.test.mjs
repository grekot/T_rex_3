// Testy logiki Sapera: `node test/mines.test.mjs` (albo `npm test`). Nie wymagają zegarka.
import assert from "node:assert/strict";
import { LEVELS } from "../utils/geometry.js";
import {
  HIDDEN,
  OPEN,
  FLAG,
  READY,
  PLAYING,
  WON,
  LOST,
  levelById,
  neighbors,
  activeCells,
  newGame,
  placeMines,
  countAt,
  reveal,
  toggleFlag,
  chord,
  tileName,
  minesLeft,
  restoreGame,
  recordWin,
  formatClock,
  formatSeconds,
} from "../utils/mines.js";

let seed = 12345;
const rnd = () => {
  seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  return seed / 0x80000000;
};

// --- plansze -------------------------------------------------------------------
for (const level of LEVELS) {
  const n = level.cols * level.rows;
  assert.equal(level.active.length, n, level.id + ": maska ma złą długość");
  // rogi wycięte (wystają poza okrągły ekran), środek w grze
  for (const corner of [0, level.cols - 1, n - level.cols, n - 1]) {
    assert.equal(level.active[corner], "0", level.id + ": róg " + corner + " powinien być wycięty");
  }
  assert.equal(level.active[Math.floor(level.rows / 2) * level.cols + Math.floor(level.cols / 2)], "1");
  assert.ok(level.mines < activeCells(level).length - 9, level.id + ": za dużo min");
  assert.equal(level.cols * level.cell <= 360, true);
}
const easy = levelById("easy");
assert.equal(easy.cols, 6);
// pole obok wyciętego rogu ma o jednego sąsiada mniej
assert.deepEqual(neighbors(easy, 1).sort((a, b) => a - b), [2, 6, 7, 8]);
assert.equal(neighbors(easy, 7).length, 7); // sąsiad rogu (0) nie istnieje
assert.equal(neighbors(easy, 14).length, 8);

// --- pierwszy ruch jest zawsze bezpieczny i odsłania obszar ------------------------
for (const level of LEVELS) {
  for (let t = 0; t < 300; t++) {
    const g = newGame(level.id);
    const cells = activeCells(level);
    const first = cells[Math.floor(rnd() * cells.length)];
    const changed = reveal(g, first, rnd);
    assert.notEqual(g.status, LOST, "pierwszy ruch trafił na minę");
    assert.equal(g.mines.reduce((a, b) => a + b, 0), level.mines, "zła liczba min");
    assert.equal(countAt(g, first), 0, "pierwsze pole powinno być zerem");
    assert.ok(changed.length >= 4, "pierwszy ruch powinien odsłonić kawałek planszy");
    for (let i = 0; i < g.mines.length; i++) {
      if (g.mines[i]) assert.equal(level.active[i], "1", "mina na wyciętym polu");
    }
  }
}

// --- ręcznie ułożona plansza ---------------------------------------------------------
function gameWithMines(levelId, mineCells) {
  const g = newGame(levelId);
  const level = levelById(levelId);
  g.mines = new Array(level.cols * level.rows).fill(0);
  mineCells.forEach((i) => (g.mines[i] = 1));
  g.status = PLAYING;
  return g;
}

// łatwy 6x6: miny w 8 i 27 (5 min wymaga poziom, tu dla prostoty 2 - liczy się logika)
{
  const g = gameWithMines("easy", [8, 27]);
  assert.equal(countAt(g, 14), 1); // sąsiad 8
  assert.equal(countAt(g, 21), 1); // sąsiad 27
  assert.equal(tileName(g, 14), "hidden");

  // flaga chroni pole w trybie łopaty (reveal na fladze nic nie robi)
  assert.deepEqual(toggleFlag(g, 8), [8]);
  assert.equal(g.view[8], FLAG);
  assert.deepEqual(reveal(g, 8), []);
  assert.equal(minesLeft(g), 5 - 1);
  assert.equal(tileName(g, 8), "flag");

  // odkrycie zera rozlewa się, ale omija flagi i miny
  const changed = reveal(g, 23); // prawa krawędź, z dala od min
  assert.ok(changed.length > 5);
  assert.equal(g.view[8], FLAG);
  assert.equal(g.view[27], HIDDEN);

  // akord: wokół 14 jest jedna mina i jedna flaga -> odkrywa resztę sąsiadów
  if (g.view[14] !== OPEN) reveal(g, 14);
  const before = g.view.filter((v) => v === OPEN).length;
  chord(g, 14);
  assert.ok(g.view.filter((v) => v === OPEN).length >= before);
  assert.notEqual(g.status, LOST);
}

// akord przy źle postawionej fladze = przegrana
{
  const g = gameWithMines("easy", [8]);
  reveal(g, 14); // cyfra 1
  assert.equal(g.view[14], OPEN);
  toggleFlag(g, 15); // flaga obok, ale nie na minie
  const changed = chord(g, 14);
  assert.equal(g.status, LOST);
  assert.equal(g.boom, 8);
  assert.ok(changed.includes(8) && changed.includes(15));
  assert.equal(tileName(g, 8), "boom");
  assert.equal(tileName(g, 15), "wrong");
  // po przegranej nic się nie da zrobić
  assert.deepEqual(reveal(g, 20), []);
  assert.deepEqual(toggleFlag(g, 20), []);
}

// przegrana pokazuje wszystkie miny, trafiona jest czerwona
{
  const g = gameWithMines("easy", [8, 27]);
  toggleFlag(g, 27);
  reveal(g, 8);
  assert.equal(g.status, LOST);
  assert.equal(tileName(g, 8), "boom");
  assert.equal(tileName(g, 27), "flag"); // dobrze postawiona flaga zostaje flagą
}

// wygrana: odkryte wszystkie pola bez min, miny dostają flagi
{
  const g = gameWithMines("easy", [8]);
  const level = levelById("easy");
  for (const i of activeCells(level)) {
    if (i !== 8 && g.view[i] === HIDDEN) reveal(g, i);
  }
  assert.equal(g.status, WON);
  assert.equal(g.view[8], FLAG);
  assert.equal(tileName(g, 8), "flag");
}

// --- symulacja: gracz-automat z prostymi regułami nie może wysypać logiki ---------------
function autoPlay(levelId) {
  const level = levelById(levelId);
  const g = newGame(levelId);
  const cells = activeCells(level);
  reveal(g, cells[Math.floor(rnd() * cells.length)], rnd);
  for (let guard = 0; guard < 500 && g.status === PLAYING; guard++) {
    let moved = false;
    for (const i of cells) {
      if (g.view[i] !== OPEN) continue;
      const around = neighbors(level, i);
      const hidden = around.filter((j) => g.view[j] === HIDDEN);
      const flags = around.filter((j) => g.view[j] === FLAG).length;
      const n = countAt(g, i);
      if (hidden.length && hidden.length + flags === n) {
        hidden.forEach((j) => toggleFlag(g, j));
        moved = true;
      } else if (hidden.length && flags === n) {
        chord(g, i, rnd);
        moved = true;
      }
      if (g.status !== PLAYING) break;
    }
    if (!moved && g.status === PLAYING) {
      // zgadywanie - jak człowiek
      const hidden = cells.filter((j) => g.view[j] === HIDDEN);
      reveal(g, hidden[Math.floor(rnd() * hidden.length)], rnd);
    }
  }
  assert.ok(g.status === WON || g.status === LOST, "partia powinna się skończyć");
  if (g.status === WON) {
    for (const i of cells) assert.ok(g.mines[i] ? g.view[i] === FLAG : g.view[i] === OPEN);
  }
  return g.status;
}
for (const level of LEVELS) {
  const res = { [WON]: 0, [LOST]: 0 };
  for (let k = 0; k < 400; k++) res[autoPlay(level.id)]++;
  console.log(level.id + " - automat (400 gier):", res);
  assert.ok(res[WON] > 0, "automat powinien czasem wygrać");
}

// --- zapis i odczyt --------------------------------------------------------------------
{
  const g = newGame("medium");
  reveal(g, 27, rnd);
  toggleFlag(g, 0); // wycięty róg - nic się nie dzieje
  g.elapsed = 4200;
  const back = restoreGame(JSON.stringify(g));
  assert.deepEqual(back, g);
  assert.equal(restoreGame("{zepsute"), null);
  assert.equal(restoreGame(JSON.stringify({ ...g, level: "kosmos" })), null);
  assert.equal(restoreGame(JSON.stringify({ ...g, view: [1, 2, 3] })), null);
  assert.equal(restoreGame(JSON.stringify(newGame("hard"))).status, READY);
}
assert.equal(newGame("brak").level, LEVELS[0].id);

// --- rekordy i czas --------------------------------------------------------------------
{
  const stats = {};
  assert.equal(recordWin(stats, "easy", 50000), true);
  assert.equal(recordWin(stats, "easy", 60000), false);
  assert.equal(recordWin(stats, "easy", 41000), true);
  assert.deepEqual(stats, { easy: { best: 41000, wins: 3 } });
}
assert.equal(formatClock(0), "0:00");
assert.equal(formatClock(83500), "1:23");
assert.equal(formatClock(600000), "10:00");
assert.equal(formatSeconds(42900), "42");
assert.equal(formatSeconds(5000000), "999");

console.log("WSZYSTKIE TESTY OK");
