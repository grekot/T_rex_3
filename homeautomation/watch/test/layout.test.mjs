// `node test/layout.test.mjs` - kafelki pulpitu zegarka w wierszach na okrągłym i kwadratowym ekranie (API.md pkt 13a)
import assert from "node:assert/strict";
import { rowsOf, layoutPages, GEOMETRY } from "../utils/layout.js";

const T = (id, size) => ({ key: id, size });
const ROUND = { width: 480, height: 480, shape: "round" };
const SQUARE = { width: 390, height: 450, shape: "square" };

// --- wiersze ---
const sizes = (rows) => rows.map((r) => r.size + ":" + r.items.map((i) => i.key).join(","));
assert.deepEqual(sizes(rowsOf([T("a", "half"), T("b", "half"), T("c", "full"), T("d", "big")])), ["half:a,b", "full:c", "big:d"]);
assert.deepEqual(sizes(rowsOf([T("a", "half"), T("b", "full"), T("c", "half"), T("d", "half"), T("e", "half")])), ["half:a", "full:b", "half:c,d", "half:e"], "half bez pary zostaje sam");
assert.deepEqual(sizes(rowsOf([T("a"), T("b", "ogromny")])), ["full:a", "full:b"], "brak / nieznany rozmiar = full");
assert.deepEqual(rowsOf([]), []);
assert.deepEqual(rowsOf(null), []);

// --- jedna krótka strona na okrągłym ekranie: wszystko mieści się bez przewijania ---
const one = layoutPages([{ title: "Dom", items: [T("a", "half"), T("b", "half"), T("c", "full")] }], ROUND);
const header = one.blocks[0];
assert.equal(header.type, "header");
assert.equal(header.text, "Dom");
assert.equal(header.y, GEOMETRY.top);
const [a, b, c] = one.blocks.slice(1);
assert.equal(a.y, GEOMETRY.top + GEOMETRY.header);
assert.equal(b.y, a.y, "dwa half w jednym wierszu");
assert.equal(a.w, b.w);
assert.equal(b.x - (a.x + a.w), GEOMETRY.gap);
assert.equal(c.y, a.y + GEOMETRY.row + GEOMETRY.gap);
assert.equal(c.size, "full");
// wiersze symetryczne względem środka ekranu
const mid = (x0, x1) => Math.abs((x0 + x1) / 2 - 240) <= 1;
assert.ok(mid(header.x, header.x + header.w) && mid(c.x, c.x + c.w) && mid(a.x, b.x + b.w), "wyśrodkowane");
// w kole: każdy róg kafelka w środku koła
const inside = (x, y) => (x - 240) ** 2 + (y - 240) ** 2 <= 240 * 240;
for (const blk of one.blocks.filter((x) => x.type === "tile")) {
  for (const [x, y] of [
    [blk.x, blk.y],
    [blk.x + blk.w, blk.y],
    [blk.x, blk.y + blk.h],
    [blk.x + blk.w, blk.y + blk.h],
  ]) {
    assert.ok(inside(x, y), "róg poza kołem: " + JSON.stringify(blk));
  }
}
assert.equal(one.height, c.y + GEOMETRY.row + GEOMETRY.gap + GEOMETRY.bottom);

// --- długa treść: na górze i na dole węższe, w środku (da się przewinąć na środek ekranu) szersze ---
const items = [];
for (let i = 0; i < 9; i++) items.push(T("f" + i, "full"));
const long = layoutPages([{ title: "", items }], ROUND);
const tiles = long.blocks.filter((x) => x.type === "tile");
assert.equal(long.blocks[0].type, "tile", "bez tytułu strony bez nagłówka");
const first = tiles[0];
const middle = tiles[4];
const last = tiles[8];
assert.ok(first.w < middle.w, "górny węższy: " + first.w + " < " + middle.w);
assert.equal(middle.w, GEOMETRY.maxWidth, "w środku pełna szerokość");
assert.ok(last.w <= middle.w);
assert.ok(first.w >= GEOMETRY.minWidth);

// --- big: podwójna wysokość; pojedynczy half na środku ---
const big = layoutPages([{ title: "X", items: [T("t", "big"), T("h", "half")] }], ROUND);
const [, bigTile, lone] = big.blocks;
assert.equal(bigTile.h, GEOMETRY.big);
assert.equal(lone.y, bigTile.y + GEOMETRY.big + GEOMETRY.gap);
assert.ok(Math.abs(lone.x + lone.w / 2 - 240) <= 1, "pojedynczy half wyśrodkowany");

// --- kilka stron jedna pod drugą; puste strony pominięte ---
const pages = layoutPages(
  [
    { title: "Salon", items: [T("a", "full")] },
    { title: "Pusta", items: [] },
    { title: "Kuchnia", items: [T("b", "full")] },
  ],
  ROUND
);
assert.deepEqual(
  pages.blocks.map((x) => (x.type === "header" ? "#" + x.text : x.item.key)),
  ["#Salon", "a", "#Kuchnia", "b"]
);

// --- kwadratowy ekran: stała szerokość ---
const sq = layoutPages([{ title: "", items: [T("a", "full"), T("b", "half"), T("c", "half")] }], SQUARE);
assert.equal(sq.blocks[0].w, Math.min(GEOMETRY.maxWidth, 390 - 2 * GEOMETRY.margin));
assert.equal(sq.blocks[1].w, Math.floor((sq.blocks[0].w - GEOMETRY.gap) / 2));

// --- inna skala (px na mniejszym ekranie) ---
const small = layoutPages([{ title: "", items: [T("a", "full")] }], { width: 416, height: 416, shape: "round" }, { top: 80, row: 76 });
assert.equal(small.blocks[0].y, 80);
assert.equal(small.blocks[0].h, 76);

assert.deepEqual(layoutPages([], ROUND), { blocks: [], height: GEOMETRY.top + GEOMETRY.bottom });

console.log("layout.test.mjs: OK");
