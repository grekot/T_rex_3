// Dom, uprawnienia i pulpit zegarka (API.md pkt 12, 13a, 14) - bez API zegarka, testy w test/home.test.mjs.
// Z pulpitu zegarka (albo, bez niego, z listy urządzeń) powstają strony z „pozycjami” - kafelkami:
//   { key, kind: "thermostat"|"toggle"|"stepper"|"status"|"value"|"scene"|"unknown", device, name, level,
//     point, size: "half"|"full"|"big", scene }
import { isSwitchable } from "./devices.js";

const obj = (x) => (x && typeof x === "object" && !Array.isArray(x) ? x : null);
const num = (x) => (typeof x === "number" && isFinite(x) ? x : null);
const list = (x) => (Array.isArray(x) ? x : obj(x) ? Object.keys(x).map((k) => x[k]) : []);

export const LEVELS = { view: 1, control: 2, config: 3 };

export function pickHome(ids, wanted) {
  if (!ids || !ids.length) return null;
  return ids.indexOf(wanted) !== -1 ? wanted : ids[0];
}

// Poziom osoby dla urządzenia: właściciel domu - config; inaczej access[id], potem access._all; brak = null
export function levelOf(owner, access, deviceId) {
  if (owner) return "config";
  const a = obj(access) || {};
  const lv = a[deviceId] !== undefined ? a[deviceId] : a._all;
  return LEVELS[lv] ? lv : null;
}

export function canControl(level) {
  return (LEVELS[level] || 0) >= LEVELS.control;
}

// Urządzenia, które osoba może znać. Właściciel czyta listę devices; domownik nie ma do niej prawa,
// więc bierzemy klucze access, a przy _all także urządzenia z pokoi i pulpitu zegarka (extra = ich id).
export function knownDeviceIds(listed, access, rooms, extra) {
  const ids = {};
  const add = (id) => {
    if (typeof id === "string" && id && id !== "_all") ids[id] = true;
  };
  if (listed) listed.forEach(add);
  const a = obj(access) || {};
  Object.keys(a).forEach(add);
  if (!listed && a._all !== undefined) {
    Object.keys(obj(rooms) || {}).forEach((r) => list(obj(rooms[r]) && rooms[r].devices).forEach(add));
    (extra || []).forEach(add);
  }
  return Object.keys(ids).sort();
}

// Widoki kafelków na zegarku (pkt 13a); inne (wykres, suwak...) pokazujemy jako wartość
export const WATCH_VIEWS = ["value", "toggle", "stepper", "status", "thermostat", "scene"];
const SIZES = ["half", "full", "big"];
const DEFAULT_POINT = { toggle: "on", stepper: "target", status: "heating" };

// Domyślny kafelek urządzenia (lista bez pulpitu)
function deviceItem(id, dev, key) {
  const kind = dev.type === "thermostat" ? "thermostat" : isSwitchable(dev.type) ? "toggle" : "unknown";
  return { key, kind, device: id, name: dev.name || id, level: dev.level, point: kind === "toggle" ? "on" : null, size: "full" };
}

// Hub domu, którym osoba może sterować (info.type == "hub", API.md pkt 11) - to on uruchamia sceny
export function findHub(devices) {
  const ids = Object.keys(obj(devices) || {}).sort();
  return ids.find((id) => devices[id].type === "hub" && canControl(devices[id].level)) || null;
}

// Akcje sceny do wykonania na zegarku, po kolei (ARCHITEKTURA.md pkt 4.6): tylko „set” do urządzeń, którymi
// osoba steruje; na pierwszym „delay” stop - czekanie godzinami to robota huba.
// partial = dlaczego coś pominięto: "hub" (opóźnienie, scena w scenie), "access" (brak uprawnień) albo false.
export function sceneSteps(actions, devices) {
  const steps = [];
  let partial = false;
  let stopped = false;
  list(actions).forEach((a) => {
    if (stopped || !obj(a)) return;
    if (a.delay !== undefined) {
      stopped = true;
      partial = "hub";
      return;
    }
    if (!obj(a.set) || typeof a.device !== "string") {
      if (a.log === undefined) partial = "hub"; // np. scena w scenie
      return;
    }
    if (devices[a.device] && canControl(devices[a.device].level)) steps.push({ device: a.device, set: a.set });
    else if (!partial) partial = "access";
  });
  return { steps, partial };
}

