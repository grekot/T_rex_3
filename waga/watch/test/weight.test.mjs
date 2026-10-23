import assert from "node:assert/strict";
import {
  MIN_W,
  MAX_W,
  DEFAULT_W,
  clampW,
  stepW,
  formatKg,
  formatDelta,
  addDays,
  daysBetween,
  shortDate,
  emptyData,
  normalize,
  upsert,
  entryFor,
  lastBefore,
  startValue,
  series,
  average,
  changeInfo,
  barHeights,
  repeatDelay,
  historyRows,
  periodChange,
} from "../utils/weight.js";

let failed = 0;
function test(name, fn) {
  try {
    fn();
  } catch (e) {
    failed++;
    console.error("BŁĄD: " + name + "\n  " + e.message);
  }
}

test("formatowanie kilogramów i różnic", () => {
  assert.equal(formatKg(823), "82,3");
  assert.equal(formatKg(1000), "100,0");
  assert.equal(formatKg(305), "30,5");
  assert.equal(formatDelta(3), "+0,3");
  assert.equal(formatDelta(-14), "−1,4");
  assert.equal(formatDelta(0), "±0,0");
});

test("krok o 0,1 kg bez błędów zaokrągleń i w granicach", () => {
  let w = 800;
  for (let i = 0; i < 7; i++) w = stepW(w, 1);
  assert.equal(w, 807);
  assert.equal(formatKg(w), "80,7");
  assert.equal(stepW(MIN_W, -1), MIN_W);
  assert.equal(stepW(MAX_W, 1), MAX_W);
  assert.equal(clampW(812.4), 812);
});

test("daty: dodawanie dni przez koniec miesiąca, roku i zmianę czasu", () => {
  assert.equal(addDays("2026-10-31", 1), "2026-11-01");
  assert.equal(addDays("2026-01-01", -1), "2025-12-31");
  assert.equal(addDays("2026-10-25", 1), "2026-10-26");
  assert.equal(addDays("2028-02-28", 1), "2028-02-29");
  assert.equal(daysBetween("2026-10-20", "2026-10-23"), 3);
  assert.equal(shortDate("2026-10-23"), "pt 23.10");
  assert.equal(shortDate("2026-10-25"), "nd 25.10");
});

test("normalize: złe wpisy odpadają, duplikat dnia - wygrywa późniejszy zapis, sortowanie", () => {
  const d = normalize({
    e: [
      { d: "2026-10-22", w: 830, t: 5 },
      { d: "2026-10-20", w: 835, t: 1 },
      { d: "2026-10-22", w: 828, t: 9 },
      { d: "zly", w: 800, t: 1 },
      { d: "2026-10-21", w: 10, t: 1 },
      { d: "2026-10-21", w: "800", t: 1 },
      null,
    ],
  });
  assert.deepEqual(d, {
    v: 1,
    e: [
      { d: "2026-10-20", w: 835, t: 1 },
      { d: "2026-10-22", w: 828, t: 9 },
    ],
  });
  assert.deepEqual(normalize(null), emptyData());
  assert.deepEqual(normalize("śmieci"), emptyData());
});

test("upsert: jeden pomiar na dzień, kolejność zachowana", () => {
  let d = emptyData();
  d = upsert(d, "2026-10-23", 823, 100);
  d = upsert(d, "2026-10-21", 830, 50);
  d = upsert(d, "2026-10-23", 821, 200);
  assert.deepEqual(
    d.e.map((x) => x.d + ":" + x.w),
    ["2026-10-21:830", "2026-10-23:821"],
  );
  assert.equal(entryFor(d, "2026-10-23").t, 200);
  assert.equal(entryFor(d, "2026-10-22"), null);
});

test("start ekranu: dzisiejszy zapis > ostatni pomiar > 80,0", () => {
  assert.equal(startValue(emptyData(), "2026-10-23"), DEFAULT_W);
  let d = upsert(emptyData(), "2026-10-20", 845, 1);
  assert.equal(startValue(d, "2026-10-23"), 845);
  d = upsert(d, "2026-10-23", 840, 2);
  assert.equal(startValue(d, "2026-10-23"), 840);
  assert.equal(lastBefore(d, "2026-10-23").w, 845);
});

test("seria do wykresu: braki jako null, dzisiaj = bieżąca (niezapisana) wartość", () => {
  let d = emptyData();
  d = upsert(d, "2026-10-20", 830, 1);
  d = upsert(d, "2026-10-22", 826, 1);
  d = upsert(d, "2026-10-23", 825, 1);
  assert.deepEqual(series(d, "2026-10-23", 5), [null, 830, null, 826, 825]);
  assert.deepEqual(series(d, "2026-10-23", 5, 822), [null, 830, null, 826, 822]);
  assert.equal(average([null, 830, null, 826, 822]), 826);
  assert.equal(average([null, null]), null);
});

test("zmiana: od wczoraj albo od daty poprzedniego pomiaru", () => {
  let d = upsert(emptyData(), "2026-10-22", 830, 1);
  assert.deepEqual(changeInfo(d, "2026-10-23", 826), { text: "−0,4 kg od wczoraj", sign: -1 });
  d = upsert(emptyData(), "2026-10-19", 830, 1);
  assert.deepEqual(changeInfo(d, "2026-10-23", 832), { text: "+0,2 kg od pn 19.10", sign: 1 });
  assert.deepEqual(changeInfo(d, "2026-10-23", 830).sign, 0);
  assert.equal(changeInfo(emptyData(), "2026-10-23", 800), null);
});

test("słupki: minimalny zakres, null dla braków", () => {
  const h = barHeights([800, null, 801, 830], 50, 6, 20);
  assert.equal(h[1], null);
  assert.ok(h[0] < h[2] && h[2] < h[3]);
  assert.equal(h[3], 50);
  assert.equal(h[0], 6);
  // prawie płasko: różnica 0,1 kg to mały, nie pełny skok
  const flat = barHeights([800, 801], 50, 6, 20);
  assert.ok(flat[1] - flat[0] < 5);
  assert.deepEqual(barHeights([null, null], 50, 6, 20), [null, null]);
});

test("historia: od najnowszego, różnica do poprzedniego pomiaru, limit; zmiana w okresie", () => {
  let d = emptyData();
  d = upsert(d, "2026-09-01", 850, 1);
  d = upsert(d, "2026-10-20", 835, 1);
  d = upsert(d, "2026-10-22", 830, 1);
  d = upsert(d, "2026-10-23", 832, 1);
  assert.deepEqual(historyRows(d, 3), [
    { d: "2026-10-23", w: 832, delta: 2 },
    { d: "2026-10-22", w: 830, delta: -5 },
    { d: "2026-10-20", w: 835, delta: -15 },
  ]);
  assert.equal(historyRows(d, 10)[3].delta, null);
  assert.equal(periodChange(d, "2026-10-23", 7), -3);
  assert.equal(periodChange(d, "2026-10-23", 60), -18);
  assert.equal(periodChange(d, "2026-10-23", 1), null);
});

test("przytrzymanie:najpierw pauza, potem coraz szybciej", () => {
  assert.ok(repeatDelay(1) > repeatDelay(2));
  assert.ok(repeatDelay(5) > repeatDelay(20));
});

if (failed) {
  console.error(failed + " test(y) nie przeszły");
  process.exit(1);
}
console.log("weight: WSZYSTKIE TESTY OK");
