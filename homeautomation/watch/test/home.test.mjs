// `node test/home.test.mjs` - dom, poziomy dostępu, pulpit zegarka -> kafelki, zgłoszenie zegarka (API.md pkt 12, 13a, 14)
import assert from "node:assert/strict";
import {
  pickHome,
  levelOf,
  canControl,
  knownDeviceIds,
  watchPages,
  dashboardDevices,
  pagesFromRooms,
  watchRecord,
  pointValue,
  stepPoint,
  findHub,
  sceneSteps,
  pickWatchDashboard,
  emptyMessage,
  iconAsset,
  formatPoint,
  describePoint,
} from "../utils/home.js";

// --- dom ---
assert.equal(pickHome([], "h1"), null);
assert.equal(pickHome(["h1", "h2"], "h2"), "h2");
assert.equal(pickHome(["h1", "h2"], "x"), "h1", "wybrany dom zniknął - pierwszy");
assert.equal(pickHome(["h1"], null), "h1");

// --- dostęp ---
assert.equal(levelOf(true, null, "t1"), "config", "właściciel ma wszystko");
assert.equal(levelOf(false, { t1: "view", _all: "control" }, "t1"), "view", "wpis urządzenia przed _all");
assert.equal(levelOf(false, { _all: "control" }, "t2"), "control");
assert.equal(levelOf(false, { t1: "view" }, "t2"), null, "brak wpisu = brak dostępu");
assert.equal(levelOf(false, { t1: "admin" }, "t1"), null, "nieznany poziom");
assert.equal(levelOf(false, null, "t1"), null);
assert.equal(canControl("view"), false);
assert.equal(canControl("control"), true);
assert.equal(canControl("config"), true);
assert.equal(canControl(null), false);

// --- urządzenia, które osoba zna ---
const rooms = { r1: { name: "Salon", devices: ["t1", "s1"] } };
const dashes = dashboardDevices({ pages: [{ tiles: [{ device: "s2" }, { scene: [{ device: "s3", set: { on: false } }] }, "zepsuty"] }] });
assert.deepEqual(dashes, ["s2", "s3"]);
assert.deepEqual(dashboardDevices(null), []);
// urządzenia z pulpitu zegarka są zawsze brane pod uwagę (np. węzeł spoza deviceIndex); filtruje levelOf
assert.deepEqual(knownDeviceIds(["t1", "s1"], null, rooms, dashes), ["s1", "s2", "s3", "t1"], "lista domu + pulpit");
assert.deepEqual(knownDeviceIds(["t1", "s1"], null, rooms, []), ["s1", "t1"]);
assert.deepEqual(knownDeviceIds(null, { t1: "control" }, rooms, []), ["t1"], "domownik: klucze access");
assert.deepEqual(knownDeviceIds(null, { _all: "view", t1: "control" }, rooms, dashes), ["s1", "s2", "s3", "t1"], "przy _all także pokoje");
assert.deepEqual(knownDeviceIds(null, null, rooms, []), []);
assert.equal(levelOf(true, null, "s2"), "config", "właściciel widzi urządzenie z pulpitu spoza indeksu");
assert.equal(levelOf(false, { t1: "control" }, "s2"), null, "domownik bez wpisu - nie");