// Kafelek sceny: sceneId -> homes/{h}/scenes/{id}; z hubem jedno polecenie {"runScene": id} do huba,
// bez huba akcje po kolei. Stary zapis: akcje wprost w kafelku (tile.scene).
function sceneItem(tile, key, size, devices, scenes, hub) {
  const base = { key, kind: "scene", device: null, level: "control", point: null, size };
  if (typeof tile.sceneId === "string" && tile.sceneId) {
    const scene = obj(obj(scenes) && scenes[tile.sceneId]);
    if (!scene) return null; // brak sceny albo brak prawa do jej odczytu
    const name = tile.label || scene.name || "Scena";
    if (hub) return { ...base, name, sceneId: tile.sceneId, hub, scene: [], partial: false };
    const { steps, partial } = sceneSteps(scene.actions, devices);
    return steps.length ? { ...base, name, sceneId: tile.sceneId, hub: null, scene: steps, partial } : null;
  }
  const { steps, partial } = sceneSteps(tile.scene, devices);
  return steps.length ? { ...base, name: tile.label || "Scena", sceneId: null, hub: null, scene: steps, partial } : null;
}

// Kafelek pulpitu zegarka -> pozycja albo null (bez dostępu, zepsuty). devices = {id: {type, name, level}}
function tileItem(tile, index, devices, scenes, hub) {
  if (!obj(tile)) return null;
  const key = "t:" + (tile.id || index);
  const size = SIZES.indexOf(tile.size) !== -1 ? tile.size : "full";
  if (tile.scene !== undefined || tile.sceneId !== undefined || tile.view === "scene") return sceneItem(tile, key, size, devices, scenes, hub);
  const dev = devices[tile.device];
  if (!dev || !dev.level) return null;
  const name = tile.label || dev.name || tile.device;
  const kind = WATCH_VIEWS.indexOf(tile.view) !== -1 ? tile.view : tile.point ? "value" : null;
  if (!kind) return { ...deviceItem(tile.device, { ...dev, name }, key), size };
  // widok termostatu na innym urządzeniu - domyślny kafelek tego urządzenia
  if (kind === "thermostat" && dev.type !== "thermostat") return { ...deviceItem(tile.device, { ...dev, name }, key), size };
  const point = typeof tile.point === "string" && tile.point ? tile.point : DEFAULT_POINT[kind] || null;
  if ((kind === "value" || kind === "status" || kind === "stepper" || kind === "toggle") && !point) return null;
  return { key, kind, device: tile.device, name, level: dev.level, point: kind === "thermostat" ? null : point, size };
}

// users/{uid}/watchDashboards/{homeId}/{watchId} -> [{title, items}] (strony bez kafelków pomijamy).
// scenes = homes/{h}/scenes (null, gdy brak prawa odczytu), hub = findHub(devices)
export function watchPages(dashboard, devices, scenes, hub) {
  return list(obj(dashboard) && dashboard.pages)
    .filter(obj)
    .map((page, p) => ({
      title: typeof page.title === "string" ? page.title : "",
      items: list(page.tiles)
        .map((tile, i) => tileItem(tile, p + "." + i, devices, scenes, hub || null))
        .filter(Boolean),
    }))
    .filter((page) => page.items.length);
}

// Urządzenia z pulpitu zegarka (domownik z _all nie czyta listy devices)
export function dashboardDevices(dashboard) {
  const ids = [];
  list(obj(dashboard) && dashboard.pages).forEach((page) =>
    list(obj(page) && page.tiles).forEach((tile) => {
      if (!obj(tile)) return;
      ids.push(tile.device);
      list(tile.scene).forEach((s) => obj(s) && ids.push(s.device));
    })
  );
  return ids.filter((id) => typeof id === "string" && id);
}

// Bez pulpitu zegarka: kafelek na każde dostępne urządzenie (bez huba - to most, nie ma czego pokazać),
// strona na pokój (arrangeDevices)
export function pagesFromRooms(arranged, devices) {
  const shown = (id) => devices[id] && devices[id].level && devices[id].type !== "hub";
  return arranged
    .map((s) => ({ title: s.room || "", items: s.ids.filter(shown).map((id) => deviceItem(id, devices[id], "d:" + id)) }))
    .filter((s) => s.items.length);
}

