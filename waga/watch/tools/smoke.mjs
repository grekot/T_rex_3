// Smoke test prawdziwych bundli zeusa w Node vm (bez zegarka i symulatora).
//
// 1. Zbuduj z przechwyceniem bundli (PowerShell, z folderu waga/watch):
//      $env:ZEUS_CAPTURE = "<pusty folder>"; $env:NODE_OPTIONS = "--require <ścieżka>/tools/capture-hook.cjs"
//      zeus build; $env:NODE_OPTIONS = ""
// 2. node tools/smoke.mjs <ten folder>
//
// Każda strona dostaje atrapy modułów @zos/*, sztuczny zegar i timery; test naciska −/+,
// przytrzymuje, zapisuje i sprawdza plik waga.json. Komunikację zml (getApp().globalData.messaging)
// obsługuje udawany Side Service z prawdziwym planem scalania (utils/weight.js) i zapisem
// Firestore (utils/firestore.js) na „chmurze” w pamięci.
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import assert from "node:assert/strict";
import { syncPlan } from "../utils/weight.js";
import { wagaWrites } from "../utils/firestore.js";

const dir = process.argv[2];
if (!dir) {
  console.error("użycie: node tools/smoke.mjs <folder z bundlami>");
  process.exit(2);
}

// Zegar w czasie lokalnym UTC+2; getTimezoneOffset() zwraca 0 jak (być może) na zegarku
const TZ_MS = 2 * 3600000;
const clock = { now: Date.UTC(2026, 9, 23, 7, 0) - TZ_MS }; // pt 23.10, 7:00 lokalnie
const files = new Map();
const log = { push: [], toasts: [], buzz: 0, errors: [] };

// Udawany Side Service + Firestore: cloud = mapa e z dokumentu waga/{uid}
const side = { loggedIn: false, online: true, cloud: {}, commits: [], requests: 0 };
let callFn = null; // onCall strony (np. LOGGED_IN z ustawień)
const messaging = {
  onCall(fn) {
    callFn = fn;
    return messaging;
  },
  onRequest() {
    return messaging;
  },
  offOnCall() {
    callFn = null;
  },
  offOnRequest() {},
  call() {},
  request(data) {
    side.requests++;
    const req = JSON.parse(JSON.stringify(data)); // inny realm
    return new Promise((resolve, reject) => {
      if (!side.online) return reject(new Error("timeout"));
      if (req.method !== "SYNC") return resolve({ ok: false, error: "?" });
      if (!side.loggedIn) return resolve({ ok: false, needsLogin: true, error: "Nie zalogowano" });
      const plan = syncPlan(req.params.e, side.cloud);
      if (plan.push.length) {
        side.commits.push(wagaWrites("proj", "u1", plan.push, clock.now)[0]);
        plan.push.forEach((x) => {
          side.cloud[x.d] = { w: x.w, t: x.t };
        });
      }
      resolve({ ok: true, apply: plan.apply });
    });
  },
};
const flush = () => new Promise((r) => setImmediate(r));

class FakeDate extends Date {
  constructor(...a) {
    super(...(a.length ? a : [clock.now]));
  }
  static now() {
    return clock.now;
  }
  getTimezoneOffset() {
    return 0;
  }
}

function local() {
  return new Date(clock.now + TZ_MS);
}

const ZML_MODULES = ["@zos/app", "@zos/ble", "@zos/i18n", "@zos/timer", "@zos/page"];

