// `node test/format.test.mjs` - teksty pomiarów
import assert from "node:assert/strict";
import { formatBytes, formatMs, summaryLines, photoInfoLines, transferMs } from "../utils/format.js";
import { describeEvent, describeStart } from "../utils/events.js";

assert.equal(formatBytes(512), "512 B");
assert.equal(formatBytes(412 * 1024), "412 KB");
assert.equal(formatBytes(1.5 * 1024 * 1024), "1,5 MB");
assert.equal(formatBytes(undefined), "?");

assert.equal(formatMs(250), "250 ms");
assert.equal(formatMs(1234), "1,2 s");
assert.equal(formatMs(41_400), "41 s");
assert.equal(formatMs(65_000), "1 min 5 s");
assert.equal(formatMs(NaN), "?");

assert.equal(transferMs({ txMs: 1000, rxMs: 900 }), 1000);
assert.equal(transferMs({ rxMs: 900 }), 900);

const photos = [
  { id: "a", png: 400 * 1024, conv: 900 * 1024, cvMs: 1000, txMs: 40_000 },
  { id: "b", png: 200 * 1024, conv: 900 * 1024, cvMs: 2000, rxMs: 20_000 },
  { id: "t", test: true, png: 1, conv: 1, cvMs: 1, txMs: 1 },
];
assert.deepEqual(summaryLines(photos), ["Średnio: PNG 300 KB, na zegarku 900 KB", "konwersja 1,5 s, Bluetooth 30 s"]);
assert.deepEqual(summaryLines([]), []);
assert.equal(photoInfoLines(photos[0], 0, 2)[0], "1/2 · PNG 400 KB · zeg. 900 KB");
assert.equal(photoInfoLines(photos[0], 0, 2)[1], "pobr. ? · konw. 1,0 s · BT 40 s");

assert.equal(describeEvent({ type: "STEP", index: 0, count: 3, step: "convert" }).current, "Zdjęcie 1/3: konwersja...");
const sent = describeEvent({ type: "SENT", id: "a", index: 1, count: 3, conv: 921600, cvMs: 800, txMs: 41000, dlMs: 300 });
assert.equal(sent.log, "OK 2/3: zeg. 900 KB, konw. 800 ms, BT 41 s");
assert.equal(sent.photo.txMs, 41000);
assert.equal(describeEvent({ type: "DONE", sent: 3, count: 3, ms: 125000 }).done, true);
assert.match(describeEvent({ type: "FAIL", index: 0, count: 1, step: "download", error: "kod 1" }).log, /pobieranie/);
assert.deepEqual(describeEvent({ type: "?" }), {});

assert.match(describeStart({ ok: false, step: "manifest", error: "timeout" }), /Most niedostępny/);
assert.match(describeStart({ ok: true, todo: 0, total: 3 }), /brak nowych/);
assert.match(describeStart({ ok: true, todo: 2, total: 3, manifestMs: 120 }), /nowe: 2 z 3/);

console.log("format OK");
