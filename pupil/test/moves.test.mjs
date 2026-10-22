import assert from "node:assert/strict";
import { G, calibrate } from "../utils/games.js";
import {
  vertTilt,
  createTiltReader,
  createFlick,
  createRepCounter,
  createStillness,
  SIMON,
  newSimon,
  simonInput,
  CATCH,
  newCatch,
  stepCatch,
  RUNNER,
  newRunner,
  runnerSpeed,
  jump,
  stepRunner,
  TREE,
  newTree,
  feedTree,
  DIG,
  newDig,
  feedDig,
  newBalloon,
  pump,
  releaseBalloon,
  EGG_LEVELS,
  newEggRoll,
  stepEggRoll,
  REFLEX,
  FISH,
  newSignalGame,
  stepSignal,
  resumeSignal,
  AIM,
  newAim,
  aimStep,
  shoot,
  RACE,
  newRace,
  feedRace,
  CALM,
  newCalm,
  feedCalm,
  WARMUP,
  newWarmup,
  feedWarmup,
} from "../utils/moves.js";

let failed = 0;
function test(name, fn) {
  try {
    fn();
  } catch (e) {
    failed++;
    console.error("BŁĄD: " + name + "\n  " + e.message);
  }
}

const T = 1000000;
const still = { x: 0, y: 0, z: G };
const zero = calibrate([still, still]);
// Ręka przechylona: rx w bok (dodatni = prawa krawędź wyżej), ry przód/tył (stopnie)
function tilted(rx, ry = 0) {
  const a = (rx * Math.PI) / 180;
  const b = (ry * Math.PI) / 180;
  return { x: G * Math.sin(a), y: G * Math.sin(b), z: G * Math.cos(a) * Math.cos(b) };
}
const shake = (amp, i) => ({ x: i % 2 ? amp : -amp, y: 0, z: G });
// ruch w górę i w dół (jak kopanie łopatą) o okresie per ms
function wave(amp, per, t) {
  return { x: 0, y: amp * Math.sin((2 * Math.PI * t) / per), z: G };
}

test("przechył przód/tył i odczyt kierunku z histerezą", () => {
  assert.ok(vertTilt(tilted(0, 30), zero) > 0.4);
  const r = createTiltReader();
  assert.equal(r.feed(0.1, 0), null);
  assert.equal(r.feed(0.5, 0.1), "right");
  assert.equal(r.feed(0.6, 0), null, "trzeba wrócić do poziomu");
  assert.equal(r.feed(0.05, 0), null);
  assert.equal(r.feed(0, -0.5), "up");
  r.feed(0, 0);
  assert.equal(r.feed(-0.4, 0.1), "left");
  r.feed(0, 0);
  assert.equal(r.feed(0, 0.45), "down");
});

test("szarpnięcie: jedno zdarzenie na ruch, przerwa", () => {
  const f = createFlick(700, 400);
  assert.equal(f.feed(still, T), false);
  assert.equal(f.feed({ x: 1500, y: 0, z: G }, T + 40), true);
  assert.equal(f.feed({ x: 1600, y: 0, z: G }, T + 80), false);
  assert.equal(f.feed(still, T + 120), false);
  assert.equal(f.feed({ x: 1500, y: 0, z: G }, T + 200), false, "przerwa");
  assert.equal(f.feed({ x: 1500, y: 0, z: G }, T + 500), true);
});

test("licznik powtórzeń liczy rytmiczny ruch, nie liczy spokoju", () => {
  const c = createRepCounter();
  for (let t = 0; t < 5000; t += 40) c.feed(wave(800, 600, t), T + t);
  assert.ok(c.count >= 6 && c.count <= 9, "powtórzeń " + c.count);
  const quiet = createRepCounter();
  for (let t = 0; t < 5000; t += 40) quiet.feed(wave(60, 600, t), T + t);
  assert.equal(quiet.count, 0);
});

