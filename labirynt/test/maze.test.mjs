// Testy Labiryntu: `node test/maze.test.mjs` (albo `npm test`). Nie wymagają zegarka.
import assert from "node:assert/strict";
import { SIZES } from "../utils/geometry.js";
import {
  sizeForLevel,
  holesForLevel,
  rng,
  isActive,
  gridNeighbors,
  cellCenter,
  cellAt,
  distances,
  buildLevel,
  holeUnder,
  atGoal,
  formatClock,
} from "../utils/maze.js";
import { PHYS, calibrate, tiltToAccel, collideRects, collideCircle, step } from "../utils/physics.js";

// --- rozmiary i postęp poziomów ----------------------------------------------------
assert.deepEqual([1, 2, 3, 4, 5, 8, 9, 30].map((l) => sizeForLevel(l).n), [5, 5, 6, 6, 7, 8, 9, 9]);
assert.equal(holesForLevel(1, 21), 0);
assert.equal(holesForLevel(2, 21), 1);
assert.equal(holesForLevel(30, 21), 2); // limit 1 dziura na 8 pól
for (const s of SIZES) {
  const n = s.n;
  for (const corner of [0, n - 1, n * n - n, n * n - 1]) assert.equal(s.active[corner], "0", n + ": róg w grze");
  assert.ok(s.cell - s.wall > 2 * s.ball + 4, n + ": kulka nie mieści się w korytarzu");
  assert.ok(s.hole > s.ball, n + ": dziura mniejsza od kulki");
}

const a = rng(5);
const b = rng(5);
for (let k = 0; k < 10; k++) assert.equal(a(), b());

// --- labirynty: spójne, bez pętli, dziury poza drogą -------------------------------------
function pointInRect(p, w) {
  return p.x >= w.x && p.x <= w.x + w.w && p.y >= w.y && p.y <= w.y + w.h;
}
function clearance(p, walls) {
  let best = Infinity;
  for (const w of walls) {
    const cx = Math.max(w.x, Math.min(p.x, w.x + w.w));
    const cy = Math.max(w.y, Math.min(p.y, w.y + w.h));
    best = Math.min(best, Math.hypot(p.x - cx, p.y - cy));
  }
  return best;
}

for (let level = 1; level <= 40; level++) {
  const lv = buildLevel(level);
  const s = lv.size;
  const cells = [];
  for (let i = 0; i < s.n * s.n; i++) if (isActive(s, i)) cells.push(i);
  const edges = lv.links.reduce((sum, l) => sum + l.length, 0) / 2;
  assert.equal(edges, cells.length - 1, "labirynt powinien być drzewem (bez pętli)");
  const { dist } = distances(lv.links, lv.start);
  for (const i of cells) assert.ok(dist[i] >= 0, "pole " + i + " nieosiągalne");
  assert.equal(lv.path[0], lv.start);
  assert.equal(lv.path[lv.path.length - 1], lv.goal);
  assert.ok(lv.path.length >= s.n, "za krótka droga do mety: " + lv.path.length);
  assert.equal(lv.holes.length, Math.min(holesForLevel(level, cells.length), lv.holes.length));
  if (level >= 2) assert.ok(lv.holes.length >= 1, "poziom " + level + " bez dziur");
  for (const h of lv.holes) {
    assert.ok(lv.path.indexOf(h) === -1, "dziura na drodze do mety");
    assert.ok(dist[h] > 1, "dziura przy starcie");
  }
  // przejścia są wolne, a między polami bez przejścia stoi ściana
  for (const i of cells) {
    const c = cellCenter(s, i);
    assert.ok(clearance(c, lv.walls) > s.ball, "środek pola za blisko ściany");
    for (const j of gridNeighbors(s, i)) {
      const d = cellCenter(s, j);
      const mid = { x: (c.x + d.x) / 2, y: (c.y + d.y) / 2 };
      const linked = lv.links[i].indexOf(j) !== -1;
      if (linked) assert.ok(clearance(mid, lv.walls) > s.ball, "przejście zablokowane " + i + "-" + j);
      else assert.ok(lv.walls.some((w) => pointInRect(mid, w)), "brak ściany " + i + "-" + j);
    }
  }
  // ten sam poziom = ten sam labirynt
  assert.deepEqual(buildLevel(level).walls, lv.walls);
}
assert.notDeepEqual(buildLevel(3).walls, buildLevel(4).walls);

// --- akcelerometr -> kierunek toczenia --------------------------------------------------------
{
  // pierwsza połowa odczytów (drganie po stuknięciu) się nie liczy
  const flat = calibrate([{ x: 400, y: 400, z: -50 }, { x: 0, y: 0, z: 0 }, { x: 10, y: -20, z: 975 }, { x: 14, y: -16, z: 985 }]);
  assert.deepEqual(flat, { x: 12, y: -18, zSign: 1 });
  assert.deepEqual(calibrate([]), { x: 0, y: 0, zSign: 1 });
  // konwencja „w górę” (z > 0): prawa krawędź w dół -> x ujemne -> kulka w prawo
  let acc = tiltToAccel({ x: 12 - 300, y: -18, z: 930 }, flat, null);
  assert.ok(acc.ax > 0 && acc.ay === 0);
  // „12” w dół -> y ujemne -> kulka w górę ekranu
  acc = tiltToAccel({ x: 12, y: -18 - 300, z: 930 }, flat, null);
  assert.ok(acc.ay < 0 && acc.ax === 0);
  // konwencja „grawitacja” (z < 0): te same pochylenia mają odwrotne znaki odczytu
  const flat2 = calibrate([{ x: 0, y: 0, z: -980 }]);
  assert.ok(tiltToAccel({ x: 300, y: 0, z: -930 }, flat2, null).ax > 0);
  assert.ok(tiltToAccel({ x: 0, y: 300, z: -930 }, flat2, null).ay < 0);
  // ręczne odwrócenie osi
  assert.ok(tiltToAccel({ x: 300, y: 0, z: -930 }, flat2, { x: true, y: false }).ax < 0);
  assert.ok(tiltToAccel({ x: 0, y: 300, z: -930 }, flat2, { x: false, y: true }).ay > 0);
  // drżenie ręki w martwej strefie nie rusza kulki
  assert.deepEqual(tiltToAccel({ x: 20, y: -10, z: 980 }, flat, null), { ax: 0, ay: 0 });
}

