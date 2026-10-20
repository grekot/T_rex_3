// `node test/sync.test.mjs` - lista zdjęć z mostu lokalnego i wybór nowych do pobrania
import assert from "node:assert/strict";
import { parseManifest, photosToFetch, watchFileName, photoUrl, BRIDGE_URL } from "../utils/sync.js";

const body = JSON.stringify({
  version: 1,
  photos: [
    { id: "1001_1700000000", size: 412345, taken: 1700000000000 },
    { id: "zły/id", size: 1 },
    { id: "1002_1700000100", size: "300000", taken: 0 },
    null,
  ],
});

const photos = parseManifest(body);
assert.deepEqual(
  photos.map((p) => p.id),
  ["1001_1700000000", "1002_1700000100"]
);
assert.equal(photos[1].size, 300000);
assert.equal(parseManifest({ photos: [] }).length, 0);
assert.throws(() => parseManifest("{}"));
assert.throws(() => parseManifest("nie json"));

assert.deepEqual(
  photosToFetch(photos, ["1001_1700000000"]).map((p) => p.id),
  ["1002_1700000100"]
);
assert.equal(photosToFetch(photos, undefined).length, 2);

assert.equal(watchFileName("1001_1700000000"), "zd_1001_1700000000.png");
assert.equal(photoUrl("abc"), BRIDGE_URL + "/p/abc.png");
assert.equal(BRIDGE_URL, "http://127.0.0.1:8765");

console.log("sync OK");

// --- dociąganie po trochu i porządki ---
import { staleToDelete } from "../utils/sync.js";

const pool = parseManifest({
  photos: [
    { id: "n1", size: 1, caption: "Las" },
    { id: "n2", size: 1, caption: "x".repeat(60) },
    { id: "n3", size: 1 },
  ],
});
assert.equal(pool[0].caption, "Las");
assert.equal(pool[1].caption.length, 40);
assert.equal(pool[2].caption, "");
assert.deepEqual(photosToFetch(pool, ["n1"], 1).map((p) => p.id), ["n2"]);
assert.deepEqual(photosToFetch(pool, ["n1"], 0).map((p) => p.id), ["n2", "n3"]);

// Na zegarku 4 zdjęcia, w puli telefonu 3: kasujemy 1 najstarsze spoza puli
const onWatch = [
  { id: "stare1", rx: 100 },
  { id: "stare2", rx: 50 },
  { id: "n1", rx: 300 },
  { id: "n2", rx: 400 },
];
assert.deepEqual(staleToDelete(onWatch, ["n1", "n2", "n3"]), ["stare2"]);
// Nic nie przybyło ponad wielkość puli - nic nie znika
assert.deepEqual(staleToDelete(onWatch.slice(0, 3), ["n1", "n2", "n3"]), []);
// Pusta pula telefonu (błąd) - nic nie kasujemy
assert.deepEqual(staleToDelete(onWatch, []), []);
// Stary nadmiar (bez znacznika odbioru) znika cały
assert.deepEqual(staleToDelete([{ id: "a" }, { id: "b" }, { id: "n1", rx: 1 }], ["n1"]), ["a", "b"]);

console.log("sync drip OK");