test("spokój ręki: mała energia bez ruchu, duża przy ruchu", () => {
  const s = createStillness();
  let e = 0;
  for (let t = 0; t < 3000; t += 40) e = s.feed(tilted(5 + Math.sin(t / 300)), T + t);
  assert.ok(e < 15, "energia " + e);
  for (let t = 3000; t < 5000; t += 40) e = s.feed(wave(500, 500, t), T + t);
  assert.ok(e > 100, "energia " + e);
});

test("powtórz ruch: rundy rosną, pomyłka zabiera życie", () => {
  let g = newSimon(4);
  assert.equal(g.seq.length, SIMON.win);
  for (let i = 1; i < g.seq.length; i++) assert.notEqual(g.seq[i], g.seq[i - 1]);
  let r = simonInput(g, g.seq[0]);
  assert.equal(r.event, "ok");
  r = simonInput(r.game, g.seq[1]);
  assert.equal(r.event, "round");
  assert.equal(r.game.level, 3);
  const wrong = ["left", "right", "up", "down"].find((d) => d !== g.seq[0]);
  r = simonInput(r.game, wrong);
  assert.equal(r.event, "wrong");
  assert.equal(r.game.lives, SIMON.lives - 1);
  // dokończenie bezbłędne
  g = r.game;
  while (!g.done) g = simonInput(g, g.seq[g.pos]).game;
  assert.equal(g.win, true);
  // dwie pomyłki = koniec
  let h = newSimon(5);
  const bad = ["left", "right", "up", "down"].find((d) => d !== h.seq[0]);
  h = simonInput(h, bad).game;
  r = simonInput(h, bad);
  assert.equal(r.event, "lose");
  assert.equal(r.game.done, true);
});

test("łapanie owoców: gracz idący pod owoce wygrywa, stojący w miejscu nie", () => {
  for (let seed = 1; seed <= 5; seed++) {
    const g = newCatch(seed);
    while (!g.done) {
      const fruit = g.items.filter((i) => i.kind === "fruit").sort((a, b) => b.y - a.y)[0];
      const rocks = g.items.filter((i) => i.kind === "rock" && i.y > CATCH.h - 110 && Math.abs(i.x - g.x) < 60);
      let tilt = 0;
      if (rocks.length) tilt = rocks[0].x > g.x ? -1 : 1;
      else if (fruit) tilt = Math.max(-1, Math.min(1, (fruit.x - g.x) / 60));
      stepCatch(g, tilt, 40);
    }
    assert.equal(g.win, true, "seed " + seed + ": " + g.caught + " owoców, życia " + g.lives);
  }
  const lazy = newCatch(2);
  while (!lazy.done) stepCatch(lazy, 0, 40);
  assert.equal(lazy.win, false);
});

test("skoki: skaczący w porę wygrywa, nieskaczący wpada na przeszkodę", () => {
  const g = newRunner(3);
  while (!g.done) {
    // skok, gdy do przeszkody zostało ok. 0,12 s (jak człowiek, który patrzy)
    const front = RUNNER.dinoX + RUNNER.dinoW / 2;
    const near = g.obstacles.find((o) => o.x >= front && (o.x - front) / runnerSpeed(g) < 0.12);
    if (near) jump(g);
    stepRunner(g, 40);
  }
  assert.equal(g.win, true, "przeskoczył " + g.jumped);
  assert.ok(g.jumped >= 10);
  const lazy = newRunner(3);
  let ev = "";
  while (!lazy.done) ev = stepRunner(lazy, 40);
  assert.equal(ev, "hit");
  assert.equal(lazy.win, false);
  assert.equal(jump(lazy), false);
});

