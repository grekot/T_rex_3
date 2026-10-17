// `node test/points.test.mjs` - nazwy i identyfikatory miejsc
import assert from "node:assert/strict";
import { newId, cleanName, defaultName, PRESET_NAMES } from "../utils/points.js";

assert.match(newId(), /^[A-Za-z0-9]{20}$/);
assert.notEqual(newId(), newId());
assert.equal(cleanName("  Auto   pod   blokiem "), "Auto pod blokiem");
assert.equal(cleanName("x".repeat(60)).length, 40);
assert.equal(defaultName([{ name: "Punkt 1" }, { name: "Punkt 3" }]), "Punkt 2");
assert.equal(defaultName([]), "Punkt 1");
assert.ok(PRESET_NAMES.includes("Auto"));

console.log("points: WSZYSTKIE TESTY OK");