// --- pulpit zegarka (pkt 13a) -> strony z kafelkami ---
const devices = {
  "termostat-ab12cd": { type: "thermostat", name: "Termostat", level: "control" },
  "shelly-3c61a2": { type: "switch", name: "Sufit", level: "view" },
  "swiatlo-1": { type: "dimmer", name: "Lampka", level: "config" },
  "obcy-1": { type: "hub", name: "Hub", level: "control" },
};
const board = {
  watch: { width: 480, height: 480, shape: "round" },
  pages: [
    {
      title: "Dom",
      tiles: [
        { id: "t1", device: "termostat-ab12cd", view: "thermostat", size: "big" },
        { id: "t2", device: "shelly-3c61a2", point: "on", view: "toggle", size: "half", label: "Salon" },
        { id: "t3", device: "termostat-ab12cd", point: "outdoor.temp", view: "value", size: "half" },
        { id: "t4", sceneId: "wyjscie", view: "scene", size: "full", label: "Wychodzę" },
        { id: "t5", device: "brak-dostepu", point: "on", view: "toggle", size: "half" },
        { id: "t6", device: "termostat-ab12cd", view: "stepper" },
        { id: "t7", device: "swiatlo-1", view: "toggle", size: "ogromny" },
        { id: "t8", device: "termostat-ab12cd", point: "heating", view: "status", size: "half" },
        { id: "t9", device: "swiatlo-1", point: "level", view: "chart" },
        { id: "t10", device: "shelly-3c61a2", view: "thermostat" },
        { id: "t11", scene: [{ device: "shelly-3c61a2", set: { on: true } }], view: "scene", label: "Tylko podgląd" },
        { id: "t12", device: "obcy-1", size: "full" },
        "zepsuty",
      ],
    },
    { title: "Pusta", tiles: [{ device: "brak-dostepu", view: "value", point: "temp" }] },
    { title: "Druga", tiles: { 0: { id: "x", device: "swiatlo-1", point: "on", view: "toggle", size: "half" } } },
  ],
};
// sceny domu (ARCHITEKTURA.md pkt 4.6); akcje po „delay” robi tylko hub
const scenes = {
  wyjscie: {
    name: "Wyjście",
    actions: [
      { device: "termostat-ab12cd", set: { mode: "auto" } },
      { device: "shelly-3c61a2", set: { on: false } },
      { delay: 600 },
      { device: "swiatlo-1", set: { on: false } },
    ],
  },
};
const pages = watchPages(board, devices, scenes, null);
assert.deepEqual(
  pages.map((p) => p.title),
  ["Dom", "Druga"],
  "strona bez dostępnych kafelków pominięta; tablica z bazy jako obiekt"
);
assert.deepEqual(pages[0].items, [
  { key: "t:t1", kind: "thermostat", device: "termostat-ab12cd", name: "Termostat", level: "control", point: null, size: "big" },
  { key: "t:t2", kind: "toggle", device: "shelly-3c61a2", name: "Salon", level: "view", point: "on", size: "half" },
  { key: "t:t3", kind: "value", device: "termostat-ab12cd", name: "Termostat", level: "control", point: "outdoor.temp", size: "half" },
  {
    key: "t:t4",
    kind: "scene",
    device: null,
    name: "Wychodzę",
    level: "control",
    point: null,
    size: "full",
    sceneId: "wyjscie",
    hub: null,
    scene: [{ device: "termostat-ab12cd", set: { mode: "auto" } }],
    partial: "hub",
  },
  { key: "t:t6", kind: "stepper", device: "termostat-ab12cd", name: "Termostat", level: "control", point: "target", size: "full" },
  { key: "t:t7", kind: "toggle", device: "swiatlo-1", name: "Lampka", level: "config", point: "on", size: "full" },
  { key: "t:t8", kind: "status", device: "termostat-ab12cd", name: "Termostat", level: "control", point: "heating", size: "half" },
  { key: "t:t9", kind: "value", device: "swiatlo-1", name: "Lampka", level: "config", point: "level", size: "full" },
  { key: "t:t10", kind: "toggle", device: "shelly-3c61a2", name: "Sufit", level: "view", point: "on", size: "full" },
  { key: "t:t12", kind: "unknown", device: "obcy-1", name: "Hub", level: "control", point: null, size: "full" },
]);
assert.deepEqual(watchPages(null, devices), []);
// z hubem scena to jedno polecenie do huba
const withHub = watchPages(board, devices, scenes, "hub-1")[0].items.find((it) => it.key === "t:t4");
assert.deepEqual([withHub.hub, withHub.sceneId, withHub.scene, withHub.partial], ["hub-1", "wyjscie", [], false]);
// scena, której nie ma (albo osoba nie może jej czytać) - kafelek pominięty
assert.equal(watchPages(board, devices, null, null)[0].items.some((it) => it.kind === "scene"), false);
// hub: urządzenie typu hub, którym osoba steruje
const noHub = { "termostat-ab12cd": devices["termostat-ab12cd"] };
assert.equal(findHub({ ...noHub, "hub-1": { type: "hub", level: "control" } }), "hub-1");
assert.equal(findHub({ ...noHub, "hub-1": { type: "hub", level: "view" } }), null, "hubem trzeba móc sterować");
assert.equal(findHub(noHub), null);
assert.equal(findHub(devices), "obcy-1");
// akcje sceny na zegarku
assert.deepEqual(sceneSteps(scenes.wyjscie.actions, devices), { steps: [{ device: "termostat-ab12cd", set: { mode: "auto" } }], partial: "hub" }, "opóźnienie ważniejsze od braku uprawnień");
assert.deepEqual(sceneSteps([{ device: "shelly-3c61a2", set: { on: true } }, { device: "swiatlo-1", set: { on: true } }], devices), { steps: [{ device: "swiatlo-1", set: { on: true } }], partial: "access" });
assert.deepEqual(sceneSteps([{ device: "swiatlo-1", set: { on: true } }, { delay: 5 }, { device: "swiatlo-1", set: { on: false } }], devices), { steps: [{ device: "swiatlo-1", set: { on: true } }], partial: "hub" });
assert.deepEqual(sceneSteps([{ device: "swiatlo-1", set: { on: true } }, { log: "x" }], devices), { steps: [{ device: "swiatlo-1", set: { on: true } }], partial: false });
assert.deepEqual(sceneSteps([{ scene: "inna" }], devices), { steps: [], partial: "hub" });
assert.deepEqual(sceneSteps(null, devices), { steps: [], partial: false });
assert.deepEqual(watchPages({ pages: "zle" }, devices), []);

