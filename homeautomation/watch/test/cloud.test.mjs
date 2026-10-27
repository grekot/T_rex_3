// `node test/cloud.test.mjs` - obieg Side Service (utils/cloud.js) na udawanej bazie z uproszczonymi
// regułami z SmartTermostatOLED/docs/firebase/database.rules.json (właściciel i domownik), pulpit zegarka
// (API.md pkt 13a) i zgłoszenie zegarka
import assert from "node:assert/strict";
import { poll, pollHome, send, registerWatch, newCache, LIST_TTL_MS } from "../utils/cloud.js";

const NOW = Date.UTC(2026, 9, 27, 18, 0, 0);
const DB = "https://db.example";
const WATCH = "8716545";
const STATE = { temp: 21.4, hum: 45, target: 21, heating: true, sensorFault: false, power: true, mode: "auto", nextChange: "22:30", outdoor: { temp: 4.2 } };

const tree = {
  users: {
    owner: { homes: { h1: true } },
    dom: {
      homes: { h1: true, h2: true },
      watchDashboards: {
        h1: {
          [WATCH]: {
            watch: { width: 480, height: 480, shape: "round" },
            pages: [
              {
                title: "Dom",
                tiles: [
                  { id: "t1", device: "termostat-aaa", view: "thermostat", size: "big" },
                  { id: "t2", device: "swiatlo-1", point: "on", view: "toggle", size: "half" },
                  { id: "t3", device: "termostat-aaa", point: "outdoor.temp", view: "value", size: "half", label: "Na dworze" },
                  { id: "t4", device: "swiatlo-2", point: "on", view: "toggle", size: "half" },
                  { id: "t5", device: "termostat-aaa", point: "target", view: "stepper", size: "full" },
                  { id: "t6", sceneId: "wyjscie", view: "scene", size: "full" }, // domownicy czytają sceny (reguły)
                ],
              },
            ],
          },
        },
      },
    },
    nikt: {},
  },
  homes: {
    h1: {
      name: "Dom",
      ownerUid: "owner",
      members: { owner: { role: "owner" }, dom: { role: "member" } },
      // lista urządzeń dla domowników (pkt 12); "swiatlo-2" bez nazwy - nazwa z urządzenia
      deviceIndex: {
        "termostat-aaa": { type: "thermostat", name: "Salon" },
        "swiatlo-1": { type: "switch", name: "Sufit" },
        "swiatlo-2": { type: "switch" },
      },
      access: { dom: { "termostat-aaa": "view", "swiatlo-1": "control" } },
      rooms: { r1: { name: "Salon", order: 0, devices: ["swiatlo-1", "termostat-aaa"] } },
      dashboards: { s1: { name: "Telefon", widgets: [{ device: "swiatlo-2", view: "toggle" }] } },
      scenes: { wyjscie: { name: "Wyjście", actions: [{ device: "swiatlo-1", set: { on: false } }, { device: "swiatlo-2", set: { on: false } }] } },
      devices: {
        "termostat-aaa": {
          info: { type: "thermostat", name: "Termostat" },
          config: { name: "Salon" },
          state: STATE,
          lastSeen: NOW - 20000,
          describe: {
            type: "thermostat",
            points: [
              { key: "outdoor.temp", name: "Na zewnątrz", unit: "°C", decimals: 1 },
              { key: "target", name: "Nastawa", unit: "°C", min: 15, max: 30, step: 0.5 },
            ],
          },
          history: { "2026-10-27": {} },
        },
        "swiatlo-1": { info: { type: "switch", name: "Sufit" }, state: { on: false }, lastSeen: NOW },
        "swiatlo-2": { info: { type: "switch", name: "Kuchnia" }, state: { on: true }, lastSeen: NOW },
      },
    },
    h2: { name: "Działka", ownerUid: "inny", access: { dom: { _all: "control" } }, rooms: { r: { name: "Altana", devices: ["lampa-9"] } }, devices: { "lampa-9": { info: { type: "switch" }, state: { on: true }, lastSeen: NOW } } },
  },
};

