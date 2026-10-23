// `node test/firestore.test.mjs` - zapis i odczyt dokumentu waga/{uid} (format z waga/SYNC.md)
import assert from "node:assert/strict";
import {
  wagaWrites,
  wagaGetRequest,
  decodeWagaDoc,
  dayFieldPath,
  commitRequest,
  docName,
  errorOf,
  authErrorMessage,
  isSessionDead,
} from "../utils/firestore.js";

const P = "proj";
const AT = Date.UTC(2026, 9, 23, 7, 0, 0);
const T1 = 1792738800123;

// Zapis: tylko wysłane dni + updatedAt + v (updateMask nie rusza innych dni ani celu)
const push = [
  { d: "2026-10-22", w: 826, t: T1 },
  { d: "2026-10-23", w: 0, t: T1 + 5 },
];
const writes = wagaWrites(P, "u1", push, AT);
assert.equal(writes.length, 1);
const w = writes[0].update;
assert.equal(w.name, "projects/proj/databases/(default)/documents/waga/u1");
assert.equal(w.name, docName(P, "waga/u1"));
assert.deepEqual(w.fields.e.mapValue.fields["2026-10-22"], {
  mapValue: { fields: { w: { integerValue: "826" }, t: { integerValue: String(T1) } } },
});
assert.deepEqual(w.fields.e.mapValue.fields["2026-10-23"].mapValue.fields.w, { integerValue: "0" });
assert.equal(w.fields.updatedAt.timestampValue, "2026-10-23T07:00:00.000Z");
assert.deepEqual(w.fields.v, { integerValue: "1" });
assert.deepEqual(writes[0].updateMask.fieldPaths, ["e.`2026-10-22`", "e.`2026-10-23`", "updatedAt", "v"]);
assert.equal(dayFieldPath("2026-01-05"), "e.`2026-01-05`");
assert.ok(!writes[0].currentDocument, "brak dokumentu = utworzenie");

// Odczyt: to, co zapisał zegarek, plus to, co zapisze telefon (liczby jako double, cel)
const found = [
  {
    found: {
      name: w.name,
      fields: {
        ...w.fields,
        goal: { integerValue: "780" },
        e: {
          mapValue: {
            fields: {
              ...w.fields.e.mapValue.fields,
              "2026-10-21": { mapValue: { fields: { w: { doubleValue: 830 }, t: { doubleValue: 5 } } } },
              "2026-10-20": { mapValue: { fields: { w: { stringValue: "x" } } } },
            },
          },
        },
      },
    },
    readTime: "x",
  },
];
const expected = {
  e: {
    "2026-10-21": { w: 830, t: 5 },
    "2026-10-22": { w: 826, t: T1 },
    "2026-10-23": { w: 0, t: T1 + 5 },
  },
  goal: 780,
};
assert.deepEqual(decodeWagaDoc(JSON.stringify(found)), expected);
assert.deepEqual(decodeWagaDoc(found), expected, "body jako obiekt");
assert.deepEqual(decodeWagaDoc([{ missing: w.name, readTime: "x" }]), { e: {}, goal: null });
assert.equal(decodeWagaDoc("zepsute"), null);
assert.deepEqual(decodeWagaDoc([{ found: { name: w.name, fields: { v: { integerValue: "1" } } } }]), { e: {}, goal: null });

// Zapytania
const get = wagaGetRequest(P, "tok", "u1");
assert.equal(get.method, "POST");
assert.ok(get.url.endsWith("/documents:batchGet"));
assert.deepEqual(JSON.parse(get.body), { documents: ["projects/proj/databases/(default)/documents/waga/u1"] });
assert.equal(get.headers.Authorization, "Bearer tok");
const c = commitRequest(P, "tok", writes);
assert.ok(c.url.endsWith("/documents:commit"));
assert.deepEqual(JSON.parse(c.body).writes, writes);

// Błędy i logowanie
assert.equal(errorOf(200, "[]"), null);
assert.equal(errorOf(403, JSON.stringify({ error: { message: "PERMISSION_DENIED" } })), "PERMISSION_DENIED");
assert.equal(errorOf(500, "x"), "HTTP 500");
assert.equal(authErrorMessage("INVALID_LOGIN_CREDENTIALS"), "Nieprawidłowy e-mail lub hasło");
assert.equal(isSessionDead("TOKEN_EXPIRED"), true);
assert.equal(isSessionDead("HTTP 500"), false);

console.log("firestore: WSZYSTKIE TESTY OK");
