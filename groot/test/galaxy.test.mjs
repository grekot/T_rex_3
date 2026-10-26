import assert from "node:assert/strict";
import { MIN, HOUR, DAY, newEgg, advance, sceneOf, MAX_HEARTS, nextReminder, REQUEST } from "../utils/pet.js";
import { PLANETS, ENERGY, VISIT_MS, addSteps, tripInfo, visiting } from "../utils/galaxy.js";
import { rocketSays, GROOT, CHATTER, chatter, greeting, JOKES, PRAISE, INVITE_GAMES } from "../utils/rocket.js";
import { GAME_NAMES } from "../utils/gamelist.js";
import { DEFEND, newDefend, defendStep, defendTap, shipPos, MIX, newMix, mixPattern, beatTimes, judgeTaps, mixRound } from "../utils/space.js";

let failed = 0;
function test(name, fn) {
  try {
    fn();
  } catch (e) {
    failed++;
    console.error("BŁĄD: " + name + "\n  " + e.message);
  }
}

const T0 = Date.UTC(2026, 9, 21);
const at = (d, h, m = 0) => T0 + d * DAY + h * HOUR + m * MIN;
const TZ = 0;

// dziecko w dzień, wszystko w porządku
function child() {
  const s = advance(newEgg(at(0, 7, 50), 1), at(0, 8), TZ).state;
  return { ...s, form: "grocik", hunger: 1, happy: 4, poops: 0, sick: 0, whim: 0, request: null };
}

test("kroki: energia co 2000 kroków, najwyżej 3 dziennie, przyrost od ostatniego odczytu", () => {
  let s = child();
  let r = addSteps(s, 1999, at(0, 9), TZ);
  assert.equal(r.state.hunger, 1);
  r = addSteps(r.state, 4100, at(0, 12), TZ);
  assert.equal(r.state.hunger, 3);
  assert.equal(r.energy, 2);
  r = addSteps(r.state, 4100, at(0, 13), TZ); // ten sam odczyt - nic nowego
  assert.equal(r.state.hunger, 3);
  assert.equal(r.msgs.length, 0);
  r = addSteps(r.state, 20000, at(0, 18), TZ);
  assert.equal(r.state.trip.energy, ENERGY.maxPerDay);
  assert.equal(r.state.hunger, MAX_HEARTS);
  // nowy dzień: licznik od zera, energia znów dostępna
  const next = { ...r.state, hunger: 0 };
  r = addSteps(next, 2500, at(1, 10), TZ);
  assert.equal(r.state.trip.energy, 1);
  assert.equal(r.state.hunger, 1);
  assert.equal(r.state.trip.seen, 2500);
});

test("kroki: Milano leci po planetach, pocztówka i tło planety przez dobę", () => {
  let s = child();
  let r = addSteps(s, PLANETS[0].need - 1, at(0, 20), TZ);
  assert.equal(r.arrived.length, 0);
  r = addSteps(r.state, PLANETS[0].need + 10, at(0, 21), TZ);
  assert.deepEqual(r.arrived, ["xandar"]);
  assert.ok(r.msgs.some((m) => m.indexOf("Xandar") >= 0));
  const info = tripInfo(r.state);
  assert.equal(info.next.id, "contraxia");
  assert.equal(info.progress, 10);
  assert.deepEqual(info.visited, ["xandar"]);
  const s2 = { ...r.state, t: at(0, 22) };
  assert.equal(visiting(s2), "xandar");
  assert.equal(sceneOf(s2), "xandar");
  const later = { ...s2, t: at(0, 21) + VISIT_MS + MIN };
  assert.equal(visiting(later), null);
  assert.equal(sceneOf(later), "poklad");
});

test("kroki: cała podróż i od nowa; jajo i odejście nie liczą", () => {
  let s = child();
  let day = 0;
  const total = PLANETS.reduce((a, p) => a + p.need, 0);
  let left = total + 100;
  while (left > 0) {
    const today = Math.min(left, 30000);
    s = addSteps(s, today, at(day, 20), TZ).state;
    left -= today;
    day++;
  }
  assert.equal(s.trip.visited.length, PLANETS.length);
  assert.equal(s.trip.rounds, 1);
  assert.equal(s.trip.leg, 0);
  const egg = newEgg(at(0, 10), 5);
  assert.equal(addSteps(egg, 9000, at(0, 11), TZ).state.trip, undefined);
  assert.equal(addSteps({ ...child(), gone: "forest" }, 9000, at(0, 11), TZ).msgs.length, 0);
});