// Reguły (w skrócie): users/{uid} tylko swoje; homes/{h} całość - właściciel; name/ownerUid/rooms/dashboards -
// domownik; access/{uid} - swoje; devices/{id} - z dostępem;
// commands/{h}/{id} - by == uid i co najmniej control.
function allowedRead(uid, path) {
  if (path[0] === "users") return path[1] === uid;
  if (path[0] !== "homes" || !path[1]) return false;
  const home = tree.homes[path[1]];
  if (!home) return false;
  if (home.ownerUid === uid) return true;
  const member = !!(home.members && home.members[uid]) || !!(home.access && home.access[uid]);
  if (["name", "ownerUid", "rooms", "dashboards", "deviceIndex", "scenes"].includes(path[2])) return member;
  if (path[2] === "access") return path[3] === uid;
  if (path[2] === "devices" && path[3]) {
    const a = (home.access && home.access[uid]) || {};
    return a[path[3]] !== undefined || a._all !== undefined;
  }
  return false;
}

const denied = () => Object.assign(new Error("Permission denied"), { status: 401 });

function fakeDb() {
  const calls = [];
  const fetchJson = async (req) => {
    const uid = /auth=tok-([a-z]+)/.exec(req.url)[1];
    const path = req.url.slice(DB.length + 1).split(".json")[0].split("/").map(decodeURIComponent);
    const method = (req.headers && req.headers["X-HTTP-Method-Override"]) || req.method;
    calls.push(method + " " + path.join("/") + (/shallow/.test(req.url) ? "?shallow" : ""));
    const body = req.body ? JSON.parse(req.body) : null;
    if (method === "PUT") {
      if (path[0] !== "users" || path[1] !== uid) throw denied();
      const parent = path.slice(0, -1).reduce((o, k) => (o[k] = o[k] || {}), tree);
      parent[path[path.length - 1]] = JSON.parse(JSON.stringify(body).replace('{".sv":"timestamp"}', String(NOW)));
      return body;
    }
    if (method === "POST") {
      // commands/{homeId}/{deviceId}
      assert.equal(path[0], "commands");
      const home = tree.homes[path[1]];
      const a = (home.access && home.access[uid]) || {};
      const lv = home.ownerUid === uid ? "config" : a[path[2]] || a._all;
      if (body.by !== uid || !(lv === "control" || lv === "config")) throw denied();
      const node = path.reduce((o, k) => (o[k] = o[k] || {}), tree);
      const key = "-K" + (Object.keys(node).length + 1);
      node[key] = body;
      return { name: key };
    }
    if (!allowedRead(uid, path)) throw denied();
    let node = tree;
    for (const k of path) node = node && typeof node === "object" ? node[k] : undefined;
    if (node === undefined) return null;
    if (/shallow=true/.test(req.url)) return Object.fromEntries(Object.keys(node).map((k) => [k, true]));
    return JSON.parse(JSON.stringify(node));
  };
  return { fetchJson, calls };
}

const db = fakeDb();
const as = (uid) => ({ fetchJson: db.fetchJson, db: DB, token: "tok-" + uid, uid });
const items = (r) => r.pages.flatMap((p) => p.items.map((it) => [it.kind, it.device, it.level, it.size]));

// --- zgłoszenie zegarka ---
let reg = await registerWatch({ ...as("dom"), info: { deviceSource: 8716545, name: "Amazfit T-Rex 3", width: 480, height: 480, shape: "round" }, appVersion: "1.0.0" });
assert.deepEqual(reg, { ok: true, watchId: WATCH });
assert.deepEqual(tree.users.dom.watches[WATCH], { name: "Amazfit T-Rex 3", deviceSource: 8716545, width: 480, height: 480, shape: "round", app: "1.0.0", lastSeen: NOW });
reg = await registerWatch({ ...as("dom"), info: {}, appVersion: "1.0.0" });
assert.equal(reg.ok, false);

