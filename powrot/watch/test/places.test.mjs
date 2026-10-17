// `node test/places.test.mjs` - miejsca: dane z Firebase + kolejka operacji offline
import assert from "node:assert/strict";
import {
  compactPlace,
  isOwn,
  sortPlaces,
  applyOps,
  removeApplied,
  removeOp,
  savePlaceOps,
  migrateOldPoints,
  findPlace,
} from "../utils/places.js";

// dokument z Firestore -> format zegarka
const mine = compactPlace(
  { id: "P1", name: "Auto", lat: 52.1, lon: 21.0, savedAt: 1000, ownerId: "me", members: ["me", "zona"], memberEmails: { me: "ja@x.pl" } },
  "me"
);
assert.deepEqual(mine, { id: "P1", name: "Auto", lat: 52.1, lon: 21.0, at: 1000, o: 1, s: 2, by: "ja@x.pl" });
const theirs = compactPlace(
  { id: "P2", name: "Namiot", lat: 50, lon: 19, createdAt: 2000, ownerId: "zona", members: ["zona", "me"], memberEmails: { zona: "zona@x.pl" } },
  "me"
);
assert.equal(theirs.o, 0);
assert.equal(theirs.at, 2000, "bez savedAt - data utworzenia");
assert.equal(theirs.by, "zona@x.pl");
assert.equal(isOwn(mine), true);
assert.equal(isOwn(theirs), false);
assert.equal(isOwn({ id: "x" }), true, "bez pola o - własne (dane lokalne)");

assert.deepEqual(sortPlaces([mine, theirs]).map((p) => p.id), ["P2", "P1"], "najnowsze na górze");

// kolejka: zapis nowego "Auto" zastępuje moje stare "Auto", ale nie cudze
let n = 0;
const rnd = () => ((n++ * 7) % 62) / 62;
const server = [mine, theirs, { ...theirs, id: "P3", name: "auto", o: 0 }];
const ops = savePlaceOps(server, " auto ", 52.2, 21.1, 3000, rnd);
assert.deepEqual(ops.map((o) => o.t), ["delPlace", "addPlace"]);
assert.equal(ops[0].pid, "P1");
assert.equal(ops[1].p.name, "auto");
assert.equal(ops[1].p.lat, 52.2);
let view = applyOps(server, ops);
assert.deepEqual(view.map((p) => p.name).sort(), ["Namiot", "auto", "auto"]);
assert.equal(view[0].at, 3000, "nowe na górze");
assert.equal(findPlace(view, "P1"), null, "stare Auto zniknęło");
assert.ok(findPlace(view, "P3"), "cudze 'auto' zostaje");

// bez nazwy -> "Punkt N"
const noName = savePlaceOps([], "  ", 1, 2, 10, rnd);
assert.deepEqual(noName.map((o) => o.t), ["addPlace"]);
assert.equal(noName[0].p.name, "Punkt 1");

// usuwanie: własne kasujemy, z cudzego się wypisujemy
assert.equal(removeOp(mine, 1, rnd).t, "delPlace");
assert.equal(removeOp(theirs, 1, rnd).t, "leavePlace");
view = applyOps(server, [removeOp(theirs, 1, rnd)]);
assert.equal(findPlace(view, "P2"), null);

// potwierdzenie z telefonu
const q = [{ id: "a" }, { id: "b" }, { id: "c" }];
assert.deepEqual(removeApplied(q, ["a", "c"]).map((o) => o.id), ["b"]);
assert.deepEqual(removeApplied(q, undefined), q);

// migracja z wersji 1.0 (punkty tylko na zegarku)
const migrated = migrateOldPoints(
  [{ id: "abc", name: "Auto", lat: 52, lon: 21, at: 5 }, { name: "zepsuty", lat: NaN, lon: 1 }],
  99,
  rnd
);
assert.equal(migrated.length, 1);
assert.deepEqual(migrated[0].p, { id: "abc", name: "Auto", lat: 52, lon: 21, at: 5 });
assert.deepEqual(migrateOldPoints(undefined, 1), []);

console.log("places: WSZYSTKIE TESTY OK");
