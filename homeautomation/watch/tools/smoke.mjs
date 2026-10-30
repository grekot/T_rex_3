// Smoke test prawdziwych bundli stron w Node vm (bez zegarka i symulatora).
//
// 1. Zbuduj z przechwyceniem bundli (PowerShell, z folderu homeautomation/watch):
//      $env:ZEUS_CAPTURE = "<pusty folder>"; $env:NODE_OPTIONS = "--require <ścieżka>/tools/capture-hook.cjs"
//      zeus build; $env:NODE_OPTIONS = ""
// 2. node tools/smoke.mjs <ten folder>
//
// Strony dostają atrapy modułów @zos/*, wspólny sztuczny zegar i timery. Komunikację zml
// (getApp().globalData.messaging) obsługuje udawany Side Service z prawdziwym utils/cloud.js
// na „bazie” home/u1/... w pamięci. Lista: kafelki, pokoje, przełączanie światła, wejście do
// termostatu (lista pod spodem nie odpytuje); termostat: − / +, tryb, ostrzeżenia, polecenia.
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import assert from "node:assert/strict";
import { poll, pollHome, pollAck, send, registerWatch, newCache } from "../utils/cloud.js";

const dir = process.argv[2];
if (!dir) {
  console.error("użycie: node tools/smoke.mjs <folder z bundlami>");
  process.exit(2);
}

const clock = { now: Date.UTC(2026, 9, 27, 16, 0) };
const log = { toasts: [], push: [], errors: [] };

const STATE = {
  id: "termostat-aaa",
  temp: 21.4,
  hum: 45,
  target: 21.0,
  heating: true,
  sensorFault: false,
  power: true,
  mode: "auto",
  override: false,
  comfortNow: true,
  nextChange: "22:30",
  outdoor: { temp: 4.2, icon: 69, age: 600 },
};

// „Baza”: urządzenia homes/h1/devices (tree), pokoje (rooms), pulpit tego zegarka (board,
// users/u1/watchDashboards/h1/8716545), zgłoszone zegarki (watches) i uprawnienia domownika u1 (access;
// dom należy do kogoś innego). Reguł nie sprawdzamy - to robi test/cloud.test.mjs.
const WATCH = "8716545";
let tree;
let rooms;
let board;
let access;
let scenes = null;
const watches = {};
function resetDb() {
  tree = {
    "termostat-aaa": {
      info: { type: "thermostat", name: "Termostat", api: 2 },
      config: { name: "Salon" },
      state: JSON.parse(JSON.stringify(STATE)),
      lastSeen: clock.now - 20000,
      history: {},
    },
  };
  rooms = null;
  board = null;
  access = { _all: "control" };
}
resetDb();

// homes/h1/deviceIndex jak go pisze aplikacja właściciela: {id: {type, name}}
function indexOf(devices) {
  const out = {};
  Object.keys(devices).forEach((id) => {
    const d = devices[id];
    out[id] = { type: (d.info && d.info.type) || "unknown", name: (d.config && d.config.name) || (d.info && d.info.name) || id };
  });
  return out;
}

const DB = "https://db.test";
async function fetchJson(req) {
  side.http.push(req.method + " " + req.url.slice(DB.length + 1).split(".json")[0]);
  const p = req.url.slice(DB.length + 1).split(".json")[0].split("/").map(decodeURIComponent);
  const root = {
    users: { u1: { homes: side.homes ? { h1: true } : null, watches, watchDashboards: { h1: { [WATCH]: board } } } },
    homes: { h1: { name: "Dom", ownerUid: "wlasciciel", access: { u1: access }, rooms, scenes, deviceIndex: indexOf(tree), devices: tree } },
  };
  if (req.headers && req.headers["X-HTTP-Method-Override"] === "PUT") {
    assert.deepEqual(p.slice(0, 3), ["users", "u1", "watches"]);
    watches[p[3]] = JSON.parse(req.body);
    return null;
  }
  if (req.method === "POST") {
    // polecenia: commands/{homeId}/{deviceId}; dla wygody testów trzymamy je przy urządzeniu
    assert.deepEqual(p.slice(0, 2), ["commands", "h1"]);
    const node = (tree[p[2]].commands = tree[p[2]].commands || {});
    const key = "-K" + ++side.pushes;
    node[key] = JSON.parse(req.body);
    assert.equal(node[key].by, "u1", "by = uid zalogowanej osoby");
    assert.equal(node[key].source, "watch");
    side.commands.push(node[key].values);
    return { name: key };
  }
  let node = root;
  for (const k of p) node = node && typeof node === "object" ? node[k] : undefined;
  if (node === undefined || node === null) return null;
  if (/shallow=true/.test(req.url)) return Object.keys(node).length ? Object.fromEntries(Object.keys(node).map((k) => [k, true])) : null;
  return JSON.parse(JSON.stringify(node));
}

