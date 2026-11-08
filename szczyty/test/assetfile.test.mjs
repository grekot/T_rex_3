import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { fileURLToPath } from "node:url";
import { openVerified } from "../utils/assetfile.js";
import { loadPeaksNear, MAGIC } from "../utils/peakdb.js";

const BIN = new Uint8Array(fs.readFileSync(fileURLToPath(new URL("../assets/gt.r/peaks.bin", import.meta.url))));

// Udawany uchwyt pliku; ignorePos = firmware ignoruje `position`, failPos = readAt rzuca
function backend(name, { ignorePos = false, failPos = false, failOpen = false } = {}) {
  return {
    name,
    open() {
      if (failOpen) throw new Error("fd -1");
      let at = 0;
      const next = (n) => {
        const b = BIN.slice(at, Math.min(BIN.length, at + n));
        at += b.length;
        return b;
      };
      return {
        readAt(p, n) {
          if (failPos) throw new Error("bad options");
          if (!ignorePos) at = p;
          return next(n);
        },
        readNext: next,
        close() {},
      };
    },
  };
}

const sameAsFile = (f) => {
  const res = loadPeaksNear(f.read, 49.6, 20.1, 106);
  assert.ok(res && res.peaks.length > 100);
  assert.ok(res.peaks.some((p) => p.name === "Turbacz"));
};

test("odczyt od pozycji - pierwszy sposób", () => {
  const f = openVerified([backend("zos"), backend("hmFS")], MAGIC);
  assert.equal(f.how, "zos");
  sameAsFile(f);
});

test("pozycja ignorowana - cały plik do pamięci", () => {
  const f = openVerified([backend("zos", { ignorePos: true })], MAGIC);
  assert.equal(f.how, "zos (całość)");
  sameAsFile(f);
});

test("readAt rzuca - cały plik do pamięci", () => {
  const f = openVerified([backend("zos", { failPos: true })], MAGIC);
  assert.equal(f.how, "zos (całość)");
  sameAsFile(f);
});

test("pierwszy sposób nie otwiera pliku - drugi", () => {
  const f = openVerified([backend("zos", { failOpen: true }), backend("hmFS")], MAGIC);
  assert.equal(f.how, "hmFS");
  sameAsFile(f);
});

test("nic nie działa - opis błędów", () => {
  const f = openVerified([backend("zos", { failOpen: true }), backend("hmFS", { failOpen: true })], MAGIC);
  assert.equal(f.read, undefined);
  assert.match(f.error, /zos: fd -1/);
  assert.match(f.error, /hmFS: fd -1/);
});
