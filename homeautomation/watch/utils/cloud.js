// Odczyt i polecenia w Realtime Database - kroki Side Service bez API Zepp (fetchJson wstrzykiwany,
// testy w test/cloud.test.mjs). fetchJson(request) zwraca sparsowaną odpowiedź albo rzuca
// Error z polem status. Ścieżki według API.md pkt 8.1, 12, 13a (users/{uid}/..., homes/{homeId}/...).
import { readRequest, writeRequest, devicePath, commandRequest, decodeDevices, pushKeyOf } from "./firebase.js";
import { buildView, ackResult } from "./termostat.js";
import { typeOf, tileView, arrangeDevices } from "./devices.js";
import {
  pickHome,
  levelOf,
  knownDeviceIds,
  watchPages,
  dashboardDevices,
  findHub,
  pickWatchDashboard,
  pagesFromRooms,
  pointValue,
  watchRecord,
  describePoint,
} from "./home.js";

export const LIST_TTL_MS = 60000; // domy, uprawnienia, pulpit, urządzenia i nazwy zmieniają się rzadko

export function newCache() {
  return { uid: null, wanted: null, watch: null, at: 0, ctx: null };
}

const str = (x) => (typeof x === "string" && x ? x : null);

// Wszystko, co zmienia się rzadko, z pamięcią na minutę:
// { homes: [{id, name}], homeId, homeName, owner, devices: {id: {type, name, level, info}}, rooms,
//   scenes, dashboard (pulpit tego zegarka albo null), describes: {id: describe} }
async function homeContext(fetchJson, db, token, uid, wantedHome, watchId, screen, cache, now) {
  if (cache.uid === uid && cache.wanted === wantedHome && cache.watch === watchId && now - cache.at < LIST_TTL_MS && cache.ctx) {
    return cache.ctx;
  }
  const read = (parts, shallow) => fetchJson(readRequest(db, token, parts, shallow));
  // węzły, do których osoba może nie mieć prawa (reguły zwracają wtedy błąd) - po prostu brak danych
  const quiet = (parts, shallow) => read(parts, shallow).catch(() => null);

  const homeIds = decodeDevices(await read(["users", uid, "homes"], true));
  const homeNames = await Promise.all(homeIds.map((h) => quiet(["homes", h, "name"])));
  const homes = homeIds.map((id, i) => ({ id, name: str(homeNames[i]) || id }));
  const homeId = pickHome(homeIds, wantedHome);
  let ctx = { homes, homeId: null };

  if (homeId) {
    const [ownerUid, access, rooms, scenes, board, index] = await Promise.all([
      quiet(["homes", homeId, "ownerUid"]),
      quiet(["homes", homeId, "access", uid]),
      quiet(["homes", homeId, "rooms"]),
      quiet(["homes", homeId, "scenes"]),
      // wszystkie pulpity zegarków tej osoby w tym domu - mały węzeł; wybór w pickWatchDashboard
      quiet(["users", uid, "watchDashboards", homeId]),
      // lista urządzeń dla wszystkich domowników: {id: {type, name}} (API.md pkt 12)
      quiet(["homes", homeId, "deviceIndex"]),
    ]);
    const owner = ownerUid === uid;
    const picked = pickWatchDashboard(board, watchId, screen);
    const dashboard = picked ? picked.dashboard : null;
    const indexed = index && typeof index === "object" ? index : null;
    // bez deviceIndex (starszy dom): właściciel czyta listę devices płytko; domownik zna tylko access, pokoje, pulpit
    let listed = indexed ? Object.keys(indexed) : null;
    if (!listed && owner) {
      const shallow = await quiet(["homes", homeId, "devices"], true);
      listed = shallow ? decodeDevices(shallow) : null;
    }
    const ids = knownDeviceIds(listed, access, rooms, dashboardDevices(dashboard));

    // urządzenia bez dostępu pomijamy; typ i nazwa z deviceIndex, a gdy ich tam brak - z samego urządzenia
    const devices = {};
    const visible = ids.filter((id) => levelOf(owner, access, id));
    const entry = (id) => (indexed && indexed[id] && typeof indexed[id] === "object" ? indexed[id] : {});
    const missing = visible.filter((id) => !str(entry(id).type) || !str(entry(id).name));
    const [infos, names] = await Promise.all([
      Promise.all(missing.map((id) => quiet(devicePath(homeId, id, "info")))),
      Promise.all(missing.map((id) => quiet(devicePath(homeId, id, "config/name")))),
    ]);
    visible.forEach((id) => {
      const e = entry(id);
      const i = missing.indexOf(id);
      const info = i !== -1 && infos[i] && typeof infos[i] === "object" ? infos[i] : str(e.type) ? { type: e.type } : null;
      devices[id] = {
        type: typeOf(info, null),
        name: str(e.name) || (i !== -1 && str(names[i])) || (info && str(info.name)) || id,
        level: levelOf(owner, access, id),
        icon: str(e.icon),
        info,
      };
    });

    // opis punktów (pkt 14: nazwa, jednostka, zakres) tylko dla urządzeń z kafelkami punktów
    const describes = {};
    if (dashboard) {
      const need = {};
      watchPages(dashboard, devices, scenes, findHub(devices)).forEach((page) =>
        page.items.forEach((it) => {
          if (it.point && it.kind !== "toggle") need[it.device] = true;
        })
      );
      const ds = Object.keys(need);
      const got = await Promise.all(ds.map((id) => quiet(devicePath(homeId, id, "describe"))));
      ds.forEach((id, i) => {
        if (got[i]) describes[id] = got[i];
      });
    }
    ctx = {
      homes,
      homeId,
      homeName: (homes.find((h) => h.id === homeId) || {}).name || homeId,
      owner,
      devices,
      rooms: rooms && typeof rooms === "object" ? rooms : null,
      scenes: scenes && typeof scenes === "object" ? scenes : null,
      dashboard,
      dashboardKey: picked ? picked.key : null,
      indexed: listed ? listed.length : 0,
      describes,
    };
  }
  cache.uid = uid;
  cache.wanted = wantedHome;
  cache.watch = watchId;
  cache.at = now;
  cache.ctx = ctx;
  return ctx;
}