test("drzewo: potrząsanie zrzuca owoce, za mocne budzi pszczoły", () => {
  const g = newTree();
  for (let i = 0; i < 400 && !g.done; i++) feedTree(g, i % 6 < 3 ? shake(1500, i) : still, T + i * 40, 40);
  assert.equal(g.win, true, "owoców " + g.fruits);
  const rough = newTree();
  for (let i = 0; i < 400 && !rough.done; i++) feedTree(rough, i % 6 < 3 ? shake(4000, i) : still, T + i * 40, 40);
  assert.equal(rough.win, false);
  assert.equal(rough.bees, TREE.hardMax);
  const lazy = newTree();
  for (let i = 0; i < 500 && !lazy.done; i++) feedTree(lazy, still, T + i * 40, 40);
  assert.equal(lazy.win, false);
});

test("kopanie: rytmiczne ruchy odkopują kość w czasie", () => {
  const g = newDig();
  for (let t = 0; !g.done; t += 40) feedDig(g, wave(800, 700, t), T + t, 40);
  assert.equal(g.win, true);
  assert.equal(g.digs, DIG.need);
  const lazy = newDig();
  for (let t = 0; !lazy.done; t += 40) feedDig(lazy, still, T + t, 40);
  assert.equal(lazy.win, false);
});

test("balon: trafienie w przedział wygrywa, przesada pęka", () => {
  for (let seed = 1; seed <= 20; seed++) {
    const g = newBalloon(seed);
    assert.ok(g.lo >= 55 && g.hi <= 87);
    while (g.size < g.lo) pump(g);
    if (g.size <= g.hi) assert.equal(releaseBalloon(g).win, true, "seed " + seed);
    const b = newBalloon(seed);
    while (!b.done) pump(b);
    assert.equal(b.popped, true);
  }
  const early = newBalloon(1);
  pump(early);
  assert.equal(releaseBalloon(early).win, false);
});

test("labirynt jajka: każda plansza do przejścia, ściany zatrzymują", () => {
  EGG_LEVELS.forEach((L, i) => {
    const g = newEggRoll(i);
    // prosty autopilot: najpierw do punktów pośrednich omijających ściany
    const way = i === 0 ? [[250, 40], [250, 140], [40, 140], [40, 250], [255, 255]] : i === 1 ? [[40, 30], [150, 30], [150, 270], [255, 270], [255, 40]] : [[275, 40], [275, 140], [150, 140], [150, 260]];
    let k = 0;
    for (let n = 0; n < 2000 && !g.done; n++) {
      const [wx, wy] = way[Math.min(k, way.length - 1)];
      const dx = wx - g.x;
      const dy = wy - g.y;
      if (Math.hypot(dx, dy) < 12 && k < way.length - 1) k++;
      const tx = Math.max(-1, Math.min(1, dx / 60 - g.vx / 300));
      const ty = Math.max(-1, Math.min(1, dy / 60 - g.vy / 300));
      stepEggRoll(g, tx, ty, 20);
    }
    assert.equal(g.win, true, "plansza " + i + " jajo na " + Math.round(g.x) + "," + Math.round(g.y));
  });
  // przechył prosto w ścianę: jajo nie przenika
  const g = newEggRoll(0);
  for (let n = 0; n < 300; n++) stepEggRoll(g, 0, 1, 20);
  assert.ok(g.y < 90, "jajo przeszło przez ścianę: " + g.y);
});

test("refleks: szybkie reakcje wygrywają, falstarty i spóźnienia przegrywają", () => {
  let now = T;
  const g = newSignalGame(7, REFLEX, now);
  while (!g.done) {
    now += 20;
    resumeSignal(g, now);
    const flick = g.phase === "go" && now - g.goAt >= 300;
    stepSignal(g, now, flick);
  }
  assert.equal(g.win, true, "średnio " + g.avg);
  assert.ok(g.avg >= 300 && g.avg < 340);
  now = T;
  const slow = newSignalGame(7, REFLEX, now);
  while (!slow.done) {
    now += 20;
    resumeSignal(slow, now);
    stepSignal(slow, now, slow.phase === "go" && now - slow.goAt >= 900);
  }
  assert.equal(slow.win, false);
  now = T;
  const eager = newSignalGame(8, REFLEX, now);
  const ev = stepSignal(eager, now + 100, true);
  assert.equal(ev, "early");
});

