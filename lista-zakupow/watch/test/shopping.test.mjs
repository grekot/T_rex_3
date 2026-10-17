// `node test/shopping.test.mjs` - logika listy na zegarku: sortowanie, kolejka operacji offline, podpowiedzi
import assert from "node:assert/strict";
import {
  newId,
  compactItem,
  compactList,
  sortItems,
  counts,
  findList,
  normalizeName,
  cleanName,
  toggleOp,
  addItemOp,
  delItemOp,
  addListOp,
  delListOp,
  leaveListOp,
  removeListOp,
  isOwn,
  isShared,
  queueOp,
  removeApplied,
  applyOps,
  planAdd,
  suggestions,
  rememberName,
  listNameSuggestions,
} from "../utils/shopping.js";

// deterministyczne "losowanie" do testów
function seq() {
  let n = 0;
  return () => ((n++ * 7) % 62) / 62;
}

// identyfikatory
const id = newId();
assert.match(id, /^[A-Za-z0-9]{20}$/);
assert.notEqual(newId(), newId());

// format kompaktowy
assert.deepEqual(compactItem({ id: "I1", name: "Mleko", checked: true, createdAt: 10, checkedAt: 20 }), {
  id: "I1",
  n: "Mleko",
  c: 1,
  t: 10,
  k: 20,
});
assert.deepEqual(compactItem({ id: "I2", name: "Chleb", checked: false, createdAt: null, checkedAt: null }), {
  id: "I2",
  n: "Chleb",
  c: 0,
  t: 0,
  k: 0,
});
assert.equal(compactList({ id: "L1", name: "Biedronka" }, [{ id: "I1", name: "x", checked: false }]).items.length, 1);

// własność i współdzielenie
const mine = compactList({ id: "L1", name: "A", ownerId: "me", members: ["me", "zona"] }, [], "me");
const theirs = compactList({ id: "L2", name: "B", ownerId: "zona", members: ["zona", "me"] }, [], "me");
assert.equal(mine.o, 1);
assert.equal(mine.s, 2);
assert.equal(theirs.o, 0);
assert.equal(isOwn(mine), true);
assert.equal(isOwn(theirs), false);
assert.equal(isOwn({ id: "stara" }), true, "dane bez pola o - traktujemy jak własne");
assert.equal(isShared(mine), true);
assert.equal(isShared(compactList({ id: "L3", name: "C", ownerId: "me", members: ["me"] }, [], "me")), false);
assert.equal(removeListOp(mine, 1).t, "delList");
assert.equal(removeListOp(theirs, 1).t, "leaveList");
assert.equal(leaveListOp("L2", 1).l, "L2");

// sortowanie i liczniki
const items = [
  { id: "chleb", n: "Chleb", c: 0, t: 2, k: 0 },
  { id: "mleko", n: "Mleko", c: 1, t: 1, k: 5 },
  { id: "maslo", n: "Masło", c: 0, t: 1, k: 0 },
  { id: "jajka", n: "Jajka", c: 1, t: 3, k: 9 },
  { id: "nowy", n: "Nowy", c: 0, t: 0, k: 0 },
];
assert.deepEqual(sortItems(items).map((i) => i.id), ["maslo", "chleb", "nowy", "jajka", "mleko"]);
assert.deepEqual(counts({ items }), { total: 5, done: 2, todo: 3 });
assert.deepEqual(counts({ items: [] }), { total: 0, done: 0, todo: 0 });

assert.equal(normalizeName("  Mleko   2% "), "mleko 2%");
assert.equal(cleanName("  Mleko   2% "), "Mleko 2%");
assert.equal(cleanName("x".repeat(150)).length, 100);

// tworzenie operacji
const rnd = seq();
const t1 = toggleOp("L1", { id: "I1", c: 0 }, 100, rnd);
assert.equal(t1.t, "toggle");
assert.equal(t1.c, 1);
assert.equal(toggleOp("L1", { id: "I1", c: 1 }, 100, rnd).c, 0);
const a1 = addItemOp("L1", "  Ser  żółty ", 110, rnd);
assert.equal(a1.t, "addItem");
assert.equal(a1.n, "Ser żółty");
assert.match(a1.i, /^[A-Za-z0-9]{20}$/);
const nl = addListOp(" Lidl ", 120, rnd);
assert.equal(nl.t, "addList");
assert.equal(nl.n, "Lidl");
assert.equal(delItemOp("L1", "I1", 130, rnd).t, "delItem");
assert.equal(delListOp("L1", 140, rnd).t, "delList");

// kolejka: nowsze odhaczenie zastępuje starsze; usunięcie kasuje odhaczenia tego produktu
const op = (o) => ({ id: o.id, t: o.t, l: o.l || "L1", i: o.i, c: o.c, n: o.n, at: o.at || 1 });
let q = queueOp([], op({ id: "o1", t: "toggle", i: "I1", c: 1 }));
q = queueOp(q, op({ id: "o2", t: "toggle", i: "I2", c: 1 }));
q = queueOp(q, op({ id: "o3", t: "toggle", i: "I1", c: 0 }));
assert.deepEqual(q.map((p) => p.id), ["o2", "o3"]);
q = queueOp(q, op({ id: "o4", t: "delItem", i: "I1" }));
assert.deepEqual(q.map((p) => p.id), ["o2", "o4"]);
q = queueOp(q, op({ id: "o5", t: "addItem", i: "I9", n: "Ser" }));
q = queueOp(q, op({ id: "o6", t: "delItem", i: "I9" }));
assert.deepEqual(q.map((p) => p.id), ["o2", "o4", "o5", "o6"], "dodanie zostaje - mogło być już w drodze");
q = queueOp(q, op({ id: "o7", t: "delList" }));
assert.deepEqual(q.map((p) => p.id), ["o4", "o5", "o6", "o7"], "odhaczenia usuwanej listy są zbędne");

