import assert from "node:assert";
import { summary, line, verdict } from "../utils/stats.js";

assert.deepStrictEqual(summary([30, 10, 20]), { n: 3, min: 10, avg: 20, max: 30 });
assert.deepStrictEqual(summary([10, null, undefined, 20]), { n: 2, min: 10, avg: 15, max: 20 });
assert.strictEqual(summary([]), null);

assert.strictEqual(line("echo", summary([10, 30])), "echo: 10/20/30 ms");
assert.strictEqual(line("echo", null), "echo: brak");

assert.strictEqual(verdict([1000, 2000]), "OK: laczenie w limicie");
assert.strictEqual(verdict([1600]), "za wolno: limit 1,5 s");
assert.strictEqual(verdict([]), "brak polaczenia");

console.log("stats: OK");
