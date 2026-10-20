// `node test/photos.test.mjs` - lista zdjęć na zegarku i ścieżki dla IMG
import assert from "node:assert/strict";
import { mergePhoto, shownPhotos, haveIds, readParams } from "../utils/photos.js";
import { srcVariants, pickSrc } from "../utils/paths.js";

// Komunikat „wysłano” z telefonu może przyjść przed albo po odbiorze pliku na zegarku
let list = mergePhoto([], { id: "a", txMs: 4000, conv: undefined });
assert.deepEqual(list, [{ id: "a", txMs: 4000 }]);
assert.deepEqual(shownPhotos(list), []);
list = mergePhoto(list, { id: "a", fileName: "zd_a.png", rxMs: 3900, txMs: null });
assert.deepEqual(list, [{ id: "a", txMs: 4000, fileName: "zd_a.png", rxMs: 3900 }]);
list = mergePhoto(list, { id: "b", filePath: "data://download/zd_b.png" });
assert.deepEqual(haveIds(list), ["a", "b"]);

assert.deepEqual(readParams('{"id":"x"}'), { id: "x" });
assert.deepEqual(readParams("zepsute"), {});
assert.deepEqual(readParams(undefined), {});
assert.deepEqual(readParams({ id: "y" }), { id: "y" });

const v = srcVariants({ fileName: "zd_a.png", filePath: "data://download/zd_a.png" });
assert.deepEqual(v, ["data://download/zd_a.png", "download/zd_a.png", "/data/download/zd_a.png", "zd_a.png"]);
assert.equal(srcVariants({ name: "zd_b.png", filePath: "/x/zd_b.png" }).length, 5);
assert.equal(pickSrc({ fileName: "zd_a.png" }, 0), "data://download/zd_a.png");
assert.equal(pickSrc({ fileName: "zd_a.png" }, 5), "download/zd_a.png");
assert.equal(pickSrc({ fileName: "zd_a.png" }, -1), "zd_a.png");

console.log("photos OK");

// --- świeże zdjęcie wyskakuje pierwsze ---
import { freshPick, FRESH_MS } from "../utils/photos.js";

const now = 10 * FRESH_MS;
const listFresh = [
  { id: "stare", fileName: "a.png", rx: now - FRESH_MS - 1 },
  { id: "nowe1", fileName: "b.png", rx: now - 1000 },
  { id: "nowe2", fileName: "c.png", rx: now - 500 },
  { id: "bezpliku", rx: now },
];
assert.equal(freshPick(listFresh, [], now), "nowe2");
assert.equal(freshPick(listFresh, ["nowe2"], now), "nowe1");
assert.equal(freshPick(listFresh, ["nowe1", "nowe2"], now), "");

console.log("photos fresh OK");
