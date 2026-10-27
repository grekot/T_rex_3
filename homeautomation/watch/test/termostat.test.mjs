// `node test/termostat.test.mjs` - nastawa, widok stanu, offline, potwierdzenia, zbieranie naciśnięć
// (logika ekranu termostatu; lista urządzeń i Side Service: devices.test.mjs, cloud.test.mjs)
import assert from "node:assert/strict";
import {
  stepTarget,
  formatTemp,
  isOffline,
  agoText,
  buildView,
  warningOf,
  modeInfo,
  outdoorText,
  ackResult,
  errorsText,
  pressTarget,
  chooseValue,
  sendDue,
  needsSend,
  shownValue,
  settleLocal,
  applyAck,
  SEND_DELAY_MS,
  ACK_TIMEOUT_MS,
  SETTLE_MS,
} from "../utils/termostat.js";

const NOW = Date.UTC(2026, 9, 27, 18, 0, 0);

// --- nastawa ---
assert.equal(stepTarget(21, 1), 21.5);
assert.equal(stepTarget(21, -1), 20.5);
assert.equal(stepTarget(30, 1), 30, "górna granica");
assert.equal(stepTarget(15, -1), 15, "dolna granica");
assert.equal(stepTarget(21.3, 1), 22, "zaokrąglenie do 0,5");
assert.equal(stepTarget(12, -1), 12, "eko poniżej zakresu: − nie podnosi");
assert.equal(stepTarget(12, 1), 15, "eko poniżej zakresu: + do 15");
assert.equal(stepTarget(null, 1), null);

assert.equal(formatTemp(21.4), "21,4°");
assert.equal(formatTemp(21), "21,0°");
assert.equal(formatTemp(-3.26), "−3,3°");
assert.equal(formatTemp(null), "--,-°");
assert.equal(formatTemp(undefined), "--,-°");

// --- offline: lastSeen starsze niż 3 min ---
assert.equal(isOffline(NOW - 60000, NOW), false);
assert.equal(isOffline(NOW - 180000, NOW), false);
assert.equal(isOffline(NOW - 180001, NOW), true);
assert.equal(isOffline(null, NOW), true);
assert.equal(agoText(NOW - 30000, NOW), "przed chwilą");
assert.equal(agoText(NOW - 12 * 60000, NOW), "12 min temu");
assert.equal(agoText(NOW - 5 * 3600000, NOW), "5 h temu");
assert.equal(agoText(NOW - 3 * 86400000, NOW), "3 dni temu");

// --- widok ---
const STATE = {
  id: "termostat-ab12cd",
  ts: 1793000000,
  temp: 21.4,
  hum: 45.0,
  target: 21.0,
  heating: true,
  sensorFault: false,
  power: true,
  mode: "auto",
  override: false,
  comfortNow: true,
  nextChange: "22:30",
  outdoor: { temp: 4.2, icon: 69, age: 600 },
  cloud: true,
};
const CONFIG = { name: "Salon", comfort: 21.0, eco: 18.0 };
const v = buildView(STATE, CONFIG, NOW - 30000, NOW);
assert.deepEqual(v, {
  name: "Salon",
  hasData: true,
  offline: false,
  ago: "przed chwilą",
  temp: 21.4,
  target: 21,
  heating: true,
  sensorFault: false,
  power: true,
  protect: null,
  mode: "auto",
  override: false,
  comfortNow: true,
  nextChange: "22:30",
  outdoor: 4.2,
});
assert.equal(warningOf(v), null);
assert.deepEqual(modeInfo(v, "auto"), { text: "komfort do 22:30", override: false });
assert.deepEqual(modeInfo({ ...v, comfortNow: false, nextChange: null }, "auto"), { text: "eko", override: false });
assert.deepEqual(modeInfo({ ...v, override: true }, "auto"), { text: "nadpisane do 22:30", override: true });
assert.deepEqual(modeInfo(v, "manual"), { text: "", override: false }, "przełączone na zegarku na ręczny");
assert.deepEqual(modeInfo({ ...v, mode: "manual" }, "auto"), { text: "", override: false }, "AUTO wybrane, termostat jeszcze nie przełączył");
assert.equal(outdoorText(v), "na zewnątrz 4,2°");
assert.equal(outdoorText({ ...v, outdoor: null }), "");

