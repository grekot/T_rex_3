// `node test/firestore.test.mjs` - zapytania REST do Firebase i dekodowanie odpowiedzi, bez sieci
import assert from "node:assert/strict";
import {
  documentsBase,
  docName,
  signInRequest,
  signUpRequest,
  emailKey,
  emailIndexWrites,
  refreshRequest,
  listsQueryRequest,
  itemsRequest,
  commitRequest,
  opWrites,
  commitOutcome,
  parseBody,
  errorOf,
  authErrorMessage,
  isSessionDead,
  decodeValue,
  parseTimestamp,
  decodeDocument,
  decodeQueryResponse,
  decodeListResponse,
} from "../utils/firestore.js";

const P = "zakupy-123";
const BASE = "https://firestore.googleapis.com/v1/projects/zakupy-123/databases/(default)/documents";
const NAME = "projects/zakupy-123/databases/(default)/documents/";

assert.equal(documentsBase(P), BASE);
assert.equal(docName(P, "lists/L1"), NAME + "lists/L1");

// logowanie
let r = signInRequest("KEY", "a@b.pl", "tajne");
assert.equal(r.url, "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=KEY");
assert.equal(r.method, "POST");
assert.deepEqual(JSON.parse(r.body), { email: "a@b.pl", password: "tajne", returnSecureToken: true });

r = signUpRequest("KEY", "a@b.pl", "tajne");
assert.equal(r.url, "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=KEY");
assert.deepEqual(JSON.parse(r.body), { email: "a@b.pl", password: "tajne", returnSecureToken: true });

r = refreshRequest("KEY", "abc/def+=");
assert.equal(r.url, "https://securetoken.googleapis.com/v1/token?key=KEY");
assert.equal(r.headers["Content-Type"], "application/x-www-form-urlencoded");
assert.equal(r.body, "grant_type=refresh_token&refresh_token=abc%2Fdef%2B%3D");

// zapytanie o listy użytkownika
r = listsQueryRequest(P, "TOKEN", "uid1");
assert.equal(r.url, BASE + ":runQuery");
assert.equal(r.headers.Authorization, "Bearer TOKEN");
const q = JSON.parse(r.body).structuredQuery;
assert.deepEqual(q.from, [{ collectionId: "lists" }]);
assert.deepEqual(q.where.fieldFilter, {
  field: { fieldPath: "members" },
  op: "ARRAY_CONTAINS",
  value: { stringValue: "uid1" },
});

r = itemsRequest(P, "TOKEN", "L1");
assert.equal(r.url, BASE + "/lists/L1/items?pageSize=300");
assert.equal(r.method, "GET");

// commit
r = commitRequest(P, "TOKEN", [{ delete: "x" }]);
assert.equal(r.url, BASE + ":commit");
assert.equal(r.method, "POST");
assert.equal(r.headers.Authorization, "Bearer TOKEN");
assert.deepEqual(JSON.parse(r.body), { writes: [{ delete: "x" }] });

const at = Date.parse("2026-10-16T10:00:00Z");
const ISO = "2026-10-16T10:00:00.000Z";

let w = opWrites(P, { t: "toggle", l: "L1", i: "I1", c: 1, at }, "uid1");
assert.equal(w.length, 1);
assert.equal(w[0].update.name, NAME + "lists/L1/items/I1");
assert.deepEqual(w[0].update.fields, {
  checked: { booleanValue: true },
  checkedAt: { timestampValue: ISO },
  updatedAt: { timestampValue: ISO },
  updatedBy: { stringValue: "watch" },
});
assert.deepEqual(w[0].updateMask.fieldPaths, ["checked", "checkedAt", "updatedAt", "updatedBy"]);
assert.deepEqual(w[0].currentDocument, { exists: true });
w = opWrites(P, { t: "toggle", l: "L1", i: "I1", c: 0, at }, "uid1");
assert.deepEqual(w[0].update.fields.checkedAt, { nullValue: null });