// Udawany Side Service
const side = { homes: true, configured: true, loggedIn: true, online: true, cache: newCache(), http: [], commands: [], pushes: 0, requests: [] };
const callFns = new Set();
const messaging = {
  onCall(fn) {
    callFns.add(fn);
    return messaging;
  },
  onRequest() {
    return messaging;
  },
  offOnCall(fn) {
    callFns.delete(fn);
  },
  offOnRequest() {},
  call() {},
  request(data, opts) {
    const req = JSON.parse(JSON.stringify(data)); // inny realm
    side.requests.push({ ...req, timeout: opts && opts.timeout });
    if (!side.online) return Promise.reject(new Error("timeout"));
    if (!side.configured) return Promise.resolve({ ok: false, notConfigured: true, error: "Brak konfiguracji" });
    if (!side.loggedIn) return Promise.resolve({ ok: false, needsLogin: true, error: "Nie zalogowano" });
    const ctx = { fetchJson, db: DB, token: "tok", uid: "u1" };
    const p = req.params || {};
    if (req.method === "HOME") return pollHome({ ...ctx, wantedHome: null, watchId: p.watch, pending: p.pending, cache: side.cache, now: clock.now });
    if (req.method === "REGISTER") return registerWatch({ ...ctx, info: p.info, appVersion: p.app });
    if (req.method === "POLL") return poll({ ...ctx, homeId: p.home, id: p.id, pending: p.pending, now: clock.now });
    if (req.method === "ACK") return pollAck({ ...ctx, homeId: p.home, id: p.id, key: p.key, type: p.type, points: p.points, now: clock.now });
    if (req.method === "SET") return send({ ...ctx, homeId: p.home, id: p.id, values: p.values });
    return Promise.resolve({ ok: false, error: "?" });
  },
};
const globalData = { messaging };
const flush = async () => {
  for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r));
};

class FakeDate extends Date {
  constructor(...a) {
    super(...(a.length ? a : [clock.now]));
  }
  static now() {
    return clock.now;
  }
}

// Timery wspólne dla wszystkich stron (lista żyje pod ekranem termostatu)
const timers = [];
let timerId = 1;
async function run(ms) {
  const end = clock.now + ms;
  for (;;) {
    await flush();
    timers.sort((a, b) => a.at - b.at || a.id - b.id);
    const t = timers[0];
    if (!t || t.at > end) break;
    clock.now = t.at;
    if (t.every) t.at += t.every;
    else timers.shift();
    t.fn();
  }
  clock.now = end;
  await flush();
}

const ZML_MODULES = ["@zos/app", "@zos/ble", "@zos/i18n", "@zos/timer", "@zos/page"];
const BUNDLES = {
  home: fs.readFileSync(path.join(dir, "page_gt_home_index.page.js"), "utf8"),
  thermostat: fs.readFileSync(path.join(dir, "page_gt_thermostat_index.page.js"), "utf8"),
};