// --- bez pulpitu zegarka: urządzenia według pokoi, strona na pokój ---
assert.deepEqual(
  pagesFromRooms(
    [
      { room: "Salon", ids: ["termostat-ab12cd", "nieznany"] },
      { room: null, ids: ["shelly-3c61a2", "hub-1"] },
    ],
    { ...devices, "hub-1": { type: "hub", name: "Hub", level: "config" } }
  ),
  [
    { title: "Salon", items: [{ key: "d:termostat-ab12cd", kind: "thermostat", device: "termostat-ab12cd", name: "Termostat", level: "control", point: null, size: "full" }] },
    { title: "", items: [{ key: "d:shelly-3c61a2", kind: "toggle", device: "shelly-3c61a2", name: "Sufit", level: "view", point: "on", size: "full" }] },
  ]
);

// --- zgłoszenie zegarka ---
assert.deepEqual(watchRecord({ deviceSource: 8716545, name: "Amazfit T-Rex 3", width: 480, height: 480, shape: "round" }, "1.0.0"), {
  id: "8716545",
  body: { name: "Amazfit T-Rex 3", deviceSource: 8716545, width: 480, height: 480, shape: "round", app: "1.0.0", lastSeen: { ".sv": "timestamp" } },
});
assert.equal(watchRecord({ deviceSource: 8716545, name: "" }, "1").body.name, "Zegarek 8716545", "bez nazwy modelu");
assert.equal(watchRecord({ deviceSource: 8716545, name: "123" }, "1").body.name, "Zegarek 8716545", "deviceName jako liczba");
assert.equal(watchRecord({ deviceSource: 1, shape: "square" }, "1").body.shape, "square");
assert.equal(watchRecord({ name: "X" }, "1"), null);
assert.equal(watchRecord(null, "1"), null);

// --- punkty: ścieżka z kropkami, krok wartości ---
assert.equal(pointValue({ outdoor: { temp: 4.2 } }, "outdoor.temp"), 4.2);
assert.equal(pointValue({ outdoor: null }, "outdoor.temp"), null);
assert.equal(pointValue({ on: false }, "on"), false);
assert.equal(pointValue(null, "on"), null);
const target = { min: 15, max: 30, step: 0.5 };
assert.equal(stepPoint(21, 1, target), 21.5);
assert.equal(stepPoint(30, 1, target), 30);
assert.equal(stepPoint(12, -1, target), 12, "poniżej zakresu: − nie podnosi");
assert.equal(stepPoint(12, 1, target), 15);
assert.equal(stepPoint(40, 1, { min: 0, max: 100, step: 10 }), 50);
assert.equal(stepPoint(0.3, 1, { step: 0.1 }), 0.4, "bez błędów zaokrągleń");
assert.equal(stepPoint(5, -1, {}), 4.5, "domyślny krok 0,5");
assert.equal(stepPoint(null, 1, target), null);

