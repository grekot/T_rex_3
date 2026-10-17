// `node test/firestore.test.mjs` - zapytania REST do Firebase dla miejsc, bez sieci
import assert from "node:assert/strict";
import {
  documentsBase,
  docName,
  signInRequest,
  signUpRequest,
  refreshRequest,
  placesQueryRequest,
  commitRequest,
  opWrites,
  commitOutcome,
  emailIndexWrites,
  parseBody,
  errorOf,
  authErrorMessage,
  decodeValue,
  decodeQueryResponse,
} from "../utils/firestore.js";

const P = "zakupy-123";
const BASE = "https://firestore.googleapis.com/v1/projects/zakupy-123/databases/(default)/documents";
const NAME = "projects/zakupy-123/databases/(default)/documents/";

assert.equal(documentsBase(P), BASE);
assert.equal(docName(P, "places/X"), NAME + "places/X");
assert.ok(signInRequest("K", "a@b.pl", "x").url.endsWith("accounts:signInWithPassword?key=K"));
assert.ok(signUpRequest("K", "a@b.pl", "x").url.endsWith("accounts:signUp?key=K"));
assert.ok(refreshRequest("K", "t").url.endsWith("/token?key=K"));

// zapytanie o moje i udostępnione mi miejsca
let r = placesQueryRequest(P, "TOKEN", "uid1");
assert.equal(r.url, BASE + ":runQuery");
const q = JSON.parse(r.body).structuredQuery;
assert.deepEqual(q.from, [{ collectionId: "places" }]);
assert.deepEqual(q.where.fieldFilter.value, { stringValue: "uid1" });
assert.equal(q.where.fieldFilter.op, "ARRAY_CONTAINS");

r = commitRequest(P, "TOKEN", []);
assert.equal(r.url, BASE + ":commit");

const at = Date.parse("2026-10-17T10:00:00Z");
const ISO = "2026-10-17T10:00:00.000Z";

// dodanie miejsca
let w = opWrites(P, { t: "addPlace", p: { id: "P1", name: "Auto", lat: 52.1, lon: 21.05, at }, at }, "7uid", "ja@x.pl");
assert.equal(w.length, 1);
assert.equal(w[0].update.name, NAME + "places/P1");
const f = w[0].update.fields;
assert.deepEqual(f.name, { stringValue: "Auto" });
assert.deepEqual(f.lat, { doubleValue: 52.1 });
assert.deepEqual(f.lon, { doubleValue: 21.05 });
assert.deepEqual(f.savedAt, { timestampValue: ISO });
assert.deepEqual(f.ownerId, { stringValue: "7uid" });
assert.deepEqual(f.members, { arrayValue: { values: [{ stringValue: "7uid" }] } });
assert.deepEqual(f.memberEmails, { mapValue: { fields: { "7uid": { stringValue: "ja@x.pl" } } } });
assert.deepEqual(w[0].currentDocument, { exists: false });

// usunięcie własnego i opuszczenie cudzego
assert.deepEqual(opWrites(P, { t: "delPlace", pid: "P1", at }, "7uid"), [{ delete: NAME + "places/P1" }]);
w = opWrites(P, { t: "leavePlace", pid: "P2", at }, "7uid");
assert.equal(w[0].update.name, NAME + "places/P2");
assert.deepEqual(w[0].updateMask.fieldPaths, ["updatedAt", "memberEmails.`7uid`"]);
assert.deepEqual(w[0].updateTransforms, [{ fieldPath: "members", removeAllFromArray: { values: [{ stringValue: "7uid" }] } }]);
assert.deepEqual(opWrites(P, { t: "nieznana" }, "u"), []);

// wynik zapisu
const err = (status, code) => ({ error: { code, status, message: status } });
assert.equal(commitOutcome({ t: "addPlace" }, 200, { writeResults: [{}] }), "applied");
assert.equal(commitOutcome({ t: "addPlace" }, 409, err("ALREADY_EXISTS", 409)), "applied");
assert.equal(commitOutcome({ t: "addPlace" }, 400, err("FAILED_PRECONDITION", 400)), "applied");
assert.equal(commitOutcome({ t: "leavePlace" }, 404, err("NOT_FOUND", 404)), "gone");
assert.equal(commitOutcome({ t: "delPlace" }, 403, err("PERMISSION_DENIED", 403)), "gone");
assert.equal(commitOutcome({ t: "delPlace" }, 401, err("UNAUTHENTICATED", 401)), "auth");
assert.equal(commitOutcome({ t: "delPlace" }, 503, err("UNAVAILABLE", 503)), "error");

// książka adresowa i drobiazgi
w = emailIndexWrites(P, "uid1", " Ja@X.pl", at);
assert.equal(w[0].update.name, NAME + "emails/ja@x.pl");
assert.deepEqual(parseBody('{"a":1}'), { a: 1 });
assert.equal(errorOf(500, "<html>"), "HTTP 500");
assert.equal(authErrorMessage("EMAIL_EXISTS"), "Konto z tym e-mailem już istnieje - zaloguj się");
assert.equal(decodeValue({ doubleValue: 52.1 }), 52.1);
assert.equal(decodeValue({ integerValue: "52" }), 52, "lat zapisany z telefonu jako liczba całkowita");
assert.deepEqual(
  decodeQueryResponse([{ document: { name: NAME + "places/P1", fields: { name: { stringValue: "Auto" } } } }]).map((d) => d.id),
  ["P1"]
);

console.log("firestore: WSZYSTKIE TESTY OK");