// --- właściciel bez pulpitu zegarka: urządzenia według pokoi (pulpitów telefonu zegarek nie pokazuje) ---
let cache = newCache();
let r = await pollHome({ ...as("owner"), wantedHome: null, watchId: WATCH, pending: null, cache, now: NOW });
assert.equal(r.ok, true);
assert.deepEqual(r.homes, [{ id: "h1", name: "Dom" }]);
assert.equal(r.homeId, "h1");
assert.equal(r.title, "Dom");
assert.equal(r.custom, false);
assert.deepEqual(r.pages.map((p) => p.title), ["Salon", "Inne"]);
assert.deepEqual(items(r), [
  ["toggle", "swiatlo-1", "config", "full"],
  ["thermostat", "termostat-aaa", "config", "full"],
  ["toggle", "swiatlo-2", "config", "full"],
]);
assert.equal(r.devices["termostat-aaa"].tile.temp, 21.4);
assert.deepEqual(r.devices["swiatlo-1"].values, { on: false }, "do zegarka tylko potrzebne punkty");
assert.deepEqual(r.devices["termostat-aaa"].values, {});
assert.ok(db.calls.includes("GET homes/h1/deviceIndex"));
assert.ok(!db.calls.includes("GET homes/h1/devices?shallow"), "z deviceIndex bez listy devices");
assert.ok(!db.calls.some((c) => /termostat-aaa\/(info|config\/name)|swiatlo-1\/(info|config\/name)/.test(c)), "typ i nazwa z deviceIndex");
assert.ok(db.calls.includes("GET homes/h1/devices/swiatlo-2/config/name"), "brak nazwy w indeksie - z urządzenia");
assert.equal(r.devices["swiatlo-2"].name, "Kuchnia");
assert.ok(db.calls.includes("GET users/owner/watchDashboards/h1"));
assert.deepEqual(r.diag, { homeName: "Dom", dashboard: null, dashboardTiles: 0, indexed: 3, visible: 3 });
assert.ok(!db.calls.some((c) => /history|describe|homes\/h1\/dashboards|prefs/.test(c)), "bez historii, pulpitów telefonu i prefs");

// drugi obieg: z pamięci tylko state + lastSeen urządzeń z ekranu
db.calls.length = 0;
await pollHome({ ...as("owner"), wantedHome: null, watchId: WATCH, pending: null, cache, now: NOW + 5000 });
assert.deepEqual(db.calls.sort(), [
  "GET homes/h1/devices/swiatlo-1/lastSeen",
  "GET homes/h1/devices/swiatlo-1/state",
  "GET homes/h1/devices/swiatlo-2/lastSeen",
  "GET homes/h1/devices/swiatlo-2/state",
  "GET homes/h1/devices/termostat-aaa/lastSeen",
  "GET homes/h1/devices/termostat-aaa/state",
]);

// --- domownik z pulpitem zegarka: kafelek bez dostępu pominięty, opis punktów z describe ---
cache = newCache();
db.calls.length = 0;
r = await pollHome({ ...as("dom"), wantedHome: null, watchId: WATCH, pending: null, cache, now: NOW });
assert.deepEqual(r.homes, [
  { id: "h1", name: "Dom" },
  { id: "h2", name: "Działka" },
]);
assert.equal(r.custom, true);
assert.deepEqual(r.pages.map((p) => p.title), ["Dom"]);
assert.deepEqual(items(r), [
  ["thermostat", "termostat-aaa", "view", "big"],
  ["toggle", "swiatlo-1", "control", "half"],
  ["value", "termostat-aaa", "view", "half"],
  ["stepper", "termostat-aaa", "view", "full"],
  ["scene", null, "control", "full"],
], "swiatlo-2 bez dostępu");
// scena domownika bez huba: akcje z jego poziomem - swiatlo-2 (bez dostępu) pominięte
const memberScene = r.pages[0].items[4];
assert.deepEqual([memberScene.sceneId, memberScene.hub, memberScene.scene, memberScene.partial], [
  "wyjscie",
  null,
  [{ device: "swiatlo-1", set: { on: false } }],
  "access",
]);
const outdoor = r.pages[0].items[2];
assert.deepEqual([outdoor.name, outdoor.point, outdoor.unit, outdoor.decimals, outdoor.pointName], ["Na dworze", "outdoor.temp", "°C", 1, "Na zewnątrz"]);
const stepper = r.pages[0].items[3];
assert.deepEqual([stepper.min, stepper.max, stepper.step], [15, 30, 0.5]);
assert.deepEqual(r.devices["termostat-aaa"].values, { "outdoor.temp": 4.2, target: 21 });
assert.equal(r.devices["swiatlo-2"], undefined);
assert.ok(db.calls.includes("GET homes/h1/devices/termostat-aaa/describe"));