test("Rocket tłumaczy: potrzeby przed gadaniem, gadanie według etapu", () => {
  const c = child();
  assert.equal(GROOT, "Jestem Groot.");
  assert.equal(rocketSays({ ...c, hunger: 0 }, TZ), "Rocket: brakuje mu słońca");
  assert.equal(rocketSays({ ...c, form: "kielek", hunger: 0 }, TZ), "Rocket: mówi, że chce pić");
  assert.equal(rocketSays({ ...c, sick: 1 }, TZ), "Rocket: swędzi go kora. Mszyce");
  assert.equal(rocketSays({ ...c, asleep: true }, TZ), "Rocket: śpi, nie budź go");
  assert.equal(rocketSays({ ...c, form: "nastek" }, TZ, () => 0), CHATTER.teen[0]);
  assert.equal(rocketSays({ ...c, form: "groot" }, TZ, () => 1), CHATTER.adult[1]);
  for (const k in CHATTER) CHATTER[k].forEach((t) => assert.ok(t.length <= 40, t));
});

test("Obrona Milano: statki lecą do środka, stuknięcie zestrzeliwuje, 12 = wygrana", () => {
  const g = newDefend(3);
  let spawned = 0;
  for (let i = 0; i < 40; i++) if (defendStep(g, 50).indexOf("spawn") >= 0) spawned++;
  assert.equal(spawned, 1);
  const sh = g.ships[0];
  const p = shipPos(sh);
  assert.ok(Math.hypot(p.x - 240, p.y - 240) < DEFEND.r0);
  assert.equal(defendTap(g, p.x + 100, p.y, undefined), false);
  assert.equal(defendTap(g, p.x + 10, p.y - 10), true);
  assert.equal(g.killed, 1);
  // gracz zestrzeliwuje każdy statek zaraz po pojawieniu się
  let t = 0;
  while (!g.done && t < 60000) {
    defendStep(g, 50);
    t += 50;
    g.ships.slice().forEach((s2) => defendTap(g, 0, 0, s2.id));
  }
  assert.equal(g.win, true);
  assert.equal(g.lives, DEFEND.lives);
});

test("Obrona Milano: bez stuknięć statki dolatują i gra jest przegrana", () => {
  const g = newDefend(9);
  let t = 0;
  let hits = 0;
  while (!g.done && t < 60000) {
    if (defendStep(g, 50).indexOf("hit") >= 0) hits++;
    t += 50;
  }
  assert.equal(g.win, false);
  assert.equal(g.lives, 0);
  assert.ok(hits >= 1);
  assert.ok(t < DEFEND.time + 100);
});

test("Awesome Mix: rytm z krótkich i długich, ocena proporcji niezależnie od tempa", () => {
  const g = newMix(4);
  const p = mixPattern(g);
  assert.equal(p.length, MIX.first - 1);
  assert.ok(p.indexOf(1) >= 0 && p.indexOf(2) >= 0);
  const times = beatTimes(p, 400);
  assert.equal(times.length, MIX.first);
  // to samo w innym tempie i z drobnymi odchyłkami = dobrze
  const slow = beatTimes(p, 520).map((x, i) => x + (i % 2 ? 40 : -30));
  assert.equal(judgeTaps(p, slow).ok, true);
  // za mało stuknięć
  assert.equal(judgeTaps(p, slow.slice(1)).why, "few");
  // wszystkie odstępy równe = zły rytm
  const flat = times.map((_, i) => i * 500);
  assert.equal(judgeTaps(p, flat).ok, false);
});

test("Awesome Mix: 2 trafione rundy z 3 = wygrana, 2 pudła = przegrana", () => {
  let g = newMix(1);
  mixPattern(g);
  mixRound(g, beatTimes(g.pattern, 450));
  assert.equal(g.done, false);
  mixPattern(g);
  assert.equal(g.pattern.length, MIX.first);
  mixRound(g, beatTimes(g.pattern, 380));
  assert.equal(g.done, true);
  assert.equal(g.win, true);
  g = newMix(2);
  mixPattern(g);
  mixRound(g, [0, 100]);
  mixPattern(g);
  mixRound(g, [0]);
  assert.equal(g.done, true);
  assert.equal(g.win, false);
});

