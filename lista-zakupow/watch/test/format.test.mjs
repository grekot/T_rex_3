// `node test/format.test.mjs`
import assert from "node:assert/strict";
import { formatTime, plural, syncStatus, shorten } from "../utils/format.js";

assert.equal(formatTime(new Date(2026, 9, 16, 9, 5)), "09:05");
assert.equal(plural(1, "zmiana", "zmiany", "zmian"), "zmiana");
assert.equal(plural(3, "zmiana", "zmiany", "zmian"), "zmiany");
assert.equal(plural(5, "zmiana", "zmiany", "zmian"), "zmian");

const t = new Date(2026, 9, 16, 14, 32).getTime();
assert.equal(syncStatus(t, 0, false), "zsynchronizowano 14:32");
assert.equal(syncStatus(0, 0, false), "");
assert.equal(syncStatus(t, 0, true), "offline");
assert.equal(syncStatus(t, 1, true), "offline · 1 zmiana czeka");
assert.equal(syncStatus(t, 3, false), "3 zmiany czekają");
assert.equal(syncStatus(t, 5, true), "offline · 5 zmian czeka");

assert.equal(shorten("abc", 60), "abc");
assert.equal(shorten("x".repeat(80), 40).length, 40);

console.log("format: WSZYSTKIE TESTY OK");
