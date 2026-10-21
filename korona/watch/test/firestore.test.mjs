// `node test/firestore.test.mjs` - zapis i odczyt dokumentu korona/{uid} (format z korona/SYNC.md)
import assert from "node:assert/strict";
import {
  koronaWrites,
  koronaGetRequest,
  decodeKoronaDoc,
  commitRequest,
  docName,
  errorOf,
  authErrorMessage,
  isSessionDead,
} from "../utils/firestore.js";

const P = "proj";
const climbs = { rysy: { d: "2024-07-15", gps: true }, o123: { d: "2020-01-02", gps: false } };
const custom = { c1700000000000: { name: "Polana", lat: 49.7, lon: 20.25, d: "2025-06-01", gps: true } };
const AT = Date.UTC(2026, 9, 20, 10, 0, 0);

const writes = koronaWrites(P, "u1", climbs, custom, AT);
assert.equal(writes.length, 1);
const w = writes[0].update;
assert.equal(w.name, "projects/proj/databases/(default)/documents/korona/u1");
assert.equal(w.name, docName(P, "korona/u1"));
assert.deepEqual(w.fields.climbs.mapValue.fields.rysy, { mapValue: { fields: { d: { stringValue: "2024-07-15" }, gps: { booleanValue: true } } } });
assert.equal(w.fields.custom.mapValue.fields.c1700000000000.mapValue.fields.lat.doubleValue, 49.7);
assert.equal(w.fields.updatedAt.timestampValue, "2026-10-20T10:00:00.000Z");
assert.deepEqual(w.fields.v, { integerValue: "1" });
assert.ok(!writes[0].updateMask, "cały dokument nadpisywany");
// pusty stan też da się zapisać (cofnięcie wszystkiego)
assert.deepEqual(koronaWrites(P, "u1", {}, {}, AT)[0].update.fields.climbs, { mapValue: { fields: {} } });

// Odczyt: ten sam format, który zapisuje zegarek
const found = [{ found: { name: w.name, fields: w.fields }, readTime: "x" }];
assert.deepEqual(decodeKoronaDoc(JSON.stringify(found)), { climbs, custom });
assert.deepEqual(decodeKoronaDoc(found), { climbs, custom }, "body jako obiekt");
assert.equal(decodeKoronaDoc([{ missing: w.name, readTime: "x" }]), null);
assert.equal(decodeKoronaDoc("zepsute"), null);
// pusty dokument (bez map)
assert.deepEqual(decodeKoronaDoc([{ found: { name: w.name, fields: { v: { integerValue: "1" } } } }]), { climbs: {}, custom: {} });

const get = koronaGetRequest(P, "tok", "u1");
assert.equal(get.method, "POST");
assert.ok(get.url.endsWith("/documents:batchGet"));
assert.deepEqual(JSON.parse(get.body), { documents: [w.name] });
assert.equal(get.headers.Authorization, "Bearer tok");
const c = commitRequest(P, "tok", writes);
assert.ok(c.url.endsWith("/documents:commit"));
assert.equal(JSON.parse(c.body).writes.length, 1);

// Błędy
assert.equal(errorOf(200, '{"writeResults":[]}'), null);
assert.equal(errorOf(403, { error: { message: "PERMISSION_DENIED", code: 403 } }), "PERMISSION_DENIED");
assert.equal(errorOf(500, ""), "HTTP 500");
assert.equal(authErrorMessage("INVALID_LOGIN_CREDENTIALS"), "Nieprawidłowy e-mail lub hasło");
assert.equal(isSessionDead("TOKEN_EXPIRED"), true);
assert.equal(isSessionDead("HTTP 500"), false);

console.log("firestore.test.mjs: OK");