function makePage(name) {
  log.errors = [];
  const widgets = [];
  const owner = {};
  let keyCb = null;
  let pageOpts = null;

  function widget(type, props) {
    const w = {
      type,
      props: { ...props },
      visible: true,
      deleted: false,
      listeners: {},
      setProperty(p, v) {
        if (w.deleted) throw new Error("setProperty na usuniętym widżecie");
        if (p === "MORE") Object.assign(w.props, v);
        else if (p === "TEXT") w.props.text = v;
        else if (p === "VISIBLE") w.visible = !!v;
        else throw new Error("nieznana właściwość " + p);
      },
      addEventListener(ev, fn) {
        (w.listeners[ev] = w.listeners[ev] || []).push(fn);
      },
    };
    if (globalData.top && globalData.top !== name) log.errors.push(name + ": createWidget pod inną stroną");
    widgets.push(w);
    return w;
  }

  const modules = {
    "@zos/ui": {
      createWidget: widget,
      deleteWidget(w) {
        w.deleted = true;
        const i = widgets.indexOf(w);
        if (i >= 0) widgets.splice(i, 1);
      },
      widget: { FILL_RECT: "FILL_RECT", TEXT: "TEXT", CIRCLE: "CIRCLE", IMG: "IMG" },
      prop: { MORE: "MORE", TEXT: "TEXT", VISIBLE: "VISIBLE" },
      event: { CLICK_UP: "CLICK_UP", CLICK_DOWN: "CLICK_DOWN", MOVE_OUT: "MOVE_OUT" },
      align: { CENTER_H: "CH", CENTER_V: "CV", LEFT: "L", RIGHT: "R" },
      text_style: { NONE: "NONE", WRAP: "WRAP", ELLIPSIS: "ELLIPSIS" },
    },
    "@zos/device": {
      SCREEN_SHAPE_SQUARE: 1,
      SCREEN_SHAPE_ROUND: 2,
      getDeviceInfo: () => ({ width: 480, height: 480, screenShape: 2, deviceSource: 8716545, deviceName: "Amazfit T-Rex 3" }),
    },
    "@zos/utils": {
      px: (v) => v,
      log: { getLogger: () => ({ log() {}, debug() {}, info() {}, warn() {}, error() {} }) },
      EventBus: class {
        on() {}
        off() {}
        emit() {}
      },
    },
    "@zos/ble/TransferFile": class {
      constructor() {
        this.inbox = { on() {}, off() {}, getNextFile() {} };
        this.outbox = { enqueueFile() {} };
      }
    },
    "@zos/router": {
      push(o) {
        log.push.push({ url: o.url, params: o.params });
      },
    },
    "@zos/interaction": {
      KEY_UP: 36,
      KEY_DOWN: 37,
      KEY_SELECT: 38,
      KEY_EVENT_CLICK: 1,
      onKey(o) {
        keyCb = o.callback;
      },
      offKey() {
        keyCb = null;
      },
      showToast(o) {
        log.toasts.push(o.content);
      },
    },
    "@zos/display": { setWakeUpRelaunch() {}, setPageBrightTime() {} },
  };

  const G = {
    __$$R$$__(mod) {
      if (!modules[mod]) {
        if (!ZML_MODULES.includes(mod)) throw new Error("brak atrapy " + mod);
        return new Proxy({}, { get: () => () => undefined });
      }
      return modules[mod];
    },
    Page(opts) {
      pageOpts = opts;
      return opts;
    },
    __$$module$$__: {},
    setTimeout(fn, ms) {
      timers.push({ id: timerId, at: clock.now + (ms || 0), fn, every: 0, owner });
      return timerId++;
    },
    setInterval(fn, ms) {
      timers.push({ id: timerId, at: clock.now + ms, fn, every: ms, owner });
      return timerId++;
    },
    clearTimeout(id) {
      const i = timers.findIndex((t) => t.id === id);
      if (i >= 0) timers.splice(i, 1);
    },
    clearInterval(id) {
      G.clearTimeout(id);
    },
    Date: FakeDate,
    getApp: () => ({ _options: { globalData } }),
    console: {
      log(...a) {
        if (String(a[0]).includes("Mini Program Error") || String(a[0]).includes("error stack")) log.errors.push(a.join(" "));
      },
    },
  };
  const ctx = vm.createContext({
    DeviceRuntimeCore: { LifeCycle: {} },
    __$$hmAppManager$$__: { currentApp: { current: { __globals__: { __$$G$$__: G } } } },
    console: G.console,
    Math,
    JSON,
  });
  vm.runInContext(BUNDLES[name], ctx, { filename: name });
  assert.equal(log.errors.length, 0, log.errors.join("\n"));
  assert.ok(pageOpts, "Page() nie zostało wywołane");

  const fire = (w, ev) => (w.listeners[ev] || []).forEach((fn) => fn({}));
  const visibleTexts = () => widgets.filter((w) => w.type === "TEXT" && w.visible).map((w) => String(w.props.text));
  const page = {
    widgets,
    async start(params) {
      if (pageOpts.onInit) pageOpts.onInit.call(pageOpts, params);
      pageOpts.build.call(pageOpts);
      await flush();
      assert.equal(log.errors.length, 0, log.errors.join("\n"));
      return page;
    },
    run,
    call(msg) {
      callFns.forEach((fn) => fn(msg));
    },
    texts: visibleTexts,
    has(t) {
      return visibleTexts().some((x) => x.includes(t));
    },
    text(t) {
      return widgets.find((w) => w.type === "TEXT" && w.visible && String(w.props.text) === t);
    },
    textColor(t) {
      return page.text(t).props.color;
    },
    // termostat
    target() {
      return widgets.find((w) => w.type === "TEXT" && w.props.text_size === 58).props.text;
    },
    flameVisible() {
      return widgets.find((w) => w.type === "IMG").visible;
    },
    activeMode() {
      const seg = widgets.filter((w) => w.type === "FILL_RECT" && w.props.w === 140 && w.visible);
      assert.equal(seg.length, 1, "jeden aktywny segment");
      return seg[0].props.x < 240 ? "manual" : "auto";
    },
    // pulpit: kafelek po nazwie -> { name, size, value, sub, pill, ... } z widżetów wewnątrz jego tła
    tile(nameText) {
      const bgs = widgets.filter((w) => w.type === "FILL_RECT" && w.props.radius === 24);
      const within = (bg, w) =>
        w !== bg && w.props.x >= bg.props.x && w.props.y >= bg.props.y && w.props.x < bg.props.x + bg.props.w && w.props.y < bg.props.y + bg.props.h;
      const bg = bgs.find((b) => widgets.some((w) => w.type === "TEXT" && within(b, w) && String(w.props.text) === nameText && w.props.text_size <= 26));
      assert.ok(bg, "brak kafelka " + nameText + " wśród: " + visibleTexts().join(" | "));
      const inside = widgets.filter((w) => within(bg, w));
      const n = inside.find((w) => w.type === "TEXT" && String(w.props.text) === nameText);
      const pill = inside.find((w) => w.type === "FILL_RECT");
      const pillText = pill && inside.find((w) => w.type === "TEXT" && w !== n && w.props.x === pill.props.x && w.props.y === pill.props.y);
      const btn = (label) => inside.find((w) => w.type === "TEXT" && w.props.text === label);
      // znacznik ochrony termostatu: mały tekst (14-16 px) w prawym górnym rogu
      const badgeText = inside.find((w) => w.type === "TEXT" && w !== n && w.props.text_size <= 16);
      const texts = inside.filter(
        (w) => w.type === "TEXT" && w !== n && w !== pillText && w !== badgeText && w.visible && !["−", "+"].includes(w.props.text)
      );
      const value = texts.slice().sort((x, y) => y.props.text_size - x.props.text_size)[0];
      // linia opisu: najmniejszy tekst - także jedyny, gdy wartość ukrywa pigułka (opis ma 16-20 px)
      const smallest = texts.slice().sort((x, y) => x.props.text_size - y.props.text_size)[0];
      const sub = texts.length > 1 || (smallest && smallest.props.text_size <= 20) ? smallest : null;
      return {
        w: bg.props.w,
        h: bg.props.h,
        x: bg.props.x,
        y: bg.props.y,
        value: value ? String(value.props.text) : null,
        valueColor: value && value.props.color,
        sub: sub ? String(sub.props.text) : null,
        subColor: sub && sub.props.color,
        pill: pill && pill.visible ? String(pillText.props.text) : null,
        pillOn: !!pill && pill.props.color === 0xe67e00,
        pillPending: !!pillText && pillText.props.color !== 0xffffff,
        buttons: !!btn("+") && btn("+").visible,
        badge: badgeText ? String(badgeText.props.text) : null,
        tap: () => fire(n, "CLICK_UP"),
        tapPill: () => fire(pillText, "CLICK_UP"),
        press: (label) => fire(btn(label), "CLICK_UP"),
      };
    },
    tap(label) {
      const w = page.text(label);
      assert.ok(w, "brak napisu " + label + " wśród: " + visibleTexts().join(" | "));
      fire(w, "CLICK_DOWN");
      fire(w, "CLICK_UP");
    },
    // dotknięcie trafia i w koło, i w napis na nim
    tapBoth(label) {
      const t = page.text(label);
      const c = widgets.find((w) => w.type === "CIRCLE" && Math.abs(w.props.center_x - (t.props.x + t.props.w / 2)) < 2);
      fire(c, "CLICK_DOWN");
      fire(t, "CLICK_DOWN");
      fire(t, "CLICK_UP");
      fire(c, "CLICK_UP");
    },
    key(k) {
      assert.ok(keyCb, "strona nie słucha przycisków");
      return keyCb(modules["@zos/interaction"][k], 1);
    },
    destroy() {
      if (pageOpts.onDestroy) pageOpts.onDestroy.call(pageOpts);
      assert.equal(log.errors.length, 0, log.errors.join("\n"));
      return timers.filter((t) => t.owner === owner).length;
    },
  };
  return page;
}