// --- wartości punktów ---
const describe = { type: "thermostat", points: [{ key: "temp", name: "Temperatura", unit: "°C", decimals: 1 }, { key: "hum", name: "Wilgotność", unit: "%" }, { key: "power", unit: "W", decimals: 1 }] };
assert.equal(describePoint(describe, "hum").name, "Wilgotność");
assert.equal(describePoint(describe, "xyz"), null);
assert.equal(describePoint(null, "hum"), null);
assert.equal(formatPoint(21.43, describePoint(describe, "temp")), "21,4°");
assert.equal(formatPoint(45, describePoint(describe, "hum")), "45%");
assert.equal(formatPoint(12.5, describePoint(describe, "power")), "12,5 W");
assert.equal(formatPoint(-3.2, { decimals: 1 }), "−3,2");
assert.equal(formatPoint(true, null), "tak");
assert.equal(formatPoint(false, null), "nie");
assert.equal(formatPoint(null, null), "--");
assert.equal(formatPoint("auto", null), "auto");
assert.equal(formatPoint({ temp: 1 }, null), "--");

// --- który pulpit zegarka: własny deviceSource, potem ułożony dla modelu z listy (zanim zegarek się zgłosił) ---
const P = (title) => ({ watch: { width: 480, height: 480, shape: "round" }, pages: [{ title, tiles: [{ id: "a", device: "x" }] }] });
const SCREEN = { width: 480, height: 480, shape: "round" };
assert.equal(pickWatchDashboard({ 8716545: P("mój"), "model:t-rex-3": P("model") }, "8716545", SCREEN).key, "8716545");
assert.equal(pickWatchDashboard({ "model:gtr-4": { ...P("gtr"), watch: { width: 466, height: 466, shape: "round" } }, "model:t-rex-3": P("t-rex") }, "8716545", SCREEN).key, "model:t-rex-3", "ten sam ekran");
assert.equal(pickWatchDashboard({ "model:gtr-4": { ...P("gtr"), watch: { width: 466, height: 466 } } }, "8716545", SCREEN).key, "model:gtr-4", "jedyny pulpit modelu");
assert.equal(pickWatchDashboard({ "999": P("inny zegarek") }, "8716545", SCREEN), null, "pulpit innego zgłoszonego zegarka - nie");
assert.equal(pickWatchDashboard({ 8716545: { pages: [] }, "model:t-rex-3": P("model") }, "8716545", SCREEN).key, "model:t-rex-3", "pusty własny - jak brak");
assert.equal(pickWatchDashboard(null, "8716545", SCREEN), null);
assert.deepEqual(pickWatchDashboard({ "model:t-rex-3": P("t") }, null, null).dashboard.pages[0].title, "t");

// --- pusty ekran: co brakuje ---
assert.match(emptyMessage({ homeName: "Dom", indexed: 0, visible: 0, dashboardTiles: 0 }), /nie ma jeszcze urządzeń w chmurze/);
assert.match(emptyMessage({ homeName: "Dom", indexed: 1, visible: 0, dashboardTiles: 2 }), /nie masz dostępu \(w chmurze: 1, z dostępem: 0\)/);
assert.match(emptyMessage({ homeName: "Dom", indexed: 3, visible: 0, dashboardTiles: 0 }), /Nie masz dostępu/);
assert.equal(emptyMessage(null).length > 0, true);

// --- ikony (pkt 12-13: klucze z katalogu telefonu) ---
assert.equal(iconAsset("ceiling", "toggle", "switch"), "bulb");
assert.equal(iconAsset("leave", "scene"), "leave");
assert.equal(iconAsset("thermostat", "value"), "thermo");
assert.equal(iconAsset("socket", "toggle", "switch"), "power");
assert.equal(iconAsset("pool", "toggle", "switch"), "power", "klucz bez obrazka - domyślna dla rodzaju");
assert.equal(iconAsset(null, "toggle", "dimmer"), "bulb");
assert.equal(iconAsset(null, "thermostat"), "thermo");
assert.equal(iconAsset(null, "scene"), "scene");
assert.equal(iconAsset(null, "value"), null);
assert.equal(iconAsset("pool", "value"), null);
// klucz z kafelka ma pierwszeństwo przed kluczem urządzenia (deviceIndex/{id}/icon); bez klucza - pole nie istnieje
const withIcons = watchPages(
  { pages: [{ tiles: [{ id: "i1", device: "swiatlo-1", view: "toggle", icon: "lamp" }, { id: "i2", device: "swiatlo-1", view: "toggle" }, { id: "i3", device: "termostat-ab12cd", view: "thermostat" }] }] },
  { ...devices, "swiatlo-1": { ...devices["swiatlo-1"], icon: "ceiling" } },
  null,
  null
)[0].items;
assert.deepEqual(withIcons.map((it) => it.icon), ["lamp", "ceiling", undefined]);
assert.equal("icon" in withIcons[2], false);

console.log("home.test.mjs: OK");