function makePage(file) {
  log.errors = [];
  const widgets = [];
  const timers = [];
  let timerId = 1;
  let keyCb = null;
  let pageOpts = null;

  function widget(type, props) {
    const w = {
      type,
      props: { ...props },
      listeners: {},
      setProperty(p, v) {
        if (p === "MORE") Object.assign(w.props, v);
        else if (p === "TEXT") w.props.text = v;
        else throw new Error("nieznana właściwość " + p);
      },
      addEventListener(ev, fn) {
        (w.listeners[ev] = w.listeners[ev] || []).push(fn);
      },
    };
    widgets.push(w);
    return w;
  }

  const modules = {
    "@zos/ui": {
      createWidget: widget,
      widget: { FILL_RECT: "FILL_RECT", TEXT: "TEXT", CIRCLE: "CIRCLE" },
      prop: { MORE: "MORE", TEXT: "TEXT" },
      event: { CLICK_UP: "CLICK_UP", CLICK_DOWN: "CLICK_DOWN", MOVE_OUT: "MOVE_OUT" },
      align: { CENTER_H: "CH", CENTER_V: "CV", LEFT: "L", RIGHT: "R" },
      text_style: { NONE: "NONE" },
    },
    "@zos/device": { getDeviceInfo: () => ({ width: 480, height: 480 }) },
    "@zos/utils": {
      px: (v) => v,
      // zml: logger i EventBus
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
        log.push.push(o.url);
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
    "@zos/display": { setWakeUpRelaunch() {} },
    "@zos/fs": {
      readFileSync(o) {
        if (!files.has(o.path)) throw new Error("brak pliku");
        return files.get(o.path);
      },
      writeFileSync(o) {
        files.set(o.path, String(o.data));
      },
    },
    "@zos/sensor": {
      VIBRATOR_SCENE_SHORT_MIDDLE: 2,
      // systemowy zegar zna datę lokalną (miesiąc 1-12)
      Time: class {
        getFullYear() {
          return local().getUTCFullYear();
        }
        getMonth() {
          return local().getUTCMonth() + 1;
        }
        getDate() {
          return local().getUTCDate();
        }
      },
      Vibrator: class {
        setMode() {}
        start() {
          log.buzz++;
        }
        stop() {}
      },
    },
  };

  const G = {
    __$$R$$__(name) {
      // zml (BasePage) przy ładowaniu sięga po @zos/app, @zos/ble, @zos/i18n, @zos/timer... -
      // tych funkcji strona nie używa, wystarczą puste
      if (!modules[name]) {
        if (!ZML_MODULES.includes(name)) throw new Error("brak atrapy " + name);
        return new Proxy({}, { get: () => () => undefined });
      }
      return modules[name];
    },
    Page(opts) {
      pageOpts = opts;
      return opts;
    },
    __$$module$$__: {},
    setTimeout(fn, ms) {
      timers.push({ id: timerId, at: clock.now + (ms || 0), fn, every: 0 });
      return timerId++;
    },
    setInterval(fn, ms) {
      timers.push({ id: timerId, at: clock.now + ms, fn, every: ms });
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
    getApp: () => ({ _options: { globalData: { messaging } } }),
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
  vm.runInContext(fs.readFileSync(path.join(dir, file), "utf8"), ctx, { filename: file });
  assert.equal(log.errors.length, 0, file + ": " + log.errors.join("\n"));
  assert.ok(pageOpts, file + ": Page() nie zostało wywołane");

  const fire = (w, ev) => (w.listeners[ev] || []).forEach((fn) => fn({}));
  const page = {
    widgets,
    start() {
      if (pageOpts.onInit) pageOpts.onInit.call(pageOpts);
      pageOpts.build.call(pageOpts);
      return page;
    },
    run(ms) {
      const end = clock.now + ms;
      for (;;) {
        timers.sort((a, b) => a.at - b.at || a.id - b.id);
        const t = timers[0];
        if (!t || t.at > end) break;
        clock.now = t.at;
        if (t.every) t.at += t.every;
        else timers.shift();
        t.fn();
      }
      clock.now = end;
    },
    texts() {
      return widgets.filter((w) => w.type === "TEXT").map((w) => String(w.props.text));
    },
    text(t) {
      return widgets.find((w) => w.type === "TEXT" && String(w.props.text) === t);
    },
    has(t) {
      return page.texts().some((x) => x.includes(t));
    },
    value() {
      return page.texts().find((x) => /^\d+,\d$/.test(x));
    },
    // stuknięcie w napis (−, +, ZAPISZ...): dotknięcie i puszczenie
    press(label, holdMs = 0) {
      const w = page.text(label);
      assert.ok(w, "brak napisu " + label);
      fire(w, "CLICK_DOWN");
      if (holdMs) page.run(holdMs);
      fire(w, "CLICK_UP");
    },
    // dotknięcie trafia i w koło, i w napis na nim
    pressBoth(label) {
      const t = page.text(label);
      const c = widgets.find((w) => w.type === "CIRCLE" && Math.abs(w.props.center_x - (t.props.x + t.props.w / 2)) < 2);
      fire(c, "CLICK_DOWN");
      fire(t, "CLICK_DOWN");
      fire(t, "CLICK_UP");
      fire(c, "CLICK_UP");
    },
    tapBar(i) {
      const bars = widgets.filter((w) => w.type === "FILL_RECT" && w.props.w < 20);
      fire(bars[i], "CLICK_UP");
    },
    bars() {
      return widgets.filter((w) => w.type === "FILL_RECT" && w.props.w < 20);
    },
    key(k) {
      assert.ok(keyCb, "strona nie słucha przycisków");
      return keyCb(modules["@zos/interaction"][k], 1);
    },
    destroy() {
      if (pageOpts.onDestroy) pageOpts.onDestroy.call(pageOpts);
      return timers.length;
    },
  };
  return page;
}

const HOME = "page_gt_home_index.page.js";
const HISTORY = "page_gt_history_index.page.js";
const data = () => JSON.parse(files.get("waga.json"));

let failed = 0;
const tests = [];
function test(name, fn) {
  tests.push([name, fn]);
}

test("pierwsze uruchomienie: 80,0, + trzy razy, zapis", () => {
  const p = makePage(HOME).start();
  assert.equal(p.value(), "80,0");
  assert.ok(p.has("pt 23.10"));
  assert.ok(p.has("pierwszy pomiar"));
  assert.ok(p.has("ZAPISZ"));
  p.press("+");
  p.press("+");
  p.press("+");
  assert.equal(p.value(), "80,3");
  p.press("ZAPISZ");
  assert.deepEqual(data().e.map((x) => x.d + ":" + x.w), ["2026-10-23:803"]);
  assert.ok(files.has("waga.bak"));
  assert.ok(p.has("ZAPISANO"));
  assert.equal(log.buzz, 1);
  p.press("ZAPISANO"); // drugi raz nic nie robi
  assert.equal(log.buzz, 1);
  assert.equal(p.destroy(), 0);
});

test("ten sam dzień: start od zapisanej wagi, zmiana -> POPRAW nadpisuje", () => {
  const p = makePage(HOME).start();
  assert.equal(p.value(), "80,3");
  assert.ok(p.has("ZAPISANO"));
  p.press("−");
  assert.equal(p.value(), "80,2");
  p.press("POPRAW");
  assert.deepEqual(data().e.map((x) => x.d + ":" + x.w), ["2026-10-23:802"]);
  p.destroy();
});

test("następny dzień: start od ostatniego pomiaru, przytrzymanie przyspiesza i staje po puszczeniu", () => {
  clock.now += 86400000;
  const p = makePage(HOME).start();
  assert.ok(p.has("sb 24.10"));
  assert.equal(p.value(), "80,2");
  assert.ok(p.has("±0,0 kg od wczoraj"));
  assert.ok(p.has("ZAPISZ"));
  p.press("−", 2000);
  const after = p.value();
  const steps = 802 - Number(after.replace(",", ""));
  assert.ok(steps > 15 && steps < 60, "kroków przy 2 s: " + steps);
  p.run(2000);
  assert.equal(p.value(), after, "po puszczeniu waga dalej się zmienia");
  assert.ok(p.has("kg od wczoraj"));
  p.destroy();
});

test("dotknięcie trafiające w koło i napis = jeden krok", () => {
  const p = makePage(HOME).start();
  const v = Number(p.value().replace(",", ""));
  p.pressBoth("+");
  assert.equal(Number(p.value().replace(",", "")), v + 1);
  p.destroy();
});

test("przyciski zegarka góra/dół", () => {
  const p = makePage(HOME).start();
  const v = Number(p.value().replace(",", ""));
  assert.equal(p.key("KEY_UP"), true);
  p.key("KEY_UP");
  p.key("KEY_DOWN");
  assert.equal(Number(p.value().replace(",", "")), v + 1);
  assert.equal(p.key("KEY_SELECT"), false);
  p.destroy();
});

test("zapis z ekranu otwartego przez północ trafia na nowy dzień", () => {
  clock.now = Date.UTC(2026, 9, 24, 23, 59) - TZ_MS;
  const p = makePage(HOME).start();
  p.press("+");
  p.run(120000);
  assert.ok(p.has("nd 25.10"));
  p.press("ZAPISZ");
  assert.ok(data().e.some((x) => x.d === "2026-10-25"));
  p.destroy();
});

test("wykres: 14 słupków, dzisiejszy pomarańczowy, stuknięcie -> historia", () => {
  const p = makePage(HOME).start();
  const bars = p.bars();
  assert.equal(bars.length, 14);
  assert.equal(bars[13].props.color, 0xff9100);
  p.tapBar(5);
  p.tapBar(6); // podwójne stuknięcie nie otwiera dwóch historii
  assert.deepEqual(log.push, ["page/gt/history/index.page"]);
  p.destroy();
});

test("historia: zmiany w okresach i wiersze od najnowszego", () => {
  const p = makePage(HISTORY).start();
  assert.ok(p.has("Historia"));
  assert.ok(p.has("7 dni:"));
  const t = p.texts();
  assert.ok(t.indexOf("nd 25.10") < t.indexOf("pt 23.10"), "kolejność wierszy");
  assert.ok(p.has("80,2"));
});

test("historia bez pomiarów", () => {
  const saved = new Map(files);
  files.clear();
  const p = makePage(HISTORY).start();
  assert.ok(p.has("Brak pomiarów"));
  for (const [k, v] of saved) files.set(k, v);
});

test("uszkodzony plik: odczyt z kopii .bak", () => {
  const good = files.get("waga.json");
  files.set("waga.json", "{zepsute");
  const p = makePage(HOME).start();
  assert.notEqual(p.value(), "80,0");
  assert.ok(!p.has("pierwszy pomiar"));
  files.set("waga.json", good);
  p.destroy();
});

// --- synchronizacja z telefonem (zml -> Side Service -> Firestore) ---

function todayLocal() {
  const d = local();
  const two = (n) => (n < 10 ? "0" : "") + n;
  return d.getUTCFullYear() + "-" + two(d.getUTCMonth() + 1) + "-" + two(d.getUTCDate());
}
const LOGIN_HINT = "Zaloguj: Zepp → Waga → ustawienia";

test("synchronizacja bez logowania: podpowiedź, nic nie wysłane", async () => {
  side.loggedIn = false;
  const p = makePage(HOME).start();
  await flush();
  assert.ok(p.has(LOGIN_HINT));
  assert.equal(side.commits.length, 0);
  p.destroy();
});

test("logowanie w ustawieniach (LOGGED_IN): wysyła wszystkie dni z maską pól", async () => {
  const p = makePage(HOME).start();
  await flush();
  side.loggedIn = true;
  assert.ok(callFn, "strona nie słucha onCall");
  callFn({ type: "LOGGED_IN" });
  await flush();
  assert.equal(side.commits.length, 1);
  const days = data().e.map((x) => x.d);
  assert.deepEqual(side.commits[0].updateMask.fieldPaths, days.map((d) => "e.`" + d + "`").concat(["updatedAt", "v"]));
  assert.deepEqual(Object.keys(side.cloud).sort(), days);
  assert.ok(!p.has(LOGIN_HINT), "podpowiedź zostaje po zalogowaniu");
  p.destroy();
});

test("poprawka z telefonu: nowszy dzisiejszy wpis podmienia wagę na ekranie", async () => {
  clock.now += 1000; // nowszy niż zapis z zegarka
  side.cloud[todayLocal()] = { w: 777, t: clock.now };
  clock.now += 1000;
  const before = side.commits.length;
  const p = makePage(HOME).start();
  await flush();
  assert.equal(p.value(), "77,7");
  assert.ok(p.has("ZAPISANO"));
  assert.equal(data().e.find((x) => x.d === todayLocal()).w, 777);
  assert.equal(side.commits.length, before, "nic do wysłania");
  p.destroy();
});

test("usunięcie na telefonie: nagrobek chowa dzień, zostaje w pliku", async () => {
  side.cloud["2026-10-23"] = { w: 0, t: clock.now };
  clock.now += 1000;
  const p = makePage(HOME).start();
  await flush();
  p.destroy();
  assert.equal(data().e.find((x) => x.d === "2026-10-23").w, 0);
  const h = makePage(HISTORY).start();
  assert.ok(!h.has("pt 23.10"));
  assert.ok(h.has("nd 25.10"));
});

test("zmiana z telefonu nie nadpisuje wagi, którą użytkownik właśnie ustawia; POPRAW wysyła jeden dzień", async () => {
  const p = makePage(HOME).start();
  await flush();
  p.press("+");
  assert.equal(p.value(), "77,8");
  side.cloud[todayLocal()] = { w: 700, t: clock.now };
  callFn({ type: "LOGGED_IN" });
  await flush();
  assert.equal(p.value(), "77,8");
  assert.ok(p.has("POPRAW"));
  p.run(1000);
  const before = side.commits.length;
  p.press("POPRAW");
  await flush();
  assert.equal(side.commits.length, before + 1);
  assert.deepEqual(side.commits[before].updateMask.fieldPaths, ["e.`" + todayLocal() + "`", "updatedAt", "v"]);
  assert.equal(side.cloud[todayLocal()].w, 778);
  assert.ok(p.has("ZAPISANO"));
  p.destroy();
});

test("telefon niedostępny: komunikat, dane lokalne bez zmian", async () => {
  side.online = false;
  const p = makePage(HOME).start();
  await flush();
  assert.ok(p.has("Telefon niedostępny"));
  assert.equal(p.value(), "77,8");
  side.online = true;
  p.destroy();
});

for (const [name, fn] of tests) {
  try {
    await fn();
    await flush();
    console.log("ok   " + name);
  } catch (e) {
    failed++;
    console.error("BŁĄD " + name + "\n  " + (e.stack || e.message).split("\n").slice(0, 4).join("\n  "));
  }
}

if (failed) {
  console.error(failed + " test(y) nie przeszły");
  process.exit(1);
}
console.log("smoke: WSZYSTKO OK");