// inny zegarek (bez własnego pulpitu) - lista urządzeń z dostępem
r = await pollHome({ ...as("dom"), wantedHome: null, watchId: "999", pending: null, cache, now: NOW + 1000 });
assert.equal(r.custom, false);
assert.deepEqual(items(r), [
  ["toggle", "swiatlo-1", "control", "full"],
  ["thermostat", "termostat-aaa", "view", "full"],
]);

// drugi dom z ustawień: domownik z _all nie czyta listy devices - urządzenia z pokoi
r = await pollHome({ ...as("dom"), wantedHome: "h2", watchId: WATCH, pending: null, cache: newCache(), now: NOW });
assert.equal(r.homeId, "h2");
assert.equal(r.title, "Działka");
assert.deepEqual(r.pages, [{ title: "Altana", items: [{ key: "d:lampa-9", kind: "toggle", device: "lampa-9", name: "lampa-9", level: "control", point: "on", size: "full" }] }]);

// --- polecenia: by = uid; domownik z „view” nie może sterować (reguły) ---
const sent = await send({ ...as("dom"), homeId: "h1", id: "swiatlo-1", values: { on: true } });
assert.deepEqual(tree.commands.h1["swiatlo-1"][sent.key], { values: { on: true }, ts: { ".sv": "timestamp" }, by: "dom", source: "watch" });
await assert.rejects(send({ ...as("dom"), homeId: "h1", id: "termostat-aaa", values: { target: 22 } }), /Permission denied/);
cache = newCache();
r = await pollHome({ ...as("dom"), wantedHome: "h1", watchId: WATCH, pending: { "swiatlo-1": sent.key }, cache, now: NOW });
assert.equal(r.devices["swiatlo-1"].ack, null, "jeszcze bez odpowiedzi");
tree.homes.h1.devices["swiatlo-1"].lastCommand = { key: sent.key, ok: false, errors: { on: "forbidden" } };
r = await pollHome({ ...as("dom"), wantedHome: "h1", watchId: WATCH, pending: { "swiatlo-1": sent.key }, cache, now: NOW + 1000 });
assert.deepEqual(r.devices["swiatlo-1"].ack, { ok: false, text: "Brak uprawnień" });

// --- osoba bez domu ---
r = await pollHome({ ...as("nikt"), wantedHome: null, watchId: WATCH, pending: null, cache: newCache(), now: NOW });
assert.deepEqual(r, { ok: true, homes: [], noHome: true });

// pamięć: po minucie dom czytany od nowa
cache = newCache();
await pollHome({ ...as("owner"), wantedHome: null, watchId: WATCH, pending: null, cache, now: NOW });
db.calls.length = 0;
await pollHome({ ...as("owner"), wantedHome: null, watchId: WATCH, pending: null, cache, now: NOW + LIST_TTL_MS + 1 });
assert.ok(db.calls.includes("GET users/owner/homes?shallow"));