assert.deepEqual(removeApplied(q, ["o4", "o5"]).map((p) => p.id), ["o6", "o7"]);
assert.deepEqual(removeApplied(q, undefined), q);

// nakładanie kolejki na dane z telefonu
const lists = [
  {
    id: "L1",
    name: "Biedronka",
    items: [
      { id: "I1", n: "Mleko", c: 1, t: 1, k: 50 },
      { id: "I2", n: "Chleb", c: 0, t: 2, k: 0 },
    ],
  },
  { id: "L2", name: "Apteka", items: [{ id: "I1", n: "Witaminy", c: 0, t: 1, k: 0 }] },
];
const view = applyOps(lists, [
  op({ id: "x1", t: "toggle", i: "I1", c: 0, at: 200 }),
  op({ id: "x2", t: "toggle", i: "I2", c: 1, at: 210 }),
  op({ id: "x3", t: "addItem", i: "I3", n: "Ser", at: 220 }),
  op({ id: "x4", t: "addList", l: "L3", n: "Lidl", at: 230 }),
  op({ id: "x5", t: "addItem", l: "L3", i: "I4", n: "Jabłka", at: 240 }),
  op({ id: "x6", t: "delList", l: "L2", at: 250 }),
]);
assert.deepEqual(view.map((l) => l.id), ["L1", "L3"]);
assert.deepEqual(view[0].items.map((i) => [i.id, i.c]), [["I1", 0], ["I2", 1], ["I3", 0]]);
assert.equal(view[0].items[1].k, 210);
assert.equal(view[0].items[2].t, 220);
assert.deepEqual(view[1], { id: "L3", name: "Lidl", o: 1, s: 1, items: [{ id: "I4", n: "Jabłka", c: 0, t: 240, k: 0 }] });
assert.deepEqual(
  applyOps(lists, [op({ id: "lv", t: "leaveList", l: "L2" })]).map((l) => l.id),
  ["L1"],
  "opuszczona lista znika od razu"
);
assert.deepEqual(
  queueOp([op({ id: "t1", t: "toggle", l: "L2", i: "I1", c: 1 })], op({ id: "lv", t: "leaveList", l: "L2" })).map((p) => p.id),
  ["lv"],
  "odhaczenia na opuszczanej liście są zbędne"
);
assert.equal(lists[0].items[0].c, 1, "dane wejściowe nie są modyfikowane");
assert.equal(lists.length, 2);
assert.deepEqual(
  applyOps(lists, [op({ id: "y1", t: "delItem", i: "I2" })])[0].items.map((i) => i.id),
  ["I1"]
);
assert.equal(applyOps(lists, []), lists);
assert.equal(applyOps(lists, [op({ id: "z", t: "addItem", l: "NIE", i: "Q", n: "x" })]).length, 2, "lista nie istnieje - pomijamy");

// planowanie dodania z zegarka
assert.deepEqual(planAdd(lists[0], " chleb "), { action: "exists", item: lists[0].items[1] });
assert.deepEqual(planAdd(lists[0], "MLEKO"), { action: "uncheck", item: lists[0].items[0] });
assert.deepEqual(planAdd(lists[0], "Ser"), { action: "add" });
assert.deepEqual(planAdd(lists[0], "   "), { action: "empty" });

// podpowiedzi: częstsze wyżej, bez produktów czekających na tej liście
const many = [
  { id: "A", name: "A", items: [{ id: "1", n: "Mleko", c: 1 }, { id: "2", n: "Chleb", c: 0 }] },
  { id: "B", name: "B", items: [{ id: "3", n: "mleko", c: 0 }, { id: "4", n: "Masło", c: 1 }] },
];
assert.deepEqual(suggestions(many, "A", ["Ser", "chleb"]), ["Mleko", "Masło", "Ser"]);
assert.deepEqual(suggestions(many, "B", []), ["Masło", "Chleb"], "produkty z tej samej listy mają wyższą wagę");
assert.ok(!suggestions(many, "B", []).some((n) => normalizeName(n) === "mleko"), "mleko czeka na liście B");
assert.equal(suggestions(many, "A", [], 1).length, 1);

assert.deepEqual(rememberName(["Ser", "Mleko"], " mleko "), ["mleko", "Ser"]);
assert.deepEqual(rememberName(["Ser"], "  "), ["Ser"]);
assert.equal(rememberName(new Array(60).fill(0).map((_, i) => "p" + i), "nowy").length, 50);

assert.ok(!listNameSuggestions([{ name: "biedronka" }]).includes("Biedronka"));
assert.ok(listNameSuggestions([]).includes("Lidl"));

assert.equal(findList(lists, "L2").name, "Apteka");
assert.equal(findList(lists, "nie-ma"), null);

console.log("shopping: WSZYSTKIE TESTY OK");
