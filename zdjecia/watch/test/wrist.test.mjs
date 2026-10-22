import assert from "node:assert/strict";
import { classify, wristState, feedWrist, tapState, tap, TAP_DOUBLE_MS } from "../utils/wrist.js";

const LOOK = { x: 50, y: -150, z: 960 };
const LOOK_NEG = { x: 50, y: -150, z: -960 };
const HANG = { x: 970, y: 100, z: 60 };
const MID = { x: 700, y: 0, z: 600 };

function run(st, samples, start, stepMs) {
  const out = [];
  samples.forEach((a, i) => {
    const ev = feedWrist(st, a, start + i * stepMs);
    if (ev) out.push(ev);
  });
  return out;
}

const rep = (a, n) => Array(n).fill(a);

// klasyfikacja, także odwrócony znak z
assert.equal(classify(LOOK), "look");
assert.equal(classify(LOOK_NEG), "look");
assert.equal(classify(HANG), "away");
assert.equal(classify(MID), "");
assert.equal(classify(null), "");
assert.equal(classify({ x: 10, y: 10, z: 10 }), "");

// ręka opuszczona, potem uniesiona: jedno "up", potem opuszczenie "down"
{
  const st = wristState();
  const ev = run(st, [...rep(HANG, 10), ...rep(LOOK, 5), ...rep(LOOK, 5), ...rep(HANG, 8)], 1000, 100);
  assert.deepEqual(ev, ["up", "down"]);
}

// ręka uniesiona od początku: brak zdarzenia, dopiero opuszczenie
{
  const st = wristState();
  assert.deepEqual(run(st, rep(LOOK, 10), 1000, 100), []);
  assert.deepEqual(run(st, rep(HANG, 10), 3000, 100), ["down"]);
}

// krótkie mignięcie pozycji (machanie) nie jest gestem
{
  const st = wristState();
  run(st, rep(HANG, 10), 1000, 100);
  assert.deepEqual(run(st, [LOOK, LOOK, HANG, HANG, HANG], 3000, 100), []);
}

// pozycja pośrednia przerywa odliczanie
{
  const st = wristState();
  run(st, rep(HANG, 10), 1000, 100);
  assert.deepEqual(run(st, [LOOK, LOOK, MID, LOOK, LOOK], 3000, 100), []);
  assert.deepEqual(run(st, [LOOK, LOOK], 3500, 100), ["up"]);
}

// stuknięcia
{
  const st = tapState();
  assert.equal(tap(st, 1000), "single");
  assert.equal(tap(st, 1000 + TAP_DOUBLE_MS - 50), "double");
  assert.equal(tap(st, 1500), "single");
  assert.equal(tap(st, 1500 + TAP_DOUBLE_MS + 50), "single");
}

console.log("wrist: ok");