const openThermostat = (level = "control") =>
  makePage("thermostat").start(JSON.stringify({ home: "h1", id: "termostat-aaa", name: "Salon", level }));

let failed = 0;
const tests = [];
function test(name, fn) {
  tests.push([name, fn]);
}
const count = (method) => side.requests.filter((r) => r.method === method).length;

// --- lista ---

test("lista: brak konfiguracji", async () => {
  side.configured = false;
  const p = await makePage("home").start();
  assert.ok(p.has("Brak konfiguracji"));
  side.configured = true;
  p.destroy();
});

test("lista: bez logowania -> komunikat, po zalogowaniu w ustawieniach od razu kafelki", async () => {
  side.loggedIn = false;
  const p = await makePage("home").start();
  assert.ok(p.has("Zaloguj się w aplikacji Zepp: Dom"));
  side.loggedIn = true;
  p.call({ type: "LOGGED_IN" });
  await run(10);
  assert.equal(p.tile("Salon").value, "21,4°");
  p.destroy();
});

test("lista: zgłoszenie zegarka, kafelek termostatu, odświeżanie co 5 s, po zamknięciu cisza", async () => {
  const registered = count("REGISTER");
  const p = await makePage("home").start();
  assert.deepEqual(watches[WATCH], {
    name: "Amazfit T-Rex 3",
    deviceSource: 8716545,
    width: 480,
    height: 480,
    shape: "round",
    app: "1.0.0",
    lastSeen: { ".sv": "timestamp" },
  });
  assert.ok(side.requests.some((r) => r.method === "HOME" && r.params.watch === WATCH), "pulpit tego zegarka");
  assert.ok(p.has("DOM"));
  const t = p.tile("Salon");
  assert.equal(t.value, "21,4°");
  assert.equal(t.sub, "nastawa 21,0° · grzeje");
  assert.equal(t.subColor, 0xff9100);
  assert.equal(t.pill, null);
  assert.ok(side.requests.every((r) => r.timeout === 15000), "własny limit czasu żądań");
  assert.ok(!side.http.some((h) => /history/.test(h)), "historii nie czytamy");
  const before = count("HOME");
  await run(15000);
  assert.ok(count("HOME") - before >= 2 && count("HOME") - before <= 3, "zapytań w 15 s: " + (count("HOME") - before));
  assert.equal(count("REGISTER") - registered, 1, "zgłoszenie raz na uruchomienie");
  assert.equal(p.destroy(), 0, "po zamknięciu żadnych timerów");
  const after = count("HOME");
  await run(20000);
  assert.equal(count("HOME"), after);
});

