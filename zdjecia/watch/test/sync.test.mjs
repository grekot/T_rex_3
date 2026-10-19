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
