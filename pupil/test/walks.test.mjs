import assert from "node:assert/strict";
import {
  normalize,
  angleDiff,
  distance,
  bearing,
  destination,
  dirName,
  FORAGE,
  newForage,
  forageStep,
  pulseEvery,
  CLIMB,
  newClimb,
  climbStatus,
  DIVE,
  newDive,
  feedDive,
  TRIP,
  newTrip,
  tripStatus,
  MARKS,
  marksStatus,
  addMark,
} from "../utils/walks.js";

let failed = 0;
function test(name, fn) {
  try {
    fn();
  } catch (e) {
    failed++;
    console.error("BŁĄD: " + name + "\n  " + e.message);
  }
}

const KRK = { lat: 50.0614, lon: 19.9366 };
const H = 3600000;

test("geometria: kąty, odległość, kierunek, punkt docelowy", () => {
  assert.equal(normalize(-90), 270);
  assert.equal(angleDiff(10, 350), 20);
  assert.equal(angleDiff(350, 10), -20);
  const p = destination(KRK.lat, KRK.lon, 45, 300);
  assert.ok(Math.abs(distance(KRK.lat, KRK.lon, p.lat, p.lon) - 300) < 0.5);
  assert.ok(Math.abs(bearing(KRK.lat, KRK.lon, p.lat, p.lon) - 45) < 0.5);
  assert.equal(dirName(44), "północny wschód");
  assert.equal(dirName(359), "północ");
});

test("szukanie jedzenia: trzymanie kierunku przez chwilę znajduje jedzenie", () => {
  const g = newForage(3);
  for (let i = 1; i < g.targets.length; i++) assert.ok(Math.abs(angleDiff(g.targets[i], g.targets[i - 1])) >= 60);
  let found = 0;
  for (let t = 0; !g.done; t += 100) {
    const target = g.targets[g.found];
    const heading = t % 4000 < 1500 ? target + 90 : target + 5; // najpierw szuka, potem trafia
    if (forageStep(g, heading, 100) === "found") found++;
  }
  assert.equal(g.win, true);
  assert.equal(found, FORAGE.foods);
  assert.ok(pulseEvery(0) < pulseEvery(90));
  assert.equal(pulseEvery(null), 0);
  const blind = newForage(4);
  for (let t = 0; !blind.done; t += 100) forageStep(blind, null, 100);
  assert.equal(blind.win, false);
});

test("wspinaczka: 3 m w górę w ciągu kilku godzin", () => {
  const task = newClimb(220.4, 0);
  assert.equal(climbStatus(task, 221.5, H).state, "climbing");
  assert.equal(climbStatus(task, 221.5, H).gain, 1.1);
  assert.equal(climbStatus(task, 223.5, H).state, "done");
  assert.equal(climbStatus(task, null, H).state, "wait");
  assert.equal(climbStatus(task, 230, CLIMB.ttl + 1).state, "expired");
  assert.equal(climbStatus(null, 230, 0).state, "none");
});

test("nurkowanie: szybkie opuszczenie i podniesienie ręki", () => {
  const g = newDive();
  let t = 0;
  const alt = (dt) => {
    // co 4 s nurek: przez 1,2 s wysokość niższa o 0,8 m; szum ±0,1 m
    const phase = t % 4000;
    return 200 + (phase > 1000 && phase < 2200 ? -0.8 : 0) + Math.sin(t / 97) * 0.1;
  };
  while (!g.done) {
    feedDive(g, alt(), t, 100);
    t += 100;
  }
  assert.equal(g.win, true, "nurków " + g.dives);
  // powolne opadanie (pogoda) nie liczy się jako nurek
  const w = newDive();
  for (t = 0; !w.done; t += 100) feedDive(w, 200 - t / 60000, t, 100);
  assert.equal(w.dives, 0);
  assert.equal(w.win, false);
});

test("wyprawa: punkt 200-500 m, dotarcie do 25 m", () => {
  for (let seed = 1; seed <= 20; seed++) {
    const task = newTrip(KRK, 0, seed);
    const d = distance(KRK.lat, KRK.lon, task.lat, task.lon);
    assert.ok(d >= TRIP.min - 1 && d <= TRIP.max + 1, String(d));
    const st = tripStatus(task, KRK, 1000);
    assert.equal(st.state, "walking");
    assert.ok(Math.abs(st.dist - task.dist) <= 1);
    const near = destination(task.lat, task.lon, 0, 10);
    assert.equal(tripStatus(task, near, 1000).state, "done");
  }
  const task = newTrip(KRK, 0, 1);
  assert.equal(tripStatus(task, null, 10).state, "wait");
  assert.equal(tripStatus(task, KRK, TRIP.ttl + 1).state, "expired");
});

test("znaczenie terenu: 3 miejsca co najmniej 100 m od siebie", () => {
  let r = addMark(null, KRK, 0);
  assert.equal(r.result, "added");
  r = addMark(r.task, destination(KRK.lat, KRK.lon, 90, 50), 1000);
  assert.equal(r.result, "near");
  assert.equal(r.nearest, 50);
  r = addMark(r.task, destination(KRK.lat, KRK.lon, 90, 150), 2000);
  assert.equal(r.result, "added");
  assert.deepEqual(marksStatus(r.task, 2000), { state: "marking", count: 2 });
  r = addMark(r.task, destination(KRK.lat, KRK.lon, 200, 150), 3000);
  assert.equal(r.result, "done");
  assert.equal(marksStatus(r.task, 3000).state, "done");
  // po dobie zaczyna się od nowa
  assert.equal(marksStatus(r.task, MARKS.ttl + 1).state, "none");
  assert.equal(addMark(r.task, KRK, MARKS.ttl + 1).task.list.length, 1);
});

if (failed) {
  console.error(failed + " test(y) nie przeszły");
  process.exit(1);
}
console.log("walks: wszystkie testy przeszły");