// --- sceny (ARCHITEKTURA.md pkt 4.6): bez huba akcje po kolei, z hubem jedno polecenie runScene ---
tree.users.owner.watchDashboards = {
  h1: {
    [WATCH]: {
      pages: [{ title: "Sceny", tiles: [{ id: "s", sceneId: "wyjscie", view: "scene", size: "full", label: "Wychodzę" }, { id: "x", sceneId: "nie-ma", view: "scene" }] }],
    },
  },
};
cache = newCache();
r = await pollHome({ ...as("owner"), wantedHome: null, watchId: WATCH, pending: null, cache, now: NOW });
assert.deepEqual(r.pages[0].items.map((it) => [it.kind, it.name, it.sceneId, it.hub, it.scene.length]), [["scene", "Wychodzę", "wyjscie", null, 2]], "scena, której nie ma - pominięta");
assert.ok(db.calls.includes("GET homes/h1/scenes"));
tree.homes.h1.devices["hub-77"] = { info: { type: "hub", name: "Hub" }, state: {}, lastSeen: NOW };
tree.homes.h1.deviceIndex["hub-77"] = { type: "hub", name: "Hub" };
cache = newCache();
r = await pollHome({ ...as("owner"), wantedHome: null, watchId: WATCH, pending: null, cache, now: NOW });
assert.deepEqual(r.pages[0].items.map((it) => [it.sceneId, it.hub, it.scene.length]), [["wyjscie", "hub-77", 0]]);
const run = await send({ ...as("owner"), homeId: "h1", id: "hub-77", values: { runScene: "wyjscie" } });
assert.deepEqual(tree.commands.h1["hub-77"][run.key].values, { runScene: "wyjscie" });
// domownik: bez „control” na hubie scena idzie z zegarka (jego poziom dla każdego urządzenia) ...
const memberScene2 = async () => (await pollHome({ ...as("dom"), wantedHome: "h1", watchId: WATCH, pending: null, cache: newCache(), now: NOW })).pages[0].items.find((it) => it.kind === "scene");
let ms = await memberScene2();
assert.deepEqual([ms.hub, ms.scene.length], [null, 1]);
await assert.rejects(send({ ...as("dom"), homeId: "h1", id: "hub-77", values: { runScene: "wyjscie" } }), /Permission denied/);
// ... a z „control” na hubie - jedno polecenie runScene do huba
tree.homes.h1.access.dom["hub-77"] = "control";
ms = await memberScene2();
assert.deepEqual([ms.hub, ms.scene.length], ["hub-77", 0]);
const runDom = await send({ ...as("dom"), homeId: "h1", id: "hub-77", values: { runScene: "wyjscie" } });
assert.deepEqual(tree.commands.h1["hub-77"][runDom.key], { values: { runScene: "wyjscie" }, ts: { ".sv": "timestamp" }, by: "dom", source: "watch" });
delete tree.homes.h1.access.dom["hub-77"];
// bez pulpitu hub nie jest kafelkiem
r = await pollHome({ ...as("owner"), wantedHome: null, watchId: "999", pending: null, cache: newCache(), now: NOW });
assert.ok(!r.pages.some((p) => p.items.some((it) => it.device === "hub-77")));
delete tree.homes.h1.devices["hub-77"];
delete tree.homes.h1.deviceIndex["hub-77"];
// dom bez deviceIndex: właściciel czyta listę devices płytko
const savedIndex = tree.homes.h1.deviceIndex;
delete tree.homes.h1.deviceIndex;
db.calls.length = 0;
r = await pollHome({ ...as("owner"), wantedHome: null, watchId: "999", pending: null, cache: newCache(), now: NOW });
assert.ok(db.calls.includes("GET homes/h1/devices?shallow"));
assert.equal(r.devices["termostat-aaa"].name, "Salon");
tree.homes.h1.deviceIndex = savedIndex;
delete tree.users.owner.watchDashboards;

// --- pulpit ułożony na telefonie dla modelu z listy (zegarek jeszcze się nie zgłosił) ---
tree.users.owner.watchDashboards = {
  h1: { "model:t-rex-3": { watch: { width: 480, height: 480, shape: "round" }, pages: [{ title: "Z modelu", tiles: [{ id: "a", device: "swiatlo-1", point: "on1", view: "toggle", size: "half" }] }] } },
};
r = await pollHome({ ...as("owner"), wantedHome: null, watchId: WATCH, screen: { width: 480, height: 480, shape: "round" }, pending: null, cache: newCache(), now: NOW });
assert.equal(r.custom, true);
assert.equal(r.diag.dashboard, "model:t-rex-3");
assert.deepEqual(items(r), [["toggle", "swiatlo-1", "config", "half"]]);
assert.deepEqual(r.devices["swiatlo-1"].values, { on1: null }, "kanał przełącznika wielokanałowego (pkt 10.1)");
delete tree.users.owner.watchDashboards;

// --- ekran termostatu ---
db.calls.length = 0;
r = await poll({ ...as("dom"), homeId: "h1", id: "termostat-aaa", pending: null, now: NOW });
assert.equal(r.view.name, "Salon");
assert.equal(r.view.temp, 21.4);
assert.deepEqual(db.calls.sort(), [
  "GET homes/h1/devices/termostat-aaa/config",
  "GET homes/h1/devices/termostat-aaa/lastSeen",
  "GET homes/h1/devices/termostat-aaa/state",
]);
const t = await send({ ...as("owner"), homeId: "h1", id: "termostat-aaa", values: { target: 22 } });
tree.homes.h1.devices["termostat-aaa"].lastCommand = { key: t.key, ok: false, error: "busy" };
r = await poll({ ...as("owner"), homeId: "h1", id: "termostat-aaa", pending: t.key, now: NOW });
assert.deepEqual(r.ack, { ok: false, text: "Urządzenie zajęte" });

console.log("cloud.test.mjs: OK");
