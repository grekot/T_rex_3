import assert from "node:assert/strict";
import {
  normalizeConfig,
  configLabel,
  rollDie,
  newHand,
  rollHand,
  toggleLock,
  allLocked,
  tumbleFaces,
  summary,
  restoreHand,
  pipsFor,
  layoutDice,
  createShakeDetector,
  DICE_TYPES,
} from "../utils/dice.js";

let failed = 0;
function test(name, fn) {
  try {
    fn();
  } catch (e) {
    failed++;
    console.error("BŁĄD: " + name + "\n  " + e.message);
  }
}

// Powtarzalny "los" do testów
function seq(...values) {
  let i = 0;
  return () => values[i++ % values.length];
}

test("ustawienia: poprawne zostają, złe wracają do domyślnych", () => {
  assert.deepEqual(normalizeConfig({ count: 3, sides: 20, shake: false }), { count: 3, sides: 20, shake: false });
  assert.deepEqual(normalizeConfig({ count: 9, sides: 7 }), { count: 2, sides: 6, shake: true });
  assert.deepEqual(normalizeConfig(null), { count: 2, sides: 6, shake: true });
  assert.equal(configLabel({ count: 2, sides: 6 }), "2 × K6");
});

test("rollDie: zawsze 1..sides, także dla skrajnych losów", () => {
  for (const s of DICE_TYPES) {
    assert.equal(rollDie(s, () => 0), 1);
    assert.equal(rollDie(s, () => 0.999999), s);
    assert.equal(rollDie(s, () => 1), s); // gdyby generator zwrócił 1
  }
  const counts = [0, 0, 0, 0, 0, 0];
  for (let i = 0; i < 60000; i++) counts[rollDie(6) - 1]++;
  for (const c of counts) assert.ok(c > 9000 && c < 11000, "nierówny rozkład: " + counts);
});

test("rzut: zatrzymane kości zostają, poprzednia suma się zapamiętuje", () => {
  let h = newHand({ count: 3, sides: 6 });
  assert.equal(h.values, null);
  // przed pierwszym rzutem nie da się zatrzymać
  assert.equal(toggleLock(h, 0), h);
  h = rollHand(h, seq(0, 0.5, 0.99)); // 1, 4, 6
  assert.deepEqual(h.values, [1, 4, 6]);
  assert.equal(h.prev, null);
  h = toggleLock(h, 2);
  assert.deepEqual(h.locked, [false, false, true]);
  h = rollHand(h, seq(0.2, 0.2)); // 2, 2, (6 zatrzymana)
  assert.deepEqual(h.values, [2, 2, 6]);
  assert.equal(h.prev, 11);
  assert.deepEqual(tumbleFaces(h, () => 0), [1, 1, 6]);
  assert.equal(allLocked(h), false);
  h = toggleLock(toggleLock(h, 0), 1);
  assert.equal(allLocked(h), true);
});

test("podsumowanie: suma, dublet, wszystkie takie same, maksimum", () => {
  assert.deepEqual(summary({ values: null }), { main: "", extra: "" });
  assert.deepEqual(summary({ sides: 6, values: [3, 3] }), { main: "Suma 6", extra: "Dublet!" });
  assert.deepEqual(summary({ sides: 6, values: [5, 5, 5, 5, 5] }), { main: "Suma 25", extra: "Wszystkie 5!" });
  assert.deepEqual(summary({ sides: 6, values: [1, 2] }), { main: "Suma 3", extra: "" });
  assert.deepEqual(summary({ sides: 20, values: [20] }), { main: "", extra: "Maksimum!" });
  assert.deepEqual(summary({ sides: 6, values: [6] }), { main: "", extra: "" });
});

test("odtwarzanie zapisu pasującego do ustawień", () => {
  const cfg = { count: 2, sides: 6 };
  const h = { count: 2, sides: 6, values: [3, 5], locked: [true, false], prev: 7 };
  assert.deepEqual(restoreHand(JSON.stringify(h), cfg), h);
  assert.equal(restoreHand(JSON.stringify(h), { count: 3, sides: 6 }), null);
  assert.equal(restoreHand(JSON.stringify({ ...h, values: [3, 9] }), cfg), null);
  assert.equal(restoreHand("zepsute", cfg), null);
  assert.deepEqual(restoreHand({ ...h, values: null, prev: undefined }, cfg).values, null);
});

test("oczka K6", () => {
  for (let f = 1; f <= 6; f++) assert.equal(pipsFor(f).filter(Boolean).length, f);
  assert.deepEqual(pipsFor(1), [false, false, false, false, false, false, true]);
});

test("rozmieszczenie: kości w okręgu ekranu i bez nakładania", () => {
  for (let n = 1; n <= 6; n++) {
    const l = layoutDice(n);
    assert.equal(l.length, n);
    for (const d of l) {
      const h = d.size / 2;
      for (const [x, y] of [[d.cx - h, d.cy - h], [d.cx + h, d.cy - h], [d.cx - h, d.cy + h], [d.cx + h, d.cy + h]]) {
        assert.ok(Math.hypot(x - 240, y - 240) < 232, "róg poza ekranem: n=" + n);
      }
      // nad napisem z sumą i przyciskiem
      assert.ok(d.cy + h <= 338 && d.cy - h >= 96, "kość wchodzi na napisy: n=" + n);
    }
    for (let i = 0; i < n; i++)
      for (let j = i + 1; j < n; j++) {
        const a = l[i], b = l[j];
        const apart = Math.abs(a.cx - b.cx) >= (a.size + b.size) / 2 || Math.abs(a.cy - b.cy) >= (a.size + b.size) / 2;
        assert.ok(apart, "kości się nakładają: n=" + n);
      }
  }
});

test("potrząśnięcie: kilka mocnych ruchów = jeden rzut, spokój nie rzuca", () => {
  const d = createShakeDetector();
  const still = { x: 0, y: 0, z: 980 };
  const jolt = { x: 1500, y: 600, z: 980 };
  let t = 1000;
  for (let i = 0; i < 50; i++) assert.equal(d.feed(still, (t += 40)), false);
  // pojedyncze szarpnięcie (np. podniesienie ręki) - nic
  assert.equal(d.feed(jolt, (t += 40)), false);
  for (let i = 0; i < 20; i++) assert.equal(d.feed(still, (t += 40)), false);
  // prawdziwe potrząsanie
  const hits = [];
  for (let i = 0; i < 30; i++) hits.push(d.feed(i % 2 ? jolt : { x: -1400, y: 0, z: 200 }, (t += 40)));
  assert.equal(hits.filter(Boolean).length, 1, "potrząsanie przez 1,2 s = jeden rzut");
  // po przerwie można znowu
  t += 2000;
  let again = false;
  for (let i = 0; i < 6; i++) again = d.feed(jolt, (t += 40)) || again;
  assert.equal(again, true);
  // quiet() blokuje
  d.quiet(t, 1000);
  for (let i = 0; i < 6; i++) assert.equal(d.feed(jolt, (t += 40)), false);
  assert.equal(d.feed(null, t), false);
});

if (failed) {
  console.error(failed + " test(y) nie przeszły");
  process.exit(1);
}
console.log("dice: WSZYSTKIE TESTY OK");