test("wędkowanie: poderwanie w oknie łowi rybę", () => {
  let now = T;
  const g = newSignalGame(3, FISH, now);
  const events = [];
  while (!g.done) {
    now += 20;
    resumeSignal(g, now);
    const e = stepSignal(g, now, g.phase === "go" && now - g.goAt >= 500);
    if (e) events.push(e);
  }
  assert.equal(g.win, true);
  assert.deepEqual(events.filter((e) => e !== "go"), ["ok", "ok", "ok"]);
  now = T;
  const late = newSignalGame(3, FISH, now);
  while (!late.done) {
    now += 20;
    resumeSignal(late, now);
    stepSignal(late, now, false);
  }
  assert.equal(late.win, false);
  assert.ok(late.results.every((r) => r.late));
});

test("celowanie: celownik idzie za przechyłem, trafienia liczą się", () => {
  const g = newAim(5);
  for (let i = 0; i < 40; i++) aimStep(g, g.tx / AIM.gain, g.ty / AIM.gain);
  assert.ok(Math.hypot(g.x - g.tx, g.y - g.ty) < 3);
  assert.equal(shoot(g), true);
  while (!g.done) {
    for (let i = 0; i < 40; i++) aimStep(g, g.tx / AIM.gain, g.ty / AIM.gain);
    shoot(g);
  }
  assert.equal(g.win, true);
  const miss = newAim(6);
  while (!miss.done) shoot(miss) || aimStep(miss, 0.6, 0.6);
  assert.equal(miss.win, false);
  assert.ok(miss.shots <= AIM.shots);
});

test("wyścig: szybkie machanie wygrywa, powolne przegrywa", () => {
  const fast = newRace();
  for (let t = 0; !fast.done; t += 40) feedRace(fast, wave(800, 450, t), T + t, 40);
  assert.equal(fast.win, true, fast.you + " vs " + fast.rival);
  const slow = newRace();
  for (let t = 0; !slow.done; t += 40) feedRace(slow, wave(800, 1400, t), T + t, 40);
  assert.equal(slow.win, false, slow.you + " vs " + slow.rival);
  assert.ok(Math.abs(fast.rival - (RACE.rival * RACE.time) / 1000) < 0.1);
});

test("medytacja: spokojna ręka wygrywa, ruchliwa nie", () => {
  const g = newCalm();
  for (let t = 0; !g.done; t += 40) feedCalm(g, tilted(10 + Math.sin(t / 700) * 0.5), T + t, 40);
  assert.equal(g.win, true);
  assert.ok(g.elapsed < CALM.need + 2000);
  const fidget = newCalm();
  for (let t = 0; !fidget.done; t += 40) feedCalm(fidget, wave(300, 900, t), T + t, 40);
  assert.equal(fidget.win, false);
});

test("rozgrzewka: trzy ćwiczenia po kolei", () => {
  const g = newWarmup();
  let t = 0;
  const events = [];
  while (!g.done && t < WARMUP.limit) {
    let a;
    if (g.step < 2) a = wave(900, 700, t);
    else a = Math.floor(t / 800) % 2 ? tilted(80) : still;
    const e = feedWarmup(g, a, T + t, 40);
    if (e === "next") events.push(g.step);
    t += 40;
  }
  assert.equal(g.win, true, "krok " + g.step);
  assert.deepEqual(events, [1, 2, 3]);
  const lazy = newWarmup();
  for (let k = 0; !lazy.done; k += 40) feedWarmup(lazy, still, T + k, 40);
  assert.equal(lazy.win, false);
});

if (failed) {
  console.error(failed + " test(y) nie przeszły");
  process.exit(1);
}
console.log("moves: wszystkie testy przeszły");