// awaria czujnika: temp null albo flaga
const fault = buildView({ ...STATE, temp: null, sensorFault: true, heating: false }, CONFIG, NOW, NOW);
assert.equal(fault.sensorFault, true);
assert.equal(fault.temp, null);
assert.equal(warningOf(fault), "Awaria czujnika");
assert.equal(buildView({ ...STATE, temp: null }, CONFIG, NOW, NOW).sensorFault, true);
// brak kontaktu ma pierwszeństwo
const off = buildView(STATE, CONFIG, NOW - 12 * 60000, NOW);
assert.equal(off.offline, true);
assert.equal(warningOf(off), "Brak kontaktu · 12 min temu");
assert.equal(warningOf(buildView({ ...STATE, power: false }, CONFIG, NOW, NOW)), "Termostat wyłączony");
// ochrona (State.protect): mróz przy wyłączonym, grzanie awaryjne przy awarii czujnika
assert.equal(warningOf(buildView({ ...STATE, power: false, protect: "frost" }, CONFIG, NOW, NOW)), "Wyłączony · ochrona przed mrozem");
assert.equal(warningOf(buildView({ ...STATE, temp: null, sensorFault: true, protect: "faultDuty" }, CONFIG, NOW, NOW)), "Awaria czujnika · grzanie awaryjne");
assert.equal(buildView({ ...STATE, protect: "cos" }, CONFIG, NOW, NOW).protect, null, "nieznana wartość");
// bez pogody, bez BMP280, tryb ręczny
const manual = buildView({ ...STATE, mode: "manual", outdoor: null, nextChange: null }, {}, NOW, NOW);
assert.equal(manual.mode, "manual");
assert.equal(manual.outdoor, null);
assert.equal(manual.name, "");
// termostat jeszcze nic nie wysłał
assert.deepEqual(buildView(null, null, null, NOW), { name: "", hasData: false, offline: true, ago: "" });
assert.equal(warningOf(buildView(null, null, null, NOW)), null);

// --- potwierdzenia (lastCommand) ---
assert.equal(ackResult(null, "-K1"), null);
assert.equal(ackResult({ key: "-K0", ok: true }, "-K1"), null, "jeszcze poprzednie polecenie");
assert.equal(ackResult({ key: "-K1", ok: true }, null), null);
assert.deepEqual(ackResult({ key: "-K1", ok: true, ts: NOW }, "-K1"), { ok: true, text: "Zapisano" });
assert.deepEqual(ackResult({ key: "-K1", ok: true, errors: {} }, "-K1"), { ok: true, text: "Zapisano" });
assert.deepEqual(ackResult({ key: "-K1", ok: false, errors: { target: "range" } }, "-K1"), {
  ok: false,
  text: "Błąd: nastawa poza zakresem",
});
assert.deepEqual(ackResult({ key: "-K1", ok: false, error: "expired" }, "-K1"), { ok: false, text: "Polecenie wygasło" });
assert.deepEqual(ackResult({ key: "-K1", ok: false, error: "busy" }, "-K1"), { ok: false, text: "Urządzenie zajęte" });
assert.deepEqual(ackResult({ key: "-K1", ok: false, error: "forbidden" }, "-K1"), { ok: false, text: "Brak uprawnień" });
assert.deepEqual(ackResult({ key: "-K1", ok: false, errors: { mode: "forbidden" } }, "-K1"), { ok: false, text: "Brak uprawnień" });
assert.deepEqual(ackResult({ key: "-K1", ok: false, error: "xyz" }, "-K1"), { ok: false, text: "Błąd: xyz" });
assert.equal(errorsText({ mode: "value" }), "Błąd: tryb zła wartość");
assert.equal(errorsText({ foo: "bar" }), "Błąd: foo bar");