// Strony z kafelkami: pulpit tego zegarka (pkt 13a) albo, bez niego, urządzenia według pokoi
function buildPages(ctx, devices) {
  if (ctx.dashboard) {
    const pages = watchPages(ctx.dashboard, devices, ctx.scenes, findHub(devices)).map((page) => ({
      ...page,
      items: page.items.map((it) => {
        if (!it.point || it.kind === "toggle") return it;
        const p = describePoint(ctx.describes[it.device], it.point) || {};
        const spec = { unit: p.unit || "", decimals: typeof p.decimals === "number" ? p.decimals : null, pointName: p.name || it.point };
        if (it.kind === "stepper") Object.assign(spec, { min: p.min, max: p.max, step: p.step });
        return { ...it, ...spec };
      }),
    }));
    if (pages.length) return pages;
  }
  const ids = Object.keys(devices);
  const names = {};
  ids.forEach((id) => {
    names[id] = devices[id].name;
  });
  return pagesFromRooms(arrangeDevices(ids, ctx.rooms, names), devices);
}

// Ekran listy: { ok, homes, homeId, title, custom, pages: [{title, items}], devices: {id: {type, name, level,
// tile, values, ack}} } albo { ok, homes, noHome }. watchId = deviceSource zegarka; pending = {id: klucz}.
export async function pollHome({ fetchJson, db, token, uid, wantedHome, watchId, screen, pending, cache, now }) {
  const ctx = await homeContext(fetchJson, db, token, uid, wantedHome, watchId || null, screen || null, cache, now);
  if (!ctx.homeId) return { ok: true, homes: ctx.homes, noHome: true };
  const waiting = pending && typeof pending === "object" ? pending : {};

  // stan czytamy tylko dla urządzeń, które są na ekranie
  const shown = {};
  buildPages(ctx, ctx.devices).forEach((p) =>
    p.items.forEach((it) => {
      if (it.device) shown[it.device] = true;
    })
  );
  const ids = Object.keys(shown);
  const rows = await Promise.all(
    ids.map((id) => {
      const get = (node) => fetchJson(readRequest(db, token, devicePath(ctx.homeId, id, node)));
      return Promise.all([get("state").catch(() => null), get("lastSeen").catch(() => null), waiting[id] ? get("lastCommand").catch(() => null) : null]);
    })
  );
  const devices = {};
  const states = {};
  ids.forEach((id, i) => {
    const [state, lastSeen, lastCommand] = rows[i];
    const d = ctx.devices[id];
    const type = d.type !== "unknown" ? d.type : typeOf(d.info, state);
    states[id] = state;
    devices[id] = {
      type,
      name: d.name,
      level: d.level,
      icon: d.icon,
      tile: tileView(type, state, lastSeen, now),
      values: {},
      ack: waiting[id] ? ackResult(lastCommand, waiting[id]) : null,
    };
  });
  // typy rozpoznane ze stanu mogą zmienić rodzaj kafelka
  const pages = buildPages(ctx, { ...ctx.devices, ...devices });
  // do zegarka idą tylko punkty potrzebne kafelkom, nie cały stan
  pages.forEach((p) =>
    p.items.forEach((it) => {
      if (it.point && devices[it.device]) devices[it.device].values[it.point] = pointValue(states[it.device], it.point);
    })
  );
  return {
    ok: true,
    homes: ctx.homes,
    homeId: ctx.homeId,
    title: ctx.homeName,
    custom: pages.some((p) => p.items.some((it) => it.key.indexOf("t:") === 0)),
    // do opisu pustego ekranu i diagnostyki (który pulpit, ile urządzeń w chmurze / z dostępem)
    diag: {
      homeName: ctx.homeName,
      dashboard: ctx.dashboardKey,
      dashboardTiles: ctx.dashboard ? dashboardDevices(ctx.dashboard).length : 0,
      indexed: ctx.indexed,
      visible: Object.keys(ctx.devices).length,
    },
    pages,
    devices,
  };
}