test("lista bez pulpitu: strona na pokój, światło przełączane jednym dotknięciem z potwierdzeniem", async () => {
  tree["swiatlo-0c4f21"] = { info: { type: "switch", name: "Sufit" }, state: { on: false }, lastSeen: clock.now };
  tree["swiatlo-77aa00"] = { info: { type: "dimmer", name: "Lampka" }, state: { on: true, level: 40 }, lastSeen: clock.now - 3600000 };
  rooms = { r1: { name: "Salon", order: 0, devices: ["swiatlo-0c4f21", "termostat-aaa"] } };
  side.cache = newCache();
  side.commands = [];
  const p = await makePage("home").start();
  const t = p.texts();
  assert.ok(t.indexOf("Salon") < t.indexOf("Sufit") && t.indexOf("Sufit") < t.lastIndexOf("Salon"), "kolejność z pokoju: " + t.join(" | "));
  assert.ok(p.has("Inne"));
  assert.equal(p.tile("Sufit").pill, "WYŁ");
  assert.equal(p.tile("Lampka").sub, "Brak kontaktu");
  // ikony domyślne: włącznik - zasilanie, ściemniacz - żarówka, termostat - termometr
  const icons = p.widgets.filter((w) => w.type === "IMG").map((w) => w.props.src);
  for (const src of ["icons/power.png", "icons/bulb.png", "icons/thermo.png"]) assert.ok(icons.includes(src), src + " w " + icons.join(","));
  const sufit = p.tile("Sufit");
  sufit.tap();
  sufit.tapPill();
  // do potwierdzenia: „WŁ…” na szarej pigułce i opis „wysyłanie…” / „czeka na urządzenie…”
  assert.equal(p.tile("Sufit").pill, "WŁ…");
  assert.ok(!p.tile("Sufit").pillOn, "nie wygląda na włączone przed potwierdzeniem");
  assert.ok(p.tile("Sufit").pillPending);
  assert.equal(p.tile("Sufit").sub, "wysyłanie…");
  await run(50);
  assert.equal(p.tile("Sufit").sub, "czeka na urządzenie…");
  assert.deepEqual(side.commands, [{ on: true }], "jedno polecenie mimo podwójnego trafienia");
  await run(2500);
  assert.equal(p.tile("Sufit").pill, "WŁ…", "stary stan nie cofa przełącznika");
  const key = Object.keys(tree["swiatlo-0c4f21"].commands)[0];
  tree["swiatlo-0c4f21"].lastCommand = { key, ok: true };
  tree["swiatlo-0c4f21"].state.on = true;
  log.toasts = [];
  const homeBefore = count("HOME");
  await run(1100);
  assert.equal(p.tile("Sufit").pill, "WŁ");
  assert.ok(p.tile("Sufit").pillOn);
  assert.equal(p.tile("Sufit").sub, "włączone");
  assert.ok(!p.tile("Sufit").pillPending, "potwierdzone szybkim pytaniem (ACK), bez czekania na obieg");
  assert.ok(p.has("Sufit: potwierdzone po"), p.texts().join(" | "));
  assert.equal(count("HOME"), homeBefore, "w czasie szybkiego pytania zwykły obieg czeka");
  assert.ok(count("ACK") >= 2);
  await run(5000);
  assert.deepEqual(log.toasts, [], "udane przełączenie bez komunikatu");
  p.tile("Sufit").tap();
  await run(50);
  assert.equal(p.tile("Sufit").pill, "WYŁ…");
  const key2 = Object.keys(tree["swiatlo-0c4f21"].commands)[1];
  tree["swiatlo-0c4f21"].lastCommand = { key: key2, ok: false, errors: { on: "forbidden" } };
  await run(5000);
  assert.deepEqual(log.toasts, ["Sufit: Brak uprawnień"]);
  assert.equal(p.tile("Sufit").pill, "WŁ");
  p.destroy();
});

test("lista -> termostat: lista pod spodem nie odpytuje i nie rysuje, po powrocie wraca", async () => {
  const p = await makePage("home").start();
  log.push = [];
  p.tile("Salon").tap();
  p.tile("Salon").tap();
  assert.equal(log.push.length, 1, "jedno otwarcie");
  assert.equal(log.push[0].url, "page/gt/thermostat/index.page");
  assert.deepEqual(JSON.parse(log.push[0].params), { home: "h1", id: "termostat-aaa", name: "Salon", level: "control" });
  const th = await openThermostat();
  const homeBefore = count("HOME");
  rooms = null; // zmiana składu listy w tym czasie
  side.cache = newCache();
  await run(12000);
  assert.equal(count("HOME"), homeBefore, "lista czeka");
  assert.ok(count("POLL") >= 2);
  assert.equal(th.destroy(), 0);
  await run(1500);
  assert.ok(count("HOME") > homeBefore, "po powrocie lista odświeża");
  assert.ok(!p.has("Inne"), "przebudowana lista bez pokoi");
  p.destroy();
});

