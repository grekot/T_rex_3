import assert from "node:assert/strict";
import {
  G,
  THROW,
  ROCK,
  BALANCE,
  throwDistance,
  createThrowDetector,
  newThrowGame,
  throwBall,
  createRocker,
  newBalance,
  stepBalance,
  calibrate,
  sideTilt,
  newGuess,
  guess,
} from "../utils/games.js";

let failed = 0;
function test(name, fn) {
  try {
    fn();
  } catch (e) {
    failed++;
    console.error("BŁĄD: " + name + "\n  " + e.message);
  }
}

const still = { x: 0, y: 0, z: G };
const T = 1000000;

// Ręka przechylona o kąt (stopnie) w bok
function tilted(deg) {
  const r = (deg * Math.PI) / 180;
  return { x: G * Math.sin(r), y: 0, z: G * Math.cos(r) };
}

test("odległość rzutu rośnie z siłą machnięcia", () => {
  assert.equal(throwDistance(0), 8);
  assert.equal(throwDistance(THROW.full), THROW.maxDist);
  assert.equal(throwDistance(99999), THROW.maxDist);
  assert.ok(throwDistance(1500) < throwDistance(2500));
});

test("detektor machnięcia: spokój nic nie daje, machnięcie jeden wynik", () => {
  const d = createThrowDetector();
  for (let i = 0; i < 50; i++) assert.equal(d.feed(still, T + i * 40), null);
  const results = [];
  const peaks = [700, 1800, 2600, 1200, 300, 0, 0, 0, 0, 0];
  peaks.forEach((p, i) => {
    const r = d.feed({ x: p, y: 0, z: G }, T + 2000 + i * 40);
    if (r !== null) results.push(r);
  });
  assert.equal(results.length, 1);
  assert.ok(Math.abs(results[0] - throwDistance(Math.hypot(2600, G) - G)) <= 1, String(results[0]));
  // zaraz po rzucie przerwa - drgania nie liczą się jako drugi rzut
  assert.equal(d.feed({ x: 2000, y: 0, z: G }, T + 2500), null);
});

test("gra w rzut: 2 złapane z 3 wygrywają", () => {
  let g = newThrowGame(5);
  assert.equal(g.targets.length, 3);
  g = throwBall(g, g.targets[0]);
  assert.equal(g.last.ok, true);
  assert.equal(g.done, false);
  g = throwBall(g, g.targets[1] + THROW.catchRange);
  assert.equal(g.done, true);
  assert.equal(g.win, true);

  let lost = newThrowGame(6);
  lost = throwBall(lost, lost.targets[0] + 30);
  lost = throwBall(lost, lost.targets[1] - 30);
  assert.equal(lost.done, true, "po dwóch pudłach już się nie da");
  assert.equal(lost.win, false);
});

function rockWith(sampler, ms) {
  const r = createRocker();
  for (let t = 0; t <= ms && !r.state.done; t += 40) r.feed(sampler(t), T + t);
  return r.state;
}

test("delikatne bujanie usypia", () => {
  const st = rockWith((t) => tilted(15 * Math.sin((2 * Math.PI * t) / 1600)), 30000);
  assert.equal(st.done, true);
  assert.equal(st.win, true, "energia " + st.energy + ", ciosy " + st.strikes);
  assert.ok(st.elapsed < 15000);
});

test("trzymanie nieruchomo nie usypia (po czasie przegrana)", () => {
  const st = rockWith(() => tilted(10), ROCK.limit + 1000);
  assert.equal(st.win, false);
  assert.equal(st.progress, 0);
  assert.equal(st.strikes, 0);
});

test("potrząsanie budzi", () => {
  const st = rockWith((t) => ({ x: 1500 * Math.sin((2 * Math.PI * t) / 250), y: 0, z: G }), 20000);
  assert.equal(st.done, true);
  assert.equal(st.win, false);
  assert.equal(st.strikes, ROCK.strikes);
});

test("balans: bez reakcji spada, z dobrą reakcją wytrzymuje", () => {
  let b = newBalance(3);
  b.pos = 0.05;
  for (let t = 0; t < BALANCE.time && !b.done; t += 40) stepBalance(b, 0, 40);
  assert.equal(b.done, true);
  assert.equal(b.win, false);
  assert.ok(b.elapsed < 8000, "spadł po " + b.elapsed);

  for (let seed = 1; seed <= 10; seed++) {
    b = newBalance(seed);
    b.pos = 0.1;
    // gracz reaguje z opóźnieniem 200 ms
    const hist = [];
    for (let t = 0; !b.done; t += 40) {
      hist.push({ pos: b.pos, vel: b.vel });
      const seen = hist[Math.max(0, hist.length - 6)];
      stepBalance(b, -0.6 * seen.pos - 0.3 * seen.vel, 40);
    }
    assert.equal(b.win, true, "seed " + seed + " spadł po " + b.elapsed);
  }
});

test("kalibracja i przechył w bok", () => {
  const samples = [null, tilted(40), tilted(10), tilted(10), tilted(10)];
  const zero = calibrate(samples);
  assert.ok(Math.abs(zero.x - tilted(10).x) < 1e-6);
  assert.ok(Math.abs(sideTilt(tilted(10), zero)) < 1e-9);
  // odczyt "w górę" (z > 0 przy ekranie do góry): większe x = prawa krawędź wyżej
  assert.ok(sideTilt(tilted(30), zero) < -0.2);
  const flipped = calibrate([{ x: 0, y: 0, z: -G }, { x: 0, y: 0, z: -G }]);
  assert.equal(flipped.zSign, -1);
  assert.ok(sideTilt({ x: 300, y: 0, z: -G }, flipped) > 0.2);
  assert.equal(sideTilt(null, zero), 0);
  assert.deepEqual(calibrate([]), { x: 0, y: 0, z: G, zSign: 1 });
});

test("lewo czy prawo: 3 trafienia wygrywają, 3 pudła przegrywają", () => {
  let g = newGuess(11);
  assert.equal(g.dirs.length, 5);
  const wrong = (d) => (d === "left" ? "right" : "left");
  for (let i = 0; i < 3; i++) g = guess(g, g.dirs[g.round]);
  assert.equal(g.done, true);
  assert.equal(g.win, true);
  let h = newGuess(12);
  for (let i = 0; i < 3; i++) h = guess(h, wrong(h.dirs[h.round]));
  assert.equal(h.done, true);
  assert.equal(h.win, false);
  assert.equal(guess(h, "left"), h);
  // obie strony losują się mniej więcej po równo
  let left = 0;
  for (let s = 1; s <= 200; s++) left += newGuess(s).dirs.filter((d) => d === "left").length;
  assert.ok(left > 400 && left < 600, String(left));
});

if (failed) {
  console.error(failed + " test(y) nie przeszły");
  process.exit(1);
}
console.log("games: wszystkie testy przeszły");