// Zgłoszenie zegarka (pkt 13a) przy uruchomieniu aplikacji -> { ok, watchId }
export async function registerWatch({ fetchJson, db, token, uid, info, appVersion }) {
  const rec = watchRecord(info, appVersion);
  if (!rec) return { ok: false, error: "Brak danych zegarka" };
  await fetchJson(writeRequest(db, token, ["users", uid, "watches", rec.id], rec.body));
  return { ok: true, watchId: rec.id };
}

// Ekran termostatu: { ok, id, view, ack }
export async function poll({ fetchJson, db, token, homeId, id, pending, now }) {
  const get = (node) => fetchJson(readRequest(db, token, devicePath(homeId, id, node)));
  const [state, config, lastSeen, lastCommand] = await Promise.all([
    get("state"),
    get("config").catch(() => null),
    get("lastSeen"),
    pending ? get("lastCommand") : Promise.resolve(null),
  ]);
  return { ok: true, id, view: buildView(state, config, lastSeen, now), ack: pending ? ackResult(lastCommand, pending) : null };
}

// Polecenie Set (pkt 7, 10) z "by": uid -> { ok, key } (klucz porównujemy później z lastCommand.key)
export async function send({ fetchJson, db, token, uid, homeId, id, values }) {
  const key = pushKeyOf(await fetchJson(commandRequest(db, token, homeId, id, values, uid)));
  if (!key) throw new Error("Brak klucza polecenia");
  return { ok: true, key };
}
