// `node test/notify.test.mjs` - próba 0b: parametry budzika, treść powiadomienia, wybór zdjęcia
import assert from "node:assert/strict";
import {
  actionFile,
  testAlarmParam,
  directAlarmParam,
  notificationFor,
  openParam,
  pickPhoto,
  takenText,
  openLogLines,
  PHOTO_PAGE,
  OPEN_B_SERVICE,
  OPEN_C_SERVICE,
} from "../utils/notify.js";

// Przewidywalny „los”
function seq(...values) {
  let i = 0;
  return () => values[i++ % values.length];
}

assert.equal(actionFile("A"), PHOTO_PAGE);
assert.equal(actionFile("B"), OPEN_B_SERVICE);
assert.equal(actionFile("C"), OPEN_C_SERVICE);

const ids = Array.from({ length: 15 }, (_, i) => "id" + i);
const param = JSON.parse(testAlarmParam("B", ids, Math.random));
assert.equal(param.m, "B");
assert.equal(param.ids.length, 10);
assert.equal(new Set(param.ids).size, 10);
assert.deepEqual(JSON.parse(testAlarmParam("A", [], Math.random)), { m: "A", ids: [] });

const n = notificationFor(JSON.stringify({ m: "A", ids: ["x", "y"] }), seq(0.9));
assert.equal(n.title, "Zobacz to");
assert.equal(n.actions.length, 1);
assert.equal(n.actions[0].file, PHOTO_PAGE);
assert.deepEqual(JSON.parse(n.actions[0].param), { id: "y", m: "A" });
// Zły parametr nie wywraca usługi - sposób C bez zdjęcia
const fallback = notificationFor("zepsuty", Math.random);
assert.equal(fallback.actions[0].file, OPEN_C_SERVICE);
assert.deepEqual(JSON.parse(fallback.actions[0].param), { id: "", m: "C" });

assert.deepEqual(JSON.parse(openParam('{"id":"a","m":"B","x":1}')), { id: "a", m: "B" });
assert.deepEqual(JSON.parse(openParam(undefined)), { id: "", m: "?" });

const photos = [{ id: "a" }, { id: "b" }, { id: "c" }];
assert.equal(pickPhoto(photos, "b", seq(0)).id, "b");
assert.equal(pickPhoto(photos, "nie-ma", seq(0.99)).id, "c");
assert.equal(pickPhoto([], "a", Math.random), null);

assert.equal(takenText(0), "");
assert.equal(takenText(new Date(2026, 9, 12, 8, 5).getTime()), "12.10 08:05");

const at = new Date(2026, 9, 19, 13, 5, 9).getTime();
assert.deepEqual(openLogLines([{ m: "C", at: at - 1000 }, { m: "C", at }]), [
  "D: jeszcze nie",
  "A: jeszcze nie",
  "B: jeszcze nie",
  "C: otwarto 13:05:09",
]);

// Sposób D: budzik wprost do ekranu zdjęcia z wylosowanym zdjęciem
assert.deepEqual(JSON.parse(directAlarmParam(["a", "b", "c"], seq(0.5))), { id: "b", m: "D" });
assert.deepEqual(JSON.parse(directAlarmParam([], Math.random)), { id: "", m: "D" });

console.log("notify OK");
