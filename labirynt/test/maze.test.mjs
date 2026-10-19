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
  holePull,
  atGoal,
  formatClock,
} from "../utils/maze.js";
import { PHYS, HARDEST_LEVEL, physicsFor, calibrate, tiltToAccel, collideRects, collideCircle, step } from "../utils/physics.js";

// --- rozmiary i postęp poziomów ----------------------------------------------------
assert.deepEqual([1, 2, 3, 4, 5, 6, 7, 8, 30].map((l) => sizeForLevel(l).n), [7, 7, 8, 9, 9, 10, 10, 11, 11]);
assert.equal(holesForLevel(1, 45), 2);
assert.equal(holesForLevel(2, 45), 3);
assert.equal(holesForLevel(30, 45), 9); // limit 1 dziura na 5 pól

// kulka coraz bardziej śliska aż do HARDEST_LEVEL, potem bez zmian
assert.deepEqual(physicsFor(1), PHYS);
assert.deepEqual(physicsFor(HARDEST_LEVEL), physicsFor(HARDEST_LEVEL + 30));
for (let l = 2; l <= HARDEST_LEVEL; l++) {
  const prev = physicsFor(l - 1);
  const cur = physicsFor(l);
  assert.ok(cur.friction < prev.friction && cur.gain > prev.gain && cur.pull > prev.pull);
}
assert.ok(physicsFor(HARDEST_LEVEL).friction > 0.3, "kulka musi dać się zatrzymać");
for (const s of SIZES) {
  const n = s.n;
  for (const corner of [0, n - 1, n * n - n, n * n - 1]) assert.equal(s.active[corner], "0", n + ": róg w grze");
  assert.ok(s.cell - s.wall > 2 * s.ball + 4, n + ": kulka nie mieści się w korytarzu");
  assert.ok(s.hole > s.ball, n + ": dziura mniejsza od kulki");
}

const a = rng(5);
const b = rng(5);
for (let k = 0; k < 10; k++) assert.equal(a(), b());

