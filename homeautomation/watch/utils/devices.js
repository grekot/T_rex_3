// Lista urządzeń domu (API.md pkt 0, 8.1, 8.3, 10): typ, kafelek, kolejność według pokoi.
// Bez API zegarka; testy w test/devices.test.mjs.
import { isOffline, agoText, formatTemp } from "./termostat.js";

const num = (x) => (typeof x === "number" && isFinite(x) ? x : null);
const obj = (x) => (x && typeof x === "object" && !Array.isArray(x) ? x : null);

// Typ z info.type; starsze wpisy bez info - po polach stanu
export function typeOf(info, state) {
  const i = obj(info);
  if (i && typeof i.type === "string" && i.type) return i.type;
  const st = obj(state);
  if (st && ("target" in st || "temp" in st)) return "thermostat";
  if (st && "on" in st) return "level" in st ? "dimmer" : "switch";
  return "unknown";
}

export function isSwitchable(type) {
  return type === "switch" || type === "dimmer";
}

// state + lastSeen -> mały obiekt kafelka (liczy go Side Service czasem telefonu)
export function tileView(type, state, lastSeen, now) {
  const st = obj(state);
  const base = { type, hasData: !!st, offline: isOffline(lastSeen, now), ago: agoText(lastSeen, now) };
  if (!st) return base;
  if (type === "thermostat") {
    const temp = num(st.temp);
    return {
      ...base,
      temp,
      target: num(st.target),
      heating: st.heating === true,
      sensorFault: st.sensorFault === true || temp === null,
      power: st.power !== false,
      protect: st.protect === "frost" || st.protect === "faultDuty" ? st.protect : null,
    };
  }
  if (isSwitchable(type)) return { ...base, on: st.on === true, level: num(st.level) };
  return base;
}

// Mały znacznik ochrony na kafelku termostatu (State.protect, API.md pkt 5) albo null
const BADGES = { frost: { text: "MRÓZ", alert: false }, faultDuty: { text: "AWARYJNIE", alert: true } };

// Teksty kafelka. on = stan na ekranie (może już uwzględniać dotknięcie, zanim urządzenie potwierdzi).
// { value, sub, alert (czerwone sub), heating (pomarańczowe sub), on (dla włączników), badge (termostat) }
export function tileText(tile, on) {
  const t = tile || {};
  const offline = t.hasData && t.offline;
  if (t.type === "thermostat") {
    const badge = (t.hasData && !offline && BADGES[t.protect]) || null;
    if (!t.hasData) return { value: "--,-°", sub: "brak danych w chmurze", alert: false, heating: false, badge };
    if (offline) return { value: formatTemp(t.temp), sub: "Brak kontaktu", alert: true, heating: false, badge };
    if (t.sensorFault) return { value: "--,-°", sub: "Awaria czujnika", alert: true, heating: !!t.heating, badge };
    if (!t.power) return { value: formatTemp(t.temp), sub: "wyłączony" + (t.heating ? " · grzeje" : ""), alert: false, heating: !!t.heating, badge };
    return {
      value: formatTemp(t.temp),
      sub: "nastawa " + formatTemp(t.target) + (t.heating ? " · grzeje" : ""),
      alert: false,
      heating: t.heating,
      badge,
    };
  }
  if (isSwitchable(t.type)) {
    const isOn = on === undefined ? t.on === true : on;
    if (!t.hasData) return { value: "", sub: "brak danych w chmurze", alert: false, heating: false, on: false };
    let sub = isOn ? "włączone" : "wyłączone";
    if (isOn && t.type === "dimmer" && t.level !== null && t.level !== undefined) sub = "jasność " + t.level + "%";
    if (offline) sub = "Brak kontaktu";
    return { value: isOn ? "WŁ" : "WYŁ", sub, alert: !!offline, heating: false, on: isOn };
  }
  return { value: "", sub: "nieobsługiwane urządzenie", alert: false, heating: false };
}

// Sekcje listy: pokoje według order (potem nazwy), urządzenia w kolejności z pokoju; reszta na końcu
// („Inne”, gdy są pokoje). rooms = {roomId: {name, order, devices:[ids]}}, names = {id: nazwa}.
export function arrangeDevices(ids, rooms, names) {
  const known = {};
  (ids || []).forEach((id) => {
    known[id] = true;
  });
  const nameOf = (id) => String((names && names[id]) || id);
  const used = {};
  const sections = [];
  const list = Object.keys(obj(rooms) || {})
    .map((key) => ({ key, room: obj(rooms[key]) || {} }))
    .sort((a, b) => {
      const oa = num(a.room.order);
      const ob = num(b.room.order);
      if (oa !== ob) return (oa === null ? 1e9 : oa) - (ob === null ? 1e9 : ob);
      return String(a.room.name || a.key).localeCompare(String(b.room.name || b.key));
    });
  list.forEach(({ key, room }) => {
    const devs = (Array.isArray(room.devices) ? room.devices : obj(room.devices) ? Object.values(room.devices) : []).filter(
      (id) => known[id] && !used[id]
    );
    devs.forEach((id) => {
      used[id] = true;
    });
    if (devs.length) sections.push({ room: String(room.name || key), ids: devs });
  });
  const rest = (ids || []).filter((id) => !used[id]).sort((a, b) => nameOf(a).localeCompare(nameOf(b)));
  if (rest.length) sections.push({ room: sections.length ? "Inne" : null, ids: rest });
  return sections;
}