// stały ciąg "losowych" liczb do testów
function seq(...xs) {
  let i = 0;
  return () => xs[i++ % xs.length];
}

test("zaczepki: zaproszenie do gry, dowcip w dwóch krokach, komplement, podróż, pora dnia", () => {
  const c = child(); // 8:00 rano
  const inv = chatter(c, TZ, seq(0.1, 0.0));
  assert.equal(inv.lines[0], GROOT);
  assert.equal(inv.invite, INVITE_GAMES[0]);
  assert.ok(inv.lines[1].indexOf(GAME_NAMES[INVITE_GAMES[0]]) >= 0, inv.lines[1]);
  const joke = chatter(c, TZ, seq(0.4, 0.0));
  assert.deepEqual(joke.lines, [GROOT, "Rocket: zna kawał. " + JOKES[0][0], JOKES[0][1]]);
  assert.equal(joke.invite, null);
  const praise = chatter(c, TZ, seq(0.6, 0.0));
  assert.equal(praise.lines[1], PRAISE[0]);
  const trip = { next: { name: "Contraxia", need: 8000 }, progress: 6000, visiting: null };
  assert.equal(chatter(c, TZ, seq(0.7), trip).lines[1], "Rocket: jeszcze 2000 kroków do Contraxia. Spacer?");
  assert.equal(chatter(c, TZ, seq(0.8)).lines[1], "Rocket: mówi dzień dobry! Rozgrzewka?");
  // wszystkie teksty mieszczą się w dwóch wierszach (ok. 52 znaki)
  JOKES.forEach((j) => assert.ok(("Rocket: zna kawał. " + j[0]).length <= 62 && j[1].length <= 40, j[0]));
  INVITE_GAMES.forEach((g) => assert.ok(GAME_NAMES[g], g));
});

test("zaczepki: gdy czegoś mu trzeba albo śpi - tylko o tym, bez zaproszeń i dowcipów", () => {
  const c = child();
  for (const x of [0.1, 0.4, 0.6, 0.9]) {
    const r = chatter({ ...c, hunger: 0 }, TZ, seq(x, 0));
    assert.deepEqual(r.lines, [GROOT, "Rocket: brakuje mu słońca"]);
    assert.equal(r.invite, null);
  }
  assert.deepEqual(chatter({ ...c, asleep: true }, TZ, seq(0.1)).lines, [GROOT, "Rocket: śpi, nie budź go"]);
  assert.deepEqual(chatter(newEgg(at(0, 10), 5), TZ, seq(0.1)).lines, []);
});

test("powitanie po przerwie; przypomnienie także o prośbie o zabawę", () => {
  const c = child();
  assert.deepEqual(greeting(c, 30 * MIN, TZ), []);
  assert.equal(greeting(c, 5 * HOUR, TZ)[1], "Rocket: cieszy się, że wróciłeś");
  assert.equal(greeting(c, 13 * HOUR, TZ)[1], "Rocket: tęsknił za tobą!");
  // potrzeba albo pora snu ważniejsze od powitania
  assert.deepEqual(greeting({ ...c, hunger: 0 }, 13 * HOUR, TZ), []);
  assert.deepEqual(greeting({ ...c, t: at(0, 20, 30) }, 13 * HOUR, TZ), []);
  // wszystko zrobione, prośba o grę przyjdzie za 60 min czuwania - alarm na tę chwilę
  const s = { ...c, t: at(0, 10), hunger: 4, happy: 4, timers: { ...c.timers, hunger: 9999, happy: 9999, poop: 9999, whim: 9999, ask: 60 } };
  const t = nextReminder(s, at(0, 10), TZ);
  assert.equal(t, at(0, 11));
  assert.ok(REQUEST.every <= 300);
});

if (failed) {
  console.error(failed + " test(y) nie przeszły");
  process.exit(1);
}
console.log("galaktyka, Rocket, gry kosmiczne: wszystkie testy przeszły");