// --- zderzenia ------------------------------------------------------------------------------
{
  const wall = [{ x: 100, y: 0, w: 10, h: 200 }];
  const ball = { x: 95, y: 50, vx: 200, vy: 0 };
  const impact = collideRects(ball, 10, wall, [0]);
  assert.equal(ball.x, 90);
  assert.ok(ball.vx < 0, "odbicie od ściany");
  assert.equal(impact, 200);
  const inside = { x: 103, y: 50, vx: 0, vy: 0 };
  collideRects(inside, 10, wall, [0]);
  assert.equal(inside.x, 90); // wypchnięta najkrótszą drogą (w lewo)
  const c = { x: 240 + 200, y: 240, vx: 100, vy: 0 };
  assert.equal(collideCircle(c, 20, 240, 240, 150), 100);
  assert.equal(c.x, 240 + 130);
}

// --- autopilot: fizyka przeprowadza kulkę przez labirynt -----------------------------------
// Pilot celuje w kolejne pola drogi jak człowiek przechylający zegarek: przyspiesza
// w stronę celu i hamuje przed nim. Sprawdzamy, że kulka nigdy nie wchodzi w ścianę,
// nie opuszcza labiryntu i dojeżdża do mety.
function autopilot(level) {
  const lv = buildLevel(level);
  const s = lv.size;
  const r = s.ball;
  const ball = { x: lv.startPoint.x, y: lv.startPoint.y, vx: 0, vy: 0 };
  const collide = (bb) => collideRects(bb, r, lv.walls, lv.index[cellAt(s, bb.x, bb.y)]);
  let target = 1;
  const dt = 1 / 30;
  for (let t = 0; t < 30 * 120; t++) {
    const p = cellCenter(s, lv.path[Math.min(target, lv.path.length - 1)]);
    const want = { x: (p.x - ball.x) * 6 - ball.vx * 2.2, y: (p.y - ball.y) * 6 - ball.vy * 2.2 };
    const max = 600; // tyle daje mocne pochylenie zegarka
    const len = Math.hypot(want.x, want.y);
    const acc = len > max ? { ax: (want.x / len) * max, ay: (want.y / len) * max } : { ax: want.x, ay: want.y };
    step(ball, acc, dt, r, collide);
    for (const w of lv.walls) {
      assert.ok(clearance(ball, [w]) > r - 0.01, "kulka weszła w ścianę na poziomie " + level);
    }
    assert.ok(isActive(s, cellAt(s, ball.x, ball.y)), "kulka poza labiryntem");
    assert.equal(holeUnder(lv, ball), -1, "autopilot wpadł do dziury na poziomie " + level);
    if (Math.hypot(ball.x - p.x, ball.y - p.y) < s.cell * 0.25) target++;
    if (atGoal(lv, ball)) return t * dt;
  }
  assert.fail("autopilot nie dojechał do mety na poziomie " + level);
}
const times = [];
for (let level = 1; level <= 20; level++) times.push(autopilot(level).toFixed(1));
console.log("autopilot - czas przejazdu poziomów 1-20 [s]:", times.join(" "));

// --- chaos: losowe pochylenia nie wyrzucą kulki z labiryntu ---------------------------------
for (const level of [1, 5, 9, 12]) {
  const lv = buildLevel(level);
  const s = lv.size;
  const r = s.ball;
  const ball = { x: lv.startPoint.x, y: lv.startPoint.y, vx: 0, vy: 0 };
  const rnd = rng(level);
  let acc = { ax: 0, ay: 0 };
  for (let t = 0; t < 30 * 60; t++) {
    if (t % 15 === 0) acc = { ax: (rnd() - 0.5) * 1600, ay: (rnd() - 0.5) * 1600 };
    step(ball, acc, 1 / 30, r, (bb) => collideRects(bb, r, lv.walls, lv.index[cellAt(s, bb.x, bb.y)]));
    assert.ok(isActive(s, cellAt(s, ball.x, ball.y)), "kulka uciekła z labiryntu (poziom " + level + ")");
    assert.ok(Math.hypot(ball.vx, ball.vy) <= PHYS.maxSpeed + 1e-6);
  }
}

// --- dziura i meta -------------------------------------------------------------------------
{
  const lv = buildLevel(4);
  const h = lv.holePoints[0];
  assert.equal(holeUnder(lv, { x: h.x + 3, y: h.y - 2 }), 0);
  assert.equal(holeUnder(lv, { x: h.x + lv.size.hole, y: h.y }), -1);
  assert.ok(atGoal(lv, lv.goalPoint));
  assert.ok(!atGoal(lv, lv.startPoint));
}
assert.equal(formatClock(83500), "1:23");

console.log("WSZYSTKIE TESTY OK");