// Pulpit tego zegarka z users/{uid}/watchDashboards/{homeId} (mapa {watchId: pulpit}). Najpierw pod własnym
// deviceSource; gdy go nie ma - pulpit ułożony na telefonie dla modelu z listy („model:…”, zanim zegarek się zgłosił)
// o tym samym ekranie; na końcu jedyny pulpit „model:…” w domu. -> { key, dashboard } albo null
export function pickWatchDashboard(boards, watchId, screen) {
  const all = obj(boards) || {};
  const usable = (k) => obj(all[k]) && list(all[k].pages).length > 0;
  if (watchId && usable(watchId)) return { key: watchId, dashboard: all[watchId] };
  const models = Object.keys(all)
    .filter((k) => k.indexOf("model:") === 0 && usable(k))
    .sort();
  const s = obj(screen);
  if (s) {
    const same = models.find((k) => {
      const w = obj(all[k].watch) || {};
      return w.width === s.width && w.height === s.height && (w.shape || "round") === (s.shape || "round");
    });
    if (same) return { key: same, dashboard: all[same] };
  }
  return models.length === 1 ? { key: models[0], dashboard: all[models[0]] } : null;
}

// Pusty ekran: co dokładnie brakuje (diag z Side Service: homeName, indexed, visible, dashboardTiles)
export function emptyMessage(diag) {
  const d = obj(diag) || {};
  const home = d.homeName ? "„" + d.homeName + "”" : "";
  if (d.dashboardTiles > 0) {
    return "Kafelki z pulpitu zegarka wskazują urządzenia, których nie ma w chmurze albo do których nie masz dostępu. Przełączniki bez chmury działają z zegarka dopiero przez hub.";
  }
  if (!d.indexed) {
    return "Dom " + home + " nie ma jeszcze urządzeń w chmurze. Zegarek widzi tylko urządzenia połączone z chmurą (termostat) albo przez hub.";
  }
  if (!d.visible) return "Nie masz dostępu do żadnego urządzenia w domu " + home + ".";
  return "Brak urządzeń do pokazania.";
}

// Zgłoszenie zegarka (pkt 13a): users/{uid}/watches/{deviceSource}
export function watchRecord(info, appVersion) {
  const i = obj(info) || {};
  const source = num(i.deviceSource);
  if (source === null) return null;
  const name = typeof i.name === "string" && i.name && !/^\d+$/.test(i.name) ? i.name : "Zegarek " + source;
  return {
    id: String(source),
    body: {
      name,
      deviceSource: source,
      width: num(i.width) || 0,
      height: num(i.height) || 0,
      shape: i.shape === "square" ? "square" : "round",
      app: String(appVersion || ""),
      lastSeen: { ".sv": "timestamp" },
    },
  };
}

// Punkt stanu po ścieżce z kropkami: "outdoor.temp"
export function pointValue(state, path) {
  let v = obj(state) ? state : null;
  String(path || "")
    .split(".")
    .forEach((k) => {
      v = v !== null && v !== undefined && typeof v === "object" ? v[k] : undefined;
    });
  return v === undefined ? null : v;
}

// Krok wartości ustawialnej (pkt 14: min, max, step); poza zakresem nie skacze w przeciwną stronę
export function stepPoint(value, dir, spec) {
  const s = obj(spec) || {};
  const step = num(s.step) || 0.5;
  const v = num(value);
  if (v === null) return null;
  let next = Math.round((v + dir * step) / step) * step;
  next = Math.round(next * 1000) / 1000;
  if (num(s.max) !== null) next = Math.min(s.max, next);
  if (num(s.min) !== null) next = Math.max(s.min, next);
  if ((dir < 0 && next > v) || (dir > 0 && next < v)) return v;
  return next;
}

// Wartość punktu do wyświetlenia (pkt 14: unit, decimals; bool jako tak / nie)
export function formatPoint(value, point) {
  const p = obj(point) || {};
  if (value === null || value === undefined) return "--";
  if (typeof value === "boolean") return value ? "tak" : "nie";
  if (typeof value === "number") {
    const d = num(p.decimals);
    const text = (d === null ? String(Math.round(value * 10) / 10) : value.toFixed(d)).replace(".", ",").replace("-", "−");
    return text + (p.unit ? (p.unit === "%" || p.unit === "°C" ? "" : " ") + (p.unit === "°C" ? "°" : p.unit) : "");
  }
  if (typeof value === "object") return "--";
  return String(value);
}

// Opis punktu z describe (pkt 14) albo null
export function describePoint(describe, key) {
  const d = obj(describe);
  return (d && list(d.points).find((p) => obj(p) && p.key === key)) || null;
}
