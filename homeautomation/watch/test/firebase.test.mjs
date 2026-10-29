// `node test/firebase.test.mjs` - adresy i treści żądań REST (Auth + Realtime Database, API.md pkt 8.1, 12)
import assert from "node:assert/strict";
import {
  signInRequest,
  refreshRequest,
  dbUrl,
  readRequest,
  writeRequest,
  devicePath,
  commandRequest,
  decodeDevices,
  pushKeyOf,
  parseBody,
  errorOf,
  authErrorMessage,
  isSessionDead,
  isTokenRejected,
} from "../utils/firebase.js";

const DB = "https://zakupy-8ec54-default-rtdb.europe-west1.firebasedatabase.app";

// Logowanie
const si = signInRequest("KEY", "a@b.pl", "pw");
assert.equal(si.url, "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=KEY");
assert.equal(si.method, "POST");
assert.deepEqual(JSON.parse(si.body), { email: "a@b.pl", password: "pw", returnSecureToken: true });
const rf = refreshRequest("KEY", "r/t+1");
assert.equal(rf.url, "https://securetoken.googleapis.com/v1/token?key=KEY");
assert.equal(rf.body, "grant_type=refresh_token&refresh_token=r%2Ft%2B1");
assert.equal(rf.headers["Content-Type"], "application/x-www-form-urlencoded");

// Adresy bazy
assert.equal(dbUrl(DB + "/", ["termostat", "u1"], "tok"), DB + "/termostat/u1.json?auth=tok");
assert.deepEqual(readRequest(DB, "t.o/k", ["users", "u1", "homes"], true), {
  url: DB + "/users/u1/homes.json?auth=t.o%2Fk&shallow=true",
  method: "GET",
});
assert.equal(readRequest(DB, "tok", ["homes", "h1", "access", "u1"]).url, DB + "/homes/h1/access/u1.json?auth=tok");
assert.deepEqual(devicePath("h1", "termostat-ab12cd", "config/name"), ["homes", "h1", "devices", "termostat-ab12cd", "config", "name"]);
assert.deepEqual(devicePath("h1", "termostat-ab12cd"), ["homes", "h1", "devices", "termostat-ab12cd"]);
assert.equal(readRequest(DB, "tok", devicePath("h1", "termostat-ab12cd", "state")).url, DB + "/homes/h1/devices/termostat-ab12cd/state.json?auth=tok");

// Zapis węzła: POST z X-HTTP-Method-Override: PUT (zgłoszenie zegarka, pkt 13a)
const wr = writeRequest(DB, "tok", ["users", "u1", "watches", "8716545"], { name: "T-Rex 3", lastSeen: { ".sv": "timestamp" } });
assert.equal(wr.url, DB + "/users/u1/watches/8716545.json?auth=tok");
assert.equal(wr.method, "POST");
assert.equal(wr.headers["X-HTTP-Method-Override"], "PUT");
assert.deepEqual(JSON.parse(wr.body), { name: "T-Rex 3", lastSeen: { ".sv": "timestamp" } });

// Polecenie: POST do commands, znacznik czasu serwera, "by" = uid (wymagają tego reguły bazy)
const cmd = commandRequest(DB, "tok", "h1", "termostat-ab12cd", { target: 21.5 }, "u1");
assert.equal(cmd.method, "POST");
assert.equal(cmd.url, DB + "/commands/h1/termostat-ab12cd.json?auth=tok", "polecenia poza devices (pkt 8.1)");
assert.deepEqual(JSON.parse(cmd.body), { values: { target: 21.5 }, ts: { ".sv": "timestamp" }, by: "u1", source: "watch" });

// Odpowiedzi
assert.deepEqual(decodeDevices('{"termostat-b":true,"termostat-a":true}'), ["termostat-a", "termostat-b"]);
assert.deepEqual(decodeDevices({ "termostat-a": true }), ["termostat-a"], "body jako obiekt");
assert.deepEqual(decodeDevices("null"), []);
assert.deepEqual(decodeDevices(null), []);
assert.deepEqual(decodeDevices("zepsute"), []);
assert.equal(pushKeyOf('{"name":"-Nabc"}'), "-Nabc");
assert.equal(pushKeyOf("{}"), null);
assert.equal(parseBody("21.5"), 21.5);
assert.equal(parseBody('"Salon"'), "Salon");
assert.equal(parseBody("null"), null);
// Zepp potrafi oddać JSON już rozpakowany: napis z bazy przychodzi bez cudzysłowów
assert.equal(parseBody("Dom"), "Dom", "rozpakowany napis (homes/{h}/name)");
assert.equal(parseBody("aBc123XyZuidOwner"), "aBc123XyZuidOwner", "rozpakowany uid (ownerUid)");
assert.equal(parseBody(""), null);
assert.deepEqual(parseBody({ a: 1 }), { a: 1 });
assert.equal(parseBody(7), 7);
assert.equal(parseBody(undefined), null);

// Błędy: Google ({error:{message}}) i baza ({error:"..."})
assert.equal(errorOf(200, '{"temp":21}'), null);
assert.equal(errorOf(200, "null"), null, "pusty węzeł to nie błąd");
assert.equal(errorOf(200, "21.4"), null);
assert.equal(errorOf(401, '{"error":"Auth token is expired"}'), "Auth token is expired");
assert.equal(errorOf(401, { error: "Permission denied" }), "Permission denied");
assert.equal(errorOf(400, { error: { message: "INVALID_LOGIN_CREDENTIALS", code: 400 } }), "INVALID_LOGIN_CREDENTIALS");
assert.equal(errorOf(500, ""), "HTTP 500");
assert.equal(authErrorMessage("INVALID_LOGIN_CREDENTIALS"), "Nieprawidłowy e-mail lub hasło");
assert.equal(authErrorMessage("TOO_MANY_ATTEMPTS_TRY_LATER : Access disabled"), "Za dużo prób, spróbuj później");
assert.equal(isSessionDead("TOKEN_EXPIRED"), true);
assert.equal(isSessionDead("HTTP 500"), false);
assert.equal(isTokenRejected(401, "Permission denied"), true);
assert.equal(isTokenRejected(400, "Auth token is expired"), true);
assert.equal(isTokenRejected(500, "HTTP 500"), false);

console.log("firebase.test.mjs: OK");