// --- zbieranie naciśnięć ---
let local = null;
local = pressTarget(local, 21, 1, NOW);
local = pressTarget(local, 21, 1, NOW + 300);
local = pressTarget(local, 21, 1, NOW + 600);
assert.equal(local.value, 22.5, "trzy + od 21");
assert.equal(shownValue(local, 21), 22.5);
assert.equal(sendDue(local, NOW + 600 + SEND_DELAY_MS - 1), false, "jeszcze dotyka");
assert.equal(sendDue(local, NOW + 600 + SEND_DELAY_MS), true);
assert.equal(needsSend(local, 21), true);
assert.equal(settleLocal(local, 21, NOW + 5000), local, "niewysłane zostaje");
// wysłano: czekamy na potwierdzenie, potem na nowy stan
local = { ...local, sentAt: NOW + 1600, key: "-K1" };
assert.equal(sendDue(local, NOW + 9000), false, "nie wysyłamy drugi raz");
assert.equal(settleLocal(local, 21, NOW + 5000), local);
assert.equal(settleLocal(local, 22.5, NOW + 5000), null, "baza pokazuje nową nastawę");
assert.equal(settleLocal(local, 21, NOW + 1600 + ACK_TIMEOUT_MS + 1), null, "brak potwierdzenia - poddajemy się");
const acked = applyAck(local, { ok: true }, "-K1", NOW + 4000);
assert.equal(acked.ackedAt, NOW + 4000);
assert.equal(settleLocal(acked, 21, NOW + 4000 + SETTLE_MS - 1), acked, "potwierdzone, stan jeszcze stary");
assert.equal(settleLocal(acked, 21, NOW + 4000 + SETTLE_MS + 1), null);
assert.equal(applyAck(local, { ok: false }, "-K1", NOW + 4000), null, "odrzucone - wraca wartość z bazy");
assert.equal(applyAck(local, { ok: false }, "-K2", NOW + 4000).ackedAt, NOW + 4000, "błąd dotyczy późniejszego polecenia");
assert.equal(applyAck(null, { ok: true }, "-K1", NOW), null);
// + potem − z powrotem: nic nie wysyłamy (w AUTO włączyłoby to nadpisanie)
let back = pressTarget(null, 21, 1, NOW);
back = pressTarget(back, 21, -1, NOW + 200);
assert.equal(back.value, 21);
assert.equal(needsSend(back, 21), false);
// ...chyba że 21,5 już poszło - wtedy cofnięcie trzeba wysłać i nie ufać staremu stanowi
let undo = { ...pressTarget(null, 21, 1, NOW), sentAt: NOW + 1000, key: "-K1" };
undo = pressTarget(undo, 21, -1, NOW + 1500);
assert.equal(undo.value, 21);
assert.equal(undo.chain, true);
assert.equal(needsSend(undo, 21), true);
undo = { ...undo, sentAt: NOW + 2500, key: "-K2" };
assert.equal(settleLocal(undo, 21, NOW + 3000), undo, "21 w bazie to jeszcze stan sprzed obu poleceń");
assert.equal(settleLocal(applyAck(undo, { ok: true }, "-K2", NOW + 4000), 21, NOW + 4000), null);
// nastawy bez danych nie zmieniamy
assert.equal(pressTarget(null, null, 1, NOW), null);
// tryb: od razu do wysłania
const m = chooseValue(null, "auto", NOW);
assert.equal(sendDue(m, NOW), true);
assert.equal(needsSend(m, "manual"), true);
assert.equal(shownValue(m, "manual"), "auto");
assert.equal(shownValue(null, "manual"), "manual");

console.log("termostat.test.mjs: OK");