test("lista: konto bez urządzeń", async () => {
  const saved = tree;
  tree = {};
  side.cache = newCache();
  const p = await makePage("home").start();
  assert.ok(p.has("nie ma jeszcze urządzeń w chmurze"), p.texts().join(" | "));
  p.destroy();
  tree = saved;
  delete tree["swiatlo-0c4f21"];
  delete tree["swiatlo-77aa00"];
  side.cache = newCache();
});

test("lista: osoba bez domu", async () => {
  side.homes = false;
  side.cache = newCache();
  const p = await makePage("home").start();
  assert.ok(p.has("Nie należysz do żadnego domu"));
  side.homes = true;
  side.cache = newCache();
  p.destroy();
});

test("pulpit zegarka: half / full / big, wartość, status, stepper − / +, scena, światło tylko do podglądu", async () => {
  tree["termostat-aaa"].describe = {
    type: "thermostat",
    points: [
      { key: "outdoor.temp", name: "Na zewnątrz", unit: "°C", decimals: 1 },
      { key: "target", name: "Nastawa", unit: "°C", decimals: 1, min: 15, max: 30, step: 0.5 },
      { key: "heating", name: "Grzanie" },
    ],
  };
  tree["swiatlo-1"] = { info: { type: "switch", name: "Sufit" }, state: { on: true }, lastSeen: clock.now };
  tree["swiatlo-2"] = { info: { type: "switch", name: "Lampka" }, state: { on: false }, lastSeen: clock.now };
  access = { _all: "control", "swiatlo-1": "view" };
  board = {
    watch: { width: 480, height: 480, shape: "round" },
    pages: [
      {
        title: "Wieczór",
        tiles: [
          { id: "t1", device: "termostat-aaa", view: "thermostat", size: "big", label: "Salon" },
          { id: "t2", device: "termostat-aaa", point: "outdoor.temp", view: "value", size: "half", label: "Dwór" },
          { id: "t3", device: "termostat-aaa", point: "heating", view: "status", size: "half", label: "Kocioł" },
          { id: "t4", device: "termostat-aaa", point: "target", view: "stepper", size: "full", label: "Nastawa" },
          { id: "t5", device: "swiatlo-1", point: "on", view: "toggle", size: "half" },
          { id: "t6", device: "swiatlo-2", point: "on", view: "toggle", size: "half" },
          { id: "t7", sceneId: "wyjscie", view: "scene", size: "full", label: "Wychodzę" },
        ],
      },
    ],
  };
  scenes = { wyjscie: { name: "Wyjście", actions: [{ device: "termostat-aaa", set: { mode: "manual" } }, { device: "swiatlo-1", set: { on: false } }] } };
  side.cache = newCache();
  side.commands = [];
  const p = await makePage("home").start();
  assert.ok(p.has("DOM"), "tytuł = nazwa domu");
  assert.ok(p.has("Wieczór"), "nagłówek strony");
  const big = p.tile("Salon");
  assert.equal(big.h, 186);
  assert.equal(big.value, "21,4°");
  assert.equal(big.sub, "nastawa 21,0° · grzeje");
  const dwor = p.tile("Dwór");
  const kociol = p.tile("Kocioł");
  assert.equal(dwor.y, kociol.y, "dwa half w jednym wierszu");
  assert.ok(dwor.x < kociol.x);
  assert.equal(dwor.value, "4,2°");
  assert.equal(kociol.value, "grzeje");
  // światło z dostępem view: stan bez przycisku, dotknięcie nic nie wysyła
  const sufit = p.tile("Sufit");
  assert.equal(sufit.pill, null);
  assert.equal(sufit.value, "WŁ");
  sufit.tap();
  assert.equal(p.tile("Lampka").pill, "WYŁ");
  // stepper: − / + w kafelku, jedno polecenie po 1 s
  const nastawa = p.tile("Nastawa");
  const pushesBefore = log.push.length;
  assert.ok(nastawa.buttons);
  assert.equal(nastawa.value, "21,0°");
  nastawa.press("+");
  await run(300);
  nastawa.press("+");
  assert.equal(p.tile("Nastawa").value, "22,0°");
  await run(900);
  assert.deepEqual(side.commands, [], "jeszcze dotyka");
  await run(200);
  assert.deepEqual(side.commands, [{ target: 22 }]);
  assert.equal(log.push.length, pushesBefore, "przycisk nie otwiera ekranu termostatu");
  // scena: tylko do urządzeń, którymi osoba steruje
  const scena = p.tile("Wychodzę");
  assert.equal(scena.pill, "▶");
  log.toasts = [];
  scena.tap();
  await run(50);
  assert.deepEqual(side.commands, [{ target: 22 }, { mode: "manual" }]);
  assert.deepEqual(log.toasts, ["Wychodzę: wysłano część (bez uprawnień do niektórych urządzeń)"]);
  p.destroy();
  for (const id of Object.keys(tree)) delete tree[id].commands;
  delete tree["swiatlo-1"];
  delete tree["swiatlo-2"];
  board = null;
  scenes = null;
  access = { _all: "control" };
  side.cache = newCache();
  resetDb();
});