// --- labirynty: spójne, dziury poza drogą, pułapki na zakrętach -------------------------------------
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
  // drzewo + przejścia otwarte do pułapek na zakrętach
  const edges = lv.links.reduce((sum, l) => sum + l.length, 0) / 2;
  assert.equal(edges, cells.length - 1 + lv.opened.length);
  assert.ok(lv.traps.length >= Math.min(2, lv.holes.length), "za mało pułapek na zakrętach, poziom " + level);
  for (const t of lv.traps) {
    const k = lv.path.findIndex((i) => lv.links[i].indexOf(t) !== -1 && lv.links[t].indexOf(i) !== -1);
    assert.ok(k > 0, "pułapka nie przylega do drogi");
  }
  // da się dojechać do mety, omijając pola z dziurami - i to tą samą drogą
  const blocked = {};
  lv.holes.forEach((h) => (blocked[h] = true));
  const safe = { [lv.start]: 0 };
  const queue = [lv.start];
  for (let q = 0; q < queue.length; q++) {
    for (const j of lv.links[queue[q]]) {
      if (blocked[j] || safe[j] !== undefined) continue;
      safe[j] = safe[queue[q]] + 1;
      queue.push(j);
    }
  }
  assert.equal(safe[lv.goal], lv.path.length - 1, "droga do mety zablokowana albo skrócona, poziom " + level);
  const { dist } = distances(lv.links, lv.start);
  for (const i of cells) assert.ok(dist[i] >= 0, "pole " + i + " nieosiągalne");
  assert.equal(lv.path[0], lv.start);
  assert.equal(lv.path[lv.path.length - 1], lv.goal);
  assert.ok(lv.path.length >= s.n, "za krótka droga do mety: " + lv.path.length);
  assert.equal(lv.holes.length, holesForLevel(level, cells.length), "za mało miejsca na dziury, poziom " + level);
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
  const phys = physicsFor(level);
  const ball = { x: lv.startPoint.x, y: lv.startPoint.y, vx: 0, vy: 0 };
  const collide = (bb) => collideRects(bb, r, lv.walls, lv.index[cellAt(s, bb.x, bb.y)], phys.restitution);
  let target = 1;
  const dt = 1 / 30;
  for (let t = 0; t < 30 * 120; t++) {
    const p = cellCenter(s, lv.path[Math.min(target, lv.path.length - 1)]);
    const want = { x: (p.x - ball.x) * 6 - ball.vx * 2.2, y: (p.y - ball.y) * 6 - ball.vy * 2.2 };
    const max = 600; // tyle daje mocne pochylenie zegarka
    const len = Math.hypot(want.x, want.y);
    const acc = len > max ? { ax: (want.x / len) * max, ay: (want.y / len) * max } : { ax: want.x, ay: want.y };
    const pull = holePull(lv, ball, phys.pull);
    step(ball, { ax: acc.ax + pull.ax, ay: acc.ay + pull.ay }, dt, r, collide, phys);
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
for (let level = 1; level <= 25; level++) times.push(autopilot(level).toFixed(1));
console.log("autopilot - czas przejazdu poziomów 1-25 [s]:", times.join(" "));

// --- chaos: losowe pochylenia nie wyrzucą kulki z labiryntu ---------------------------------
for (const level of [1, 5, 9, 12, 25]) {
  const lv = buildLevel(level);
  const s = lv.size;
  const r = s.ball;
  const phys = physicsFor(level);
  const ball = { x: lv.startPoint.x, y: lv.startPoint.y, vx: 0, vy: 0 };
  const rnd = rng(level);
  let acc = { ax: 0, ay: 0 };
  for (let t = 0; t < 30 * 60; t++) {
    if (t % 15 === 0) acc = { ax: (rnd() - 0.5) * 1600, ay: (rnd() - 0.5) * 1600 };
    const collide = (bb) => collideRects(bb, r, lv.walls, lv.index[cellAt(s, bb.x, bb.y)], phys.restitution);
    step(ball, acc, 1 / 30, r, collide, phys);
    assert.ok(isActive(s, cellAt(s, ball.x, ball.y)), "kulka uciekła z labiryntu (poziom " + level + ")");
    assert.ok(Math.hypot(ball.vx, ball.vy) <= phys.maxSpeed + 1e-6);
  }
}

// --- dziura i meta -------------------------------------------------------------------------
{
  const lv = buildLevel(4);
  const h = lv.holePoints[0];
  assert.equal(holeUnder(lv, { x: h.x + 3, y: h.y - 2 }), 0);
  assert.equal(holeUnder(lv, { x: h.x + lv.size.hole, y: h.y }), -1);
  // wciąganie: na brzegu dziury kulka jest ściągana do środka, z daleka nie
  const near = { x: h.x + lv.size.hole + 2, y: h.y };
  const pull = holePull(lv, near, 1000);
  assert.ok(pull.ax < -10 && Math.abs(pull.ay) < 1e-9, "brzeg dziury powinien ciągnąć do środka");
  assert.deepEqual(holePull(lv, { x: h.x + lv.size.cell, y: h.y }, 1000), { ax: 0, ay: 0 });
  // kulka stojąca na brzegu dziury sama do niej wpada
  const ball = { ...near, vx: 0, vy: 0 };
  let fell = false;
  for (let t = 0; t < 60 && !fell; t++) {
    const p = holePull(lv, ball, physicsFor(4).pull);
    step(ball, p, 1 / 30, lv.size.ball, () => 0, physicsFor(4));
    fell = holeUnder(lv, ball) === 0;
  }
  assert.ok(fell, "kulka na brzegu dziury powinna wpaść");
  assert.ok(atGoal(lv, lv.goalPoint));
  assert.ok(!atGoal(lv, lv.startPoint));
}
assert.equal(formatClock(83500), "1:23");

console.log("WSZYSTKIE TESTY OK");
