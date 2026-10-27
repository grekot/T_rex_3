// `node test/devices.test.mjs` - typy urządzeń, kafelki, kolejność według pokoi (API.md pkt 0, 8.3, 10)
import assert from "node:assert/strict";
import { typeOf, isSwitchable, tileView, tileText, arrangeDevices } from "../utils/devices.js";

const NOW = Date.UTC(2026, 9, 27, 18, 0, 0);

// --- typ ---
assert.equal(typeOf({ type: "thermostat", name: "Salon" }, null), "thermostat");
assert.equal(typeOf({ type: "dimmer" }, { on: true }), "dimmer");
assert.equal(typeOf({ type: "hub" }, null), "hub");
assert.equal(typeOf(null, { temp: 21, target: 21 }), "thermostat", "bez info - po stanie");
assert.equal(typeOf(null, { on: false }), "switch");
assert.equal(typeOf(null, { on: false, level: 30 }), "dimmer");
assert.equal(typeOf(null, null), "unknown");
assert.equal(isSwitchable("switch"), true);
assert.equal(isSwitchable("dimmer"), true);
assert.equal(isSwitchable("thermostat"), false);

// --- kafelek termostatu ---
const th = tileView("thermostat", { temp: 21.4, target: 21.5, heating: true, sensorFault: false, power: true }, NOW - 1000, NOW);
assert.deepEqual(th, {
  type: "thermostat",
  hasData: true,
  offline: false,
  ago: "przed chwilą",
  temp: 21.4,
  target: 21.5,
  heating: true,
  sensorFault: false,
  power: true,
  protect: null,
});
assert.deepEqual(tileText(th), { value: "21,4°", sub: "nastawa 21,5° · grzeje", alert: false, heating: true, badge: null });
assert.equal(tileText({ ...th, heating: false }).sub, "nastawa 21,5°");
assert.deepEqual(tileText({ ...th, offline: true }), { value: "21,4°", sub: "Brak kontaktu", alert: true, heating: false, badge: null });
assert.deepEqual(tileText({ ...th, temp: null, sensorFault: true, heating: false }), { value: "--,-°", sub: "Awaria czujnika", alert: true, heating: false, badge: null });
assert.equal(tileText({ ...th, power: false, heating: false }).sub, "wyłączony");
// znacznik ochrony (State.protect, pkt 5)
const frost = tileView("thermostat", { temp: 6.5, target: 21, heating: true, power: false, protect: "frost" }, NOW, NOW);
assert.equal(frost.protect, "frost");
assert.deepEqual(tileText(frost), { value: "6,5°", sub: "wyłączony · grzeje", alert: false, heating: true, badge: { text: "MRÓZ", alert: false } });
const duty = tileView("thermostat", { temp: null, sensorFault: true, heating: true, power: true, protect: "faultDuty" }, NOW, NOW);
assert.deepEqual(tileText(duty).badge, { text: "AWARYJNIE", alert: true });
assert.equal(tileText(duty).sub, "Awaria czujnika");
assert.equal(tileText({ ...duty, offline: true }).badge, null, "bez kontaktu ochrona nieznana");
assert.equal(tileView("thermostat", { temp: 20, protect: "xyz" }, NOW, NOW).protect, null);
assert.equal(tileText(tileView("thermostat", null, null, NOW)).sub, "brak danych");
assert.equal(tileView("thermostat", { temp: null }, NOW, NOW).sensorFault, true);

// --- kafelek włącznika / ściemniacza ---
const sw = tileView("switch", { on: true, power: 12.5 }, NOW, NOW);
assert.deepEqual(sw, { type: "switch", hasData: true, offline: false, ago: "przed chwilą", on: true, level: null });
assert.deepEqual(tileText(sw), { value: "WŁ", sub: "włączone", alert: false, heating: false, on: true });
assert.deepEqual(tileText(sw, false), { value: "WYŁ", sub: "wyłączone", alert: false, heating: false, on: false }, "dotknięcie przed potwierdzeniem");
const dim = tileView("dimmer", { on: true, level: 80 }, NOW, NOW);
assert.equal(tileText(dim).sub, "jasność 80%");
assert.equal(tileText(dim, false).sub, "wyłączone");
assert.equal(tileText({ ...sw, offline: true }).sub, "Brak kontaktu");
assert.equal(tileText({ ...sw, offline: true }).alert, true);
assert.equal(tileText(tileView("switch", null, null, NOW)).sub, "brak danych");
assert.equal(tileText(tileView("hub", { x: 1 }, NOW, NOW)).sub, "nieobsługiwane urządzenie");

// --- kolejność ---
const ids = ["swiatlo-1", "swiatlo-2", "termostat-a", "termostat-b"];
const names = { "swiatlo-1": "Sufit", "swiatlo-2": "Lampka", "termostat-a": "Salon", "termostat-b": "Biuro" };
assert.deepEqual(arrangeDevices(ids, null, names), [{ room: null, ids: ["termostat-b", "swiatlo-2", "termostat-a", "swiatlo-1"] }], "bez pokoi: po nazwie");
const rooms = {
  r2: { name: "Sypialnia", order: 1, devices: ["swiatlo-2"] },
  r1: { name: "Salon", order: 0, devices: ["termostat-a", "swiatlo-1", "nieistniejace"] },
  r3: { name: "Pusty", order: 2, devices: [] },
  r4: { name: "Dubel", order: 3, devices: ["swiatlo-1"] },
};
assert.deepEqual(arrangeDevices(ids, rooms, names), [
  { room: "Salon", ids: ["termostat-a", "swiatlo-1"] },
  { room: "Sypialnia", ids: ["swiatlo-2"] },
  { room: "Inne", ids: ["termostat-b"] },
]);
// tablica w RTDB może przyjść jako obiekt {"0": ..., "1": ...}; pokój bez order na końcu
assert.deepEqual(arrangeDevices(["a", "b"], { x: { name: "X", devices: { 0: "b", 1: "a" } }, y: { name: "Y", order: 0, devices: ["zz"] } }, {}), [
  { room: "X", ids: ["b", "a"] },
]);
assert.deepEqual(arrangeDevices([], rooms, {}), []);

console.log("devices.test.mjs: OK");