test("pulpit zegarka: scena z hubem - jedno polecenie runScene do huba", async () => {
  tree["hub-1"] = { info: { type: "hub", name: "Hub" }, state: {}, lastSeen: clock.now };
  scenes = { wyjscie: { name: "Wyjście", actions: [{ device: "termostat-aaa", set: { mode: "auto" } }, { delay: 600 }] } };
  board = { pages: [{ title: "", tiles: [{ id: "s", sceneId: "wyjscie", view: "scene", size: "half" }] }] };
  side.cache = newCache();
  side.commands = [];
  const p = await makePage("home").start();
  const s = p.tile("Wyjście");
  assert.equal(s.pill, "▶");
  log.toasts = [];
  s.tap();
  await run(50);
  assert.deepEqual(side.commands, [{ runScene: "wyjscie" }]);
  assert.ok(tree["hub-1"].commands, "polecenie do huba");
  assert.deepEqual(log.toasts, ["Wyjście: wysłano"]);
  p.destroy();
  // bez huba: akcje do pierwszego „delay”, komunikat o reszcie
  delete tree["hub-1"];
  side.cache = newCache();
  side.commands = [];
  const q = await makePage("home").start();
  log.toasts = [];
  q.tile("Wyjście").tap();
  await run(50);
  assert.deepEqual(side.commands, [{ mode: "auto" }]);
  assert.deepEqual(log.toasts, ["Wyjście: wysłano część (opóźnienia wymagają huba)"]);
  q.destroy();
  board = null;
  scenes = null;
  side.cache = newCache();
  resetDb();
});

test("pulpit zegarka: kafelki w kole - żaden róg poza ekranem przy żadnym przewinięciu", async () => {
  const tiles = [];
  for (let i = 0; i < 8; i++) tiles.push({ id: "h" + i, device: "termostat-aaa", point: "temp", view: "value", size: i % 3 ? "half" : "full", label: "K" + i });
  board = { pages: [{ title: "Dużo", tiles }] };
  side.cache = newCache();
  const p = await makePage("home").start();
  const bgs = p.widgets.filter((w) => w.type === "FILL_RECT" && w.props.radius === 24);
  assert.equal(bgs.length, 8);
  const spacer = p.widgets.find((w) => w.type === "FILL_RECT" && w.props.color === 0 && w.props.w === 480);
  const height = spacer.props.y + spacer.props.h;
  const maxScroll = Math.max(0, height - 480);
  for (const b of bgs) {
    const { x, y, w, h } = b.props;
    // przewinięcie, przy którym kafelek jest najbliżej środka - tam musi się mieścić w kole
    const s = Math.min(maxScroll, Math.max(0, y + h / 2 - 240));
    for (const [cx, cy] of [
      [x, y - s],
      [x + w, y - s],
      [x, y + h - s],
      [x + w, y + h - s],
    ]) {
      assert.ok((cx - 240) ** 2 + (cy - 240) ** 2 <= 240 * 240 + 1, "róg poza kołem: " + JSON.stringify(b.props));
    }
  }
  p.destroy();
  board = null;
  side.cache = newCache();
});

// --- termostat ---

test("termostat: temperatura, płomień, nastawa, AUTO z „do HH:MM”, zewnątrz", async () => {
  const p = await openThermostat();
  assert.ok(p.has("Salon"));
  assert.ok(p.has("21,4°"));
  assert.equal(p.target(), "21,0°");
  assert.ok(p.flameVisible());
  assert.ok(p.has("na zewnątrz 4,2°"));
  assert.equal(p.activeMode(), "auto");
  assert.ok(p.has("komfort do 22:30"));
  assert.ok(!p.has("Brak kontaktu"));
  const before = count("POLL");
  await run(15000);
  assert.ok(count("POLL") - before >= 2 && count("POLL") - before <= 3);
  assert.equal(p.destroy(), 0);
});

test("termostat: + trzy razy -> jedno polecenie po 1 s, potwierdzenie, nowa nastawa", async () => {
  side.commands = [];
  const p = await openThermostat();
  p.tap("+");
  await run(300);
  p.tap("+");
  await run(300);
  p.tapBoth("+");
  assert.equal(p.target(), "22,5°");
  await run(900);
  assert.equal(side.commands.length, 0, "jeszcze dotyka");
  await run(200);
  assert.deepEqual(side.commands, [{ target: 22.5 }]);
  assert.ok(p.has("Czekam na termostat"));
  await run(2500);
  assert.equal(p.target(), "22,5°");
  const key = Object.keys(tree["termostat-aaa"].commands)[0];
  tree["termostat-aaa"].lastCommand = { key, ok: true, ts: clock.now };
  tree["termostat-aaa"].state.target = 22.5;
  tree["termostat-aaa"].state.override = true;
  log.toasts = [];
  await run(5000);
  assert.equal(log.toasts.length, 1);
  assert.match(log.toasts[0], /^Zapisano \(\d+,\d s\)$/, "potwierdzenie z czasem: " + log.toasts[0]);
  assert.equal(p.target(), "22,5°");
  assert.ok(p.has("nadpisane do 22:30"));
  assert.ok(!p.has("Czekam"));
  delete tree["termostat-aaa"].commands;
  p.destroy();
});

