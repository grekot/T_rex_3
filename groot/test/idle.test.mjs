import assert from "node:assert/strict";
import { ACTS, WALK_RANGE, newIdle, stepIdle, idleSprite, resetIdle } from "../utils/idle.js";

let failed = 0;
function test(name, fn) {
  try {
    fn();
  } catch (e) {
    failed++;
    console.error("BŁĄD: " + name + "\n  " + e.message);
  }
}

function mulberry(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

test("zajęcia: przez godzinę spaceruje, zajmuje się różnymi rzeczami i nie wychodzi poza zakres", () => {
  const rng = mulberry(7);
  const st = newIdle();
  const seen = new Set();
  let walks = 0;
  let prevAct = null;
  for (let f = 0; f < 6000; f++) {
    const before = st.kind;
    stepIdle(st, true, rng);
    if (st.kind === "walk" && before !== "walk") walks++;
    if (st.kind === "act") {
      seen.add(st.act);
      if (before !== "act") {
        assert.notEqual(st.act, prevAct, "to samo zajęcie dwa razy z rzędu");
        prevAct = st.act;
      }
    }
    assert.ok(Math.abs(st.x) <= WALK_RANGE, "za daleko: " + st.x);
    const sp = idleSprite(st, f);
    assert.ok(typeof sp.frame === "string" && sp.frame.length > 0);
    if (st.kind === "act") assert.match(sp.frame, /^act_(dance|flower|game|spores)[01]$/);
  }
  assert.equal(seen.size, ACTS.length, "nie wszystkie zajęcia: " + [...seen]);
  assert.ok(walks > 20, "za mało spacerów: " + walks);
});

test("forma bez klatek zajęć tylko stoi i spaceruje", () => {
  const rng = mulberry(3);
  const st = newIdle();
  for (let f = 0; f < 3000; f++) {
    stepIdle(st, false, rng);
    assert.notEqual(st.kind, "act");
    assert.match(idleSprite(st, f).frame, /^(idle[01]|left)$/);
  }
});

test("spacer w lewo używa klatki 'left', powrót na środek", () => {
  const st = newIdle();
  st.kind = "walk";
  st.target = -40;
  stepIdle(st, true, () => 0.5);
  assert.equal(st.x, -8);
  assert.equal(idleSprite(st, 0).frame, "left");
  resetIdle(st);
  assert.equal(st.x, 0);
  assert.equal(idleSprite(st, 0).frame, "idle0");
});

if (failed) {
  console.error(failed + " test(y) nie przeszły");
  process.exit(1);
}
console.log("idle: wszystkie testy przeszły");