w = opWrites(P, { t: "addItem", l: "L1", i: "I9", n: "Ser", at }, "uid1");
assert.equal(w[0].update.name, NAME + "lists/L1/items/I9");
assert.deepEqual(w[0].update.fields.name, { stringValue: "Ser" });
assert.deepEqual(w[0].update.fields.checked, { booleanValue: false });
assert.deepEqual(w[0].update.fields.createdAt, { timestampValue: ISO });
assert.deepEqual(w[0].currentDocument, { exists: false });
assert.equal(w[0].updateMask, undefined, "nowy dokument - bez maski pól");

assert.deepEqual(opWrites(P, { t: "delItem", l: "L1", i: "I1", at }, "uid1"), [{ delete: NAME + "lists/L1/items/I1" }]);

w = opWrites(P, { t: "addList", l: "L3", n: "Lidl", at }, "uid1");
assert.equal(w[0].update.name, NAME + "lists/L3");
assert.deepEqual(w[0].update.fields.ownerId, { stringValue: "uid1" });
assert.deepEqual(w[0].update.fields.members, { arrayValue: { values: [{ stringValue: "uid1" }] } });
assert.deepEqual(w[0].currentDocument, { exists: false });

assert.deepEqual(opWrites(P, { t: "delList", l: "L1", at }, "uid1", ["A", "B"]), [
  { delete: NAME + "lists/L1/items/A" },
  { delete: NAME + "lists/L1/items/B" },
  { delete: NAME + "lists/L1" },
]);
assert.deepEqual(opWrites(P, { t: "delList", l: "L1", at }, "uid1"), [{ delete: NAME + "lists/L1" }]);
assert.deepEqual(opWrites(P, { t: "nieznana" }, "uid1"), []);

// opuszczenie cudzej listy: usuń siebie z members i swój e-mail z memberEmails
w = opWrites(P, { t: "leaveList", l: "L2", at }, "7uid");
assert.equal(w.length, 1);
assert.equal(w[0].update.name, NAME + "lists/L2");
assert.deepEqual(w[0].update.fields, { updatedAt: { timestampValue: ISO } });
assert.deepEqual(w[0].updateMask.fieldPaths, ["updatedAt", "memberEmails.`7uid`"], "uid w cudzysłowie (może zaczynać się cyfrą)");
assert.deepEqual(w[0].updateTransforms, [
  { fieldPath: "members", removeAllFromArray: { values: [{ stringValue: "7uid" }] } },
]);
assert.deepEqual(w[0].currentDocument, { exists: true });

// książka adresowa
assert.equal(emailKey("  Zona@X.PL "), "zona@x.pl");
w = emailIndexWrites(P, "uid1", " Ja@X.pl", at);
assert.equal(w[0].update.name, NAME + "emails/ja@x.pl");
assert.deepEqual(w[0].update.fields.uid, { stringValue: "uid1" });
assert.deepEqual(w[0].update.fields.email, { stringValue: "ja@x.pl" });
assert.equal(w[0].currentDocument, undefined, "zapis bez warunku - utworzy albo nadpisze");

// wynik commit
const err = (status, code) => ({ error: { code, status, message: status } });
const tog = { t: "toggle" };
const add = { t: "addItem" };
assert.equal(commitOutcome(tog, 200, { writeResults: [{}], commitTime: "x" }), "applied");
assert.equal(commitOutcome(tog, 200, '{"writeResults":[{}],"commitTime":"x"}'), "applied");
assert.equal(commitOutcome(tog, 404, err("NOT_FOUND", 404)), "gone", "produkt usunięty na telefonie");
assert.equal(commitOutcome(tog, 403, err("PERMISSION_DENIED", 403)), "gone", "lista usunięta na telefonie");
assert.equal(commitOutcome(tog, 400, err("FAILED_PRECONDITION", 400)), "gone");
assert.equal(commitOutcome(add, 409, err("ALREADY_EXISTS", 409)), "applied", "ponowienie udanego dodania");
assert.equal(commitOutcome(add, 400, err("FAILED_PRECONDITION", 400)), "applied");
assert.equal(commitOutcome(tog, 401, err("UNAUTHENTICATED", 401)), "auth");
assert.equal(commitOutcome(tog, 401, ""), "auth");
assert.equal(commitOutcome(tog, 503, err("UNAVAILABLE", 503)), "error");
assert.equal(commitOutcome(tog, 502, "<html>"), "error");
assert.equal(commitOutcome(tog, 200, {}), "error");