test("termostat: + i − z powrotem -> nic nie wysyła", async () => {
  side.commands = [];
  const p = await openThermostat();
  p.tap("+");
  await run(200);
  p.tap("−");
  await run(3000);
  assert.deepEqual(side.commands, []);
  p.destroy();
});

test("termostat: przyciski góra/dół, odrzucone polecenie wraca do bazy", async () => {
  side.commands = [];
  const p = await openThermostat();
  assert.equal(p.key("KEY_DOWN"), true);
  p.key("KEY_DOWN");
  assert.equal(p.key("KEY_SELECT"), false);
  assert.equal(p.target(), "21,5°");
  await run(1100);
  assert.deepEqual(side.commands, [{ target: 21.5 }]);
  const key = Object.keys(tree["termostat-aaa"].commands)[0];
  tree["termostat-aaa"].lastCommand = { key, ok: false, errors: { target: "range" }, ts: clock.now };
  log.toasts = [];
  await run(3000);
  assert.deepEqual(log.toasts, ["Błąd: nastawa poza zakresem"]);
  assert.equal(p.target(), "22,5°");
  delete tree["termostat-aaa"].commands;
  p.destroy();
});

test("termostat: RĘCZNY od razu, zebrana nastawa wysłana przed nim, brak potwierdzenia", async () => {
  side.commands = [];
  const p = await openThermostat();
  p.tap("+");
  p.tap("RĘCZNY");
  assert.equal(p.activeMode(), "manual");
  await run(50);
  assert.deepEqual(side.commands, [{ target: 23 }, { mode: "manual" }]);
  log.toasts = [];
  await run(36000);
  assert.ok(log.toasts.includes("Brak potwierdzenia"), log.toasts.join(","));
  assert.equal(p.activeMode(), "auto");
  assert.equal(p.target(), "22,5°");
  delete tree["termostat-aaa"].commands;
  p.destroy();
});

test("termostat: brak kontaktu i awaria czujnika (także na kafelku)", async () => {
  tree["termostat-aaa"].lastSeen = clock.now - 10 * 60000;
  const p = await openThermostat();
  assert.ok(p.has("Brak kontaktu · 10 min temu"));
  assert.ok(!p.flameVisible(), "grzanie nieznane");
  tree["termostat-aaa"].lastSeen = clock.now;
  tree["termostat-aaa"].state.temp = null;
  tree["termostat-aaa"].state.sensorFault = true;
  tree["termostat-aaa"].state.protect = "faultDuty";
  await run(5000);
  assert.ok(p.has("Awaria czujnika · grzanie awaryjne"));
  assert.ok(p.has("--,-°"));
  p.destroy();
  const h = await makePage("home").start();
  assert.equal(h.tile("Salon").sub, "Awaria czujnika");
  assert.equal(h.tile("Salon").subColor, 0xff5252);
  assert.equal(h.tile("Salon").badge, "AWARYJNIE", "znacznik ochrony na kafelku");
  tree["termostat-aaa"].state = { ...STATE, power: false, heating: true, temp: 6.5, protect: "frost" };
  await run(5000);
  assert.equal(h.tile("Salon").badge, "MRÓZ");
  assert.equal(h.tile("Salon").sub, "wyłączony · grzeje");
  h.destroy();
  resetDb();
});

test("termostat: dostęp view - bez − / + i bez zmiany trybu", async () => {
  side.commands = [];
  const p = await openThermostat("view");
  assert.ok(p.has("21,4°"));
  assert.ok(!p.has("+"), "przyciski ukryte");
  assert.equal(p.key("KEY_UP"), false, "przyciski zegarka wracają do systemu");
  p.tap("RĘCZNY");
  await run(1500);
  assert.deepEqual(side.commands, []);
  assert.equal(p.activeMode(), "auto");
  p.destroy();
});

test("termostat: telefon niedostępny", async () => {
  side.online = false;
  const p = await openThermostat();
  assert.ok(p.has("Brak połączenia z telefonem"));
  side.online = true;
  await run(5000);
  assert.ok(p.has("21,4°"));
  side.online = false;
  await run(5000);
  assert.ok(p.has("Telefon niedostępny"));
  assert.ok(p.has("21,4°"), "dane zostają");
  side.online = true;
  p.destroy();
});

for (const [name, fn] of tests) {
  try {
    globalData.top = undefined;
    await fn();
    await flush();
    console.log("ok   " + name);
  } catch (e) {
    failed++;
    console.error("BŁĄD " + name + "\n  " + (e.stack || e.message).split("\n").slice(0, 4).join("\n  "));
  }
  timers.length = 0;
}

if (failed) {
  console.error(failed + " test(y) nie przeszły");
  process.exit(1);
}
console.log("smoke: WSZYSTKO OK");
