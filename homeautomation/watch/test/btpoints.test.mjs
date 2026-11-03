// `node test/btpoints.test.mjs` - konfiguracja pilota, indeksy punktów, kodowanie wartości (API.md pkt 15.1-15.2),
// stan z Bluetooth na kafelkach i ekranie termostatu
import assert from "node:assert/strict";
import { normalizeBle, pointIndex, pointKind, encodeValue, decodeValue, btDevices, applyBt, applyBtView, cmdKeyOf } from "../utils/btpoints.js";

const KEY = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
const cfg = normalizeBle({
  homeId: "h1",
  hub: "hub-51e96c",
  id: "zegarek-8716545",
  slot: 3,
  key: KEY.toUpperCase(),
  cfgVer: 4,
  points: [
    { device: "termostat-ab12cd", point: "temp", kind: "sensor" },
    { device: "termostat-ab12cd", point: "target", kind: "setpoint" },
    { device: "swiatlo-79cfe4", point: "on2" },
    { device: "hub-51e96c", point: "runScene", arg: "wyjscie" },
    { device: "termostat-ab12cd", point: "mode", kind: "select", options: ["manual", "auto"] },
    { device: "termostat-ab12cd", point: "heating" },
  ],
});
assert.equal(cfg.key, KEY, "klucz małymi literami");
assert.equal(cfg.slot, 3);
assert.equal(cfg.cfgVer, 4);
assert.equal(cfg.points.length, 6);
assert.equal(normalizeBle({ ...cfg, key: "zly" }), null);
assert.equal(normalizeBle({ ...cfg, slot: 0 }), null);
assert.equal(normalizeBle({ ...cfg, id: "" }), null);
assert.equal(normalizeBle(null), null);
// lista z bazy jako obiekt {"0": …}
assert.equal(normalizeBle({ ...cfg, points: { 0: { device: "a", point: "on" } } }).points[0].device, "a");

// --- indeksy ---
assert.equal(pointIndex(cfg, "termostat-ab12cd", "target"), 1);
assert.equal(pointIndex(cfg, "swiatlo-79cfe4", "on2"), 2);
assert.equal(pointIndex(cfg, "hub-51e96c", "runScene", "wyjscie"), 3);
assert.equal(pointIndex(cfg, "hub-51e96c", "runScene", "inna"), -1);
assert.equal(pointIndex(cfg, "swiatlo-79cfe4", "on1"), -1);
assert.equal(pointIndex(null, "x", "y"), -1);

// --- rodzaje i kodowanie (pkt 15.2) ---
assert.equal(pointKind(cfg.points[0]), "number");
assert.equal(pointKind(cfg.points[2]), "bool", "onN po nazwie");
assert.equal(pointKind(cfg.points[3]), "action");
assert.equal(pointKind(cfg.points[4]), "select");
assert.equal(pointKind({ point: "power" }), "bool");
assert.equal(pointKind({ point: "mode" }), "select");
assert.equal(pointKind({ point: "level" }), "number");
assert.equal(encodeValue(cfg.points[1], 21.5), 2150);
assert.equal(encodeValue(cfg.points[1], -2.5), -250);
assert.equal(encodeValue(cfg.points[1], 21.456), 2146);
assert.equal(encodeValue(cfg.points[2], true), 1);
assert.equal(encodeValue(cfg.points[2], false), 0);
assert.equal(encodeValue(cfg.points[4], "auto"), 1);
assert.equal(encodeValue(cfg.points[4], "eco"), null);
assert.equal(encodeValue({ point: "mode" }, "manual"), 0, "domyślna lista trybów termostatu");
assert.equal(encodeValue(cfg.points[3], null), 0, "scena - wartość pomijana");
assert.equal(encodeValue(cfg.points[1], "x"), null);
assert.equal(decodeValue(cfg.points[0], 2143), 21.43);
assert.equal(decodeValue(cfg.points[0], -250), -2.5);
assert.equal(decodeValue(cfg.points[2], 1), true);
assert.equal(decodeValue(cfg.points[2], 0), false);
assert.equal(decodeValue(cfg.points[4], 1), "auto");
assert.equal(decodeValue(cfg.points[4], 7), null);

// --- stan z ramki na urządzenia ---
const bt = btDevices(cfg, 0, [
  { status: 1, value: 2143 },
  { status: 1, value: 2150 },
  { status: 1, value: 1 },
  { status: 1, value: 0 }, // scena - pomijana
  { status: 1, value: 1 },
  { status: 3, value: 0 }, // online, bez wartości
]);
assert.deepEqual(bt, {
  "termostat-ab12cd": { online: true, values: { temp: 21.43, target: 21.5, mode: "auto", heating: null } },
  "swiatlo-79cfe4": { online: true, values: { on2: true } },
});
// od drugiego punktu (kolejny odczyt przy liście > 32)
assert.deepEqual(btDevices(cfg, 2, [{ status: 0, value: 0 }]), { "swiatlo-79cfe4": { online: false, values: { on2: false } } });

// --- na kafelki ---
const devices = {
  "termostat-ab12cd": { type: "thermostat", name: "Salon", tile: { type: "thermostat", hasData: false, offline: true }, values: {} },
  "swiatlo-79cfe4": { type: "switch", name: "Sufit", tile: { type: "switch", hasData: true, offline: false, on: false }, values: { on2: false } },
  inne: { type: "switch", tile: { hasData: false } },
};
const after = applyBt(devices, bt);
assert.deepEqual(after["termostat-ab12cd"].tile, {
  type: "thermostat",
  hasData: true,
  offline: false,
  temp: 21.43,
  sensorFault: false,
  target: 21.5,
  heating: false,
});
assert.equal(after["swiatlo-79cfe4"].values.on2, true);
assert.equal(after["swiatlo-79cfe4"].tile.offline, false);
assert.equal(after.inne, devices.inne, "urządzenia spoza listy bez zmian");
assert.equal(devices["swiatlo-79cfe4"].values.on2, false, "wejście nie zmienione");
assert.deepEqual(applyBt(devices, { obce: { online: true, values: { on: true } } }), devices);
// offline z Bluetooth
assert.equal(applyBt(devices, { "swiatlo-79cfe4": { online: false, values: { on2: true } } })["swiatlo-79cfe4"].tile.offline, true);

// --- ekran termostatu ---
const view = { name: "Salon", hasData: true, offline: true, ago: "12 min temu", temp: 19, target: 20, heating: false, power: true, mode: "manual" };
assert.deepEqual(applyBtView(view, bt["termostat-ab12cd"]), {
  name: "Salon",
  hasData: true,
  offline: false,
  ago: "przed chwilą",
  temp: 21.43,
  sensorFault: false,
  target: 21.5,
  heating: false,
  power: true,
  mode: "auto",
});
assert.equal(applyBtView(view, null), view);
assert.equal(applyBtView(null, bt["termostat-ab12cd"]).hasData, true, "bez telefonu - sam Bluetooth");

assert.equal(cmdKeyOf(cfg, 1234), "zegarek-8716545:1234");
assert.equal(cmdKeyOf(null, 1), null);

console.log("btpoints.test.mjs: OK");