// odpowiedzi i błędy
assert.deepEqual(parseBody('{"a":1}'), { a: 1 });
assert.deepEqual(parseBody({ a: 1 }), { a: 1 });
assert.equal(parseBody("<html>"), null);
assert.equal(errorOf(200, { ok: 1 }), null);
assert.equal(errorOf(400, { error: { code: 400, message: "INVALID_LOGIN_CREDENTIALS" } }), "INVALID_LOGIN_CREDENTIALS");
assert.equal(errorOf(400, '{"error":"invalid_grant"}'), "invalid_grant");
assert.equal(errorOf(403, [{ error: { code: 403, message: "Missing or insufficient permissions." } }]), "Missing or insufficient permissions.");
assert.equal(errorOf(500, "<html>"), "HTTP 500");
assert.equal(authErrorMessage("INVALID_LOGIN_CREDENTIALS"), "Nieprawidłowy e-mail lub hasło");
assert.equal(authErrorMessage("TOO_MANY_ATTEMPTS_TRY_LATER : Access disabled"), "Za dużo prób, spróbuj później");
assert.equal(authErrorMessage("Coś innego"), "Coś innego");
assert.equal(isSessionDead("TOKEN_EXPIRED"), true);
assert.equal(isSessionDead("INVALID_REFRESH_TOKEN"), true);
assert.equal(isSessionDead("HTTP 500"), false);

// czas z mikrosekundami, bez ułamka i śmieci
assert.equal(parseTimestamp("2026-10-16T10:00:00.123456Z"), Date.parse("2026-10-16T10:00:00.123Z"));
assert.equal(parseTimestamp("2026-10-16T10:00:00Z"), Date.parse("2026-10-16T10:00:00Z"));
assert.equal(parseTimestamp("2026-10-16T10:00:00.5Z"), Date.parse("2026-10-16T10:00:00.500Z"));
assert.equal(parseTimestamp(""), null);

// dekodowanie dokumentów Firestore
assert.equal(decodeValue({ stringValue: "x" }), "x");
assert.equal(decodeValue({ booleanValue: false }), false);
assert.equal(decodeValue({ integerValue: "42" }), 42);
assert.equal(decodeValue({ timestampValue: "2026-10-16T10:00:00.123456Z" }), Date.parse("2026-10-16T10:00:00.123Z"));
assert.equal(decodeValue({ nullValue: null }), null);
assert.deepEqual(decodeValue({ arrayValue: { values: [{ stringValue: "u1" }] } }), ["u1"]);
assert.deepEqual(decodeValue({ arrayValue: {} }), []);
assert.deepEqual(decodeValue({ mapValue: { fields: { a: { integerValue: "1" } } } }), { a: 1 });

const listDoc = {
  name: "projects/zakupy-123/databases/(default)/documents/lists/L1",
  fields: {
    name: { stringValue: "Biedronka" },
    members: { arrayValue: { values: [{ stringValue: "uid1" }] } },
    createdAt: { timestampValue: "2026-10-16T08:00:00Z" },
  },
};
assert.deepEqual(decodeDocument(listDoc), {
  id: "L1",
  name: "Biedronka",
  members: ["uid1"],
  createdAt: Date.parse("2026-10-16T08:00:00Z"),
});

assert.deepEqual(
  decodeQueryResponse([{ document: listDoc, readTime: "x" }]).map((d) => d.id),
  ["L1"]
);
assert.deepEqual(decodeQueryResponse([{ readTime: "x" }]), [], "brak list = tylko readTime");
assert.deepEqual(decodeQueryResponse(JSON.stringify([{ document: listDoc }])).length, 1);

const items = decodeListResponse({
  documents: [
    {
      name: ".../lists/L1/items/I1",
      fields: { name: { stringValue: "Mleko" }, checked: { booleanValue: true }, checkedAt: { nullValue: null } },
    },
  ],
});
assert.deepEqual(items, [{ id: "I1", name: "Mleko", checked: true, checkedAt: null }]);
assert.deepEqual(decodeListResponse({}), [], "pusta lista produktów nie ma pola documents");

console.log("firestore: WSZYSTKIE TESTY OK");
