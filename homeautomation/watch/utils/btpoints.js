// Lista punktów pilota (API.md pkt 15.1: homes/{h}/remotes/{id}.points) po stronie zegarka: konfiguracja z telefonu,
// indeks punktu w ramkach, kodowanie wartości (pkt 15.2) i nakładanie stanu z Bluetooth na kafelki.
// Bez API zegarka; testy w test/btpoints.test.mjs.

const obj = (x) => (x && typeof x === "object" && !Array.isArray(x) ? x : null);
const str = (x) => (typeof x === "string" && x ? x : null);

export const MODE_OPTIONS = ["manual", "auto"]; // termostat (pkt 5), gdy describe nie podał listy
const BOOL_POINT = /^(on\d*|power|heating|sensorFault|override|comfortNow)$/;

// Konfiguracja Bluetooth z Side Service: users/{uid}/watches/{watchId}/ble + homes/{h}/remotes/{id}
// -> { homeId, hub, id, slot, key, cfgVer, points: [{device, point, arg, kind, options}] } albo null
export function normalizeBle(cfg) {
  const c = obj(cfg);
  if (!c) return null;
  const key = str(c.key);
  const slot = Number(c.slot);
  if (!key || !/^[0-9a-fA-F]{64}$/.test(key) || !(slot >= 1 && slot <= 250) || !str(c.id)) return null;
  const points = (Array.isArray(c.points) ? c.points : obj(c.points) ? Object.keys(c.points).map((k) => c.points[k]) : [])
    .slice(0, 128)
    .map((p) => {
      const o = obj(p) || {};
      return {
        device: str(o.device),
        point: str(o.point),
        arg: str(o.arg),
        kind: str(o.kind),
        options: Array.isArray(o.options) ? o.options.map(String) : null,
      };
    });
  return {
    homeId: str(c.homeId),
    hub: str(c.hub),
    id: c.id,
    slot,
    key: key.toLowerCase(),
    cfgVer: Number(c.cfgVer) >= 0 ? Number(c.cfgVer) & 0xffff : 0,
    points,
  };
}

// Indeks punktu w liście (pozycja = numer w ramkach) albo -1. arg - tylko dla runScene (id sceny).
export function pointIndex(cfg, device, point, arg) {
  if (!cfg) return -1;
  return cfg.points.findIndex((p) => p.device === device && p.point === point && (arg === undefined || arg === null || p.arg === arg));
}

// Rodzaj punktu: "bool" | "select" | "action" | "number" (z describe, inaczej po nazwie)
export function pointKind(p) {
  const k = p && p.kind;
  if (k === "switch" || k === "status") return "bool";
  if (k === "select") return "select";
  if (k === "action" || (p && p.point === "runScene")) return "action";
  if (k === "sensor" || k === "setpoint") return "number";
  if (p && BOOL_POINT.test(p.point || "")) return "bool";
  if (p && p.point === "mode") return "select";
  return "number";
}

function optionsOf(p) {
  return p.options && p.options.length ? p.options : p.point === "mode" ? MODE_OPTIONS : [];
}

// Wartość -> int32 do ramki (pkt 15.2) albo null, gdy się nie da (tekst spoza listy)
export function encodeValue(p, v) {
  switch (pointKind(p)) {
    case "bool":
      return v ? 1 : 0;
    case "select": {
      const i = optionsOf(p).indexOf(String(v));
      return i === -1 ? null : i;
    }
    case "action":
      return 0;
    default: {
      const n = Number(v);
      if (!isFinite(n)) return null;
      const x = Math.round(n * 100);
      return x > 2147483647 || x < -2147483648 ? null : x;
    }
  }
}

// int32 z ramki -> wartość punktu (null = brak)
export function decodeValue(p, raw) {
  switch (pointKind(p)) {
    case "bool":
      return raw !== 0;
    case "select": {
      const o = optionsOf(p);
      return raw >= 0 && raw < o.length ? o[raw] : null;
    }
    case "action":
      return null;
    default:
      return raw / 100;
  }
}

// Odczyt stanu od indeksu `from` -> { device: { online, values: {point: wartość} } }
export function btDevices(cfg, from, points) {
  const out = {};
  (points || []).forEach((pv, i) => {
    const p = cfg && cfg.points[from + i];
    if (!p || !p.device || !p.point || pointKind(p) === "action") return;
    const d = (out[p.device] = out[p.device] || { online: false, values: {} });
    if (pv.status & 0x01) d.online = true;
    d.values[p.point] = pv.status & 0x02 ? null : decodeValue(p, pv.value);
  });
  return out;
}

// Stan z Bluetooth na urządzenia pulpitu (devices z Side Service albo z pamięci): wartości punktów kafelków
// i pola kafelka (tileView: termostat temp/target/heating/power, włącznik on). Zwraca nowy obiekt.
export function applyBt(devices, bt) {
  const out = { ...(obj(devices) || {}) };
  Object.keys(obj(bt) || {}).forEach((id) => {
    const d = out[id];
    if (!d) return;
    const b = bt[id];
    const values = { ...(d.values || {}) };
    Object.keys(b.values).forEach((p) => {
      if (Object.prototype.hasOwnProperty.call(values, p) || p in b.values) values[p] = b.values[p];
    });
    const tile = { ...(d.tile || {}), hasData: true, offline: !b.online };
    const v = b.values;
    if (d.type === "thermostat") {
      if ("temp" in v) {
        tile.temp = v.temp;
        tile.sensorFault = v.temp === null;
      }
      if ("target" in v) tile.target = v.target;
      if ("heating" in v) tile.heating = v.heating === true;
      if ("power" in v) tile.power = v.power !== false;
    } else if ("on" in v) {
      tile.on = v.on === true;
    }
    if ("level" in v && v.level !== null) tile.level = v.level;
    out[id] = { ...d, values, tile };
  });
  return out;
}

// Ekran termostatu (buildView) ze stanem z Bluetooth jednego urządzenia
export function applyBtView(view, b) {
  if (!b) return view;
  const v = { ...(view || {}), hasData: true, offline: !b.online, ago: b.online ? "przed chwilą" : (view && view.ago) || "" };
  const x = b.values;
  if ("temp" in x) {
    v.temp = x.temp;
    v.sensorFault = x.temp === null;
  }
  if ("target" in x && x.target !== null) v.target = x.target;
  if ("heating" in x) v.heating = x.heating === true;
  if ("power" in x) v.power = x.power !== false;
  if ("mode" in x && x.mode) v.mode = x.mode === "auto" ? "auto" : "manual";
  if ("override" in x) v.override = x.override === true;
  if ("comfortNow" in x) v.comfortNow = x.comfortNow === true;
  return v;
}

// Klucz polecenia wspólny dla obu dróg (pkt 15.4): "<id pilota>:<licznik>"
export function cmdKeyOf(cfg, counter) {
  return cfg ? cfg.id + ":" + counter : null;
}
