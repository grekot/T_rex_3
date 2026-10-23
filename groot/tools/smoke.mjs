// Smoke test prawdziwych bundli zeusa w Node vm (bez zegarka i symulatora).
//
// 1. Zbuduj z przechwyceniem bundli (PowerShell, z folderu groot):
//      $env:ZEUS_CAPTURE = "<pusty folder>"; $env:NODE_OPTIONS = "--require <ścieżka>/tools/capture-hook.cjs"
//      zeus build; $env:NODE_OPTIONS = ""
// 2. node tools/smoke.mjs <ten folder>
//
// Każda strona dostaje atrapy modułów @zos/*, sztuczny zegar i timery; test klika widżety,
// naciska przyciski i podaje odczyty akcelerometru, a potem sprawdza stan w LocalStorage.
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import assert from "node:assert/strict";

const dir = process.argv[2];
if (!dir) {
  console.error("użycie: node tools/smoke.mjs <folder z bundlami>");
  process.exit(2);
}

// --- wspólne atrapy ----------------------------------------------------------------

// Zegar w czasie lokalnym UTC+2: Date.UTC(...) poniżej to godziny lokalne minus TZ_MS
const TZ_MS = 2 * 3600000;
const clock = { now: Date.UTC(2026, 9, 21, 9, 0) - TZ_MS }; // 9:00 lokalnie
const storageMap = new Map(); // "plik" LocalStorage
const files = new Map(); // /data aplikacji (@zos/fs)
const log = { push: [], back: 0, toasts: [], buzz: [], display: [], errors: [], alarms: [], cancels: [] };
let accelReading = { x: 0, y: 0, z: 980 };
let vibrateAt = -1e12;
const VIBRATION_SHAKE_MS = 450;
// "zły" zegarek: drgania dłużej i nieregularnie (co trzeci odczyt spokojny), jak przy
// wędkowaniu na T-Rex 3, gdzie wyciszanie po wibracji nie wystarczało
let shake = { ms: VIBRATION_SHAKE_MS, gaps: false };
// kompas (null = nieskalibrowany), barometr (m), GPS (null = szuka)
const sensors = { heading: 0, altitude: 220, fix: { lat: 50.0614, lon: 19.9366 }, steps: 0 };

class FakeDate extends Date {
  constructor(...a) {
    super(...(a.length ? a : [clock.now]));
  }
  static now() {
    return clock.now;
  }
  getTimezoneOffset() {
    return 0; // jak (być może) na zegarku - strefa musi przyjść z sensora Time
  }
}

function makePage(file) {
  const widgets = [];
  const timers = [];
  let timerId = 1;
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
        if (p === "MORE") Object.assign(w.props, v);
        else if (p === "VISIBLE") w.visible = !!v;
        else throw new Error("nieznana właściwość " + p);
      },
      getProperty(p) {
        return w.props[p];
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
      deleteWidget(w) {
        w.deleted = true;
      },
      widget: { FILL_RECT: "FILL_RECT", IMG: "IMG", TEXT: "TEXT", ARC: "ARC", CIRCLE: "CIRCLE" },
      prop: { MORE: "MORE", VISIBLE: "VISIBLE" },
      event: { CLICK_UP: "CLICK_UP", CLICK_DOWN: "CLICK_DOWN" },
      align: { CENTER_H: "CH", CENTER_V: "CV", LEFT: "L" },
      text_style: { NONE: "NONE", WRAP: "WRAP" },
    },
    "@zos/device": { getDeviceInfo: () => ({ width: 480, height: 480 }) },
    "@zos/utils": { px: (v) => v },
    "@zos/router": {
      push(o) {
        log.push.push(o.url);
      },
      back() {
        log.back++;
      },
    },
    "@zos/interaction": {
      KEY_UP: 36,
      KEY_DOWN: 37,
      KEY_SELECT: 38,
      KEY_SHORTCUT: 39,
      KEY_BACK: 8,
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
    // Złośliwa atrapa: każda instancja ma własną kopię danych z chwili utworzenia
    // i przy zapisie nadpisuje całość (tak mógł działać zegarek, gdy światło wracało)
    "@zos/storage": {
      LocalStorage: class {
        constructor() {
          this.copy = new Map(storageMap);
        }
        getItem(k) {
          return this.copy.has(k) ? this.copy.get(k) : undefined;
        }
        setItem(k, v) {
          this.copy.set(k, String(v));
          storageMap.clear();
          for (const [a, b] of this.copy) storageMap.set(a, b);
        }
      },
    },
    "@zos/fs": {
      readFileSync(o) {
        if (!files.has(o.path)) return undefined;
        const v = files.get(o.path);
        if (o.options && o.options.encoding) return v;
        return new TextEncoder().encode(v).buffer;
      },
      writeFileSync(o) {
        files.set(o.path, String(o.data));
      },
    },
    "@zos/sensor": {
      FREQ_MODE_HIGH: 2,
      VIBRATOR_SCENE_SHORT_LIGHT: 1,
      VIBRATOR_SCENE_SHORT_MIDDLE: 2,
      VIBRATOR_SCENE_DURATION: 3,
      VIBRATOR_SCENE_NOTIFICATION: 4,
      VIBRATOR_SCENE_SHORT_STRONG: 5,
      Compass: class {
        onChange() {}
        offChange() {}
        start() {}
        stop() {}
        getStatus() {
          return sensors.heading !== null;
        }
        getDirectionAngle() {
          return sensors.heading === null ? "INVALID" : sensors.heading;
        }
      },
      // kroki z całego dnia (podróż Milano, utils/galaxy.js)
      Step: class {
        getCurrent() {
          return sensors.steps;
        }
        getTarget() {
          return 8000;
        }
        onChange() {}
        offChange() {}
      },
      Barometer: class {
        onChange() {}
        offChange() {}
        getAltitude() {
          return sensors.altitude;
        }
      },
      Geolocation: class {
        start() {}
        stop() {}
        onChange() {}
        offChange() {}
        getStatus() {
          return sensors.fix ? "A" : "V";
        }
        getLatitude(o) {
          return o.format === "DD" ? Math.abs(sensors.fix.lat) : { direction: sensors.fix.lat < 0 ? "S" : "N" };
        }
        getLongitude(o) {
          return o.format === "DD" ? Math.abs(sensors.fix.lon) : { direction: sensors.fix.lon < 0 ? "W" : "E" };
        }
      },
      Accelerometer: class {
        setFreqMode() {}
        onChange() {}
        offChange() {}
        start() {}
        stop() {}
        getCurrent() {
          // wibracja zegarka trzęsie akcelerometrem (tak było na T-Rex 3: Refleks i
          // Wędkowanie zaliczały "reakcję" bez ruchu ręki)
          // drgania na wszystkich osiach, dłużej niż sama wibracja (silniczek wyhamowuje)
          if (clock.now - vibrateAt < shake.ms && !(shake.gaps && Math.floor(clock.now / 40) % 3 === 2)) {
            const k = Math.floor(clock.now / 40) % 2 ? 1 : -1;
            return { x: accelReading.x + k * 1500, y: accelReading.y - k * 1200, z: accelReading.z + k * 600 };
          }
          return { ...accelReading };
        }
      },
      // systemowy zegar zna godzinę lokalną; w teście strefa = +2 h (jak w Polsce latem)
      Time: class {
        getHours() {
          return new Date(clock.now + TZ_MS).getUTCHours();
        }
        getMinutes() {
          return new Date(clock.now + TZ_MS).getUTCMinutes();
        }
      },
      Vibrator: class {
        setMode(m) {
          this.m = m;
        }
        start() {
          log.buzz.push(this.m);
          vibrateAt = clock.now;
        }
        stop() {}
      },
    },
    "@zos/alarm": {
      set(o) {
        log.alarms.push(o);
        return 40 + log.alarms.length;
      },
      cancel(id) {
        log.cancels.push(id);
        return 0;
      },
    },
    "@zos/display": {
      setPageBrightTime: () => log.display.push("bright"),
      resetPageBrightTime: () => log.display.push("resetBright"),
      pauseDropWristScreenOff: () => log.display.push("pause"),
      resetDropWristScreenOff: () => log.display.push("resetWrist"),
    },
  };

  const G = {
    __$$R$$__(name) {
      if (!modules[name]) throw new Error("brak atrapy " + name);
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

  const page = {
    opts: pageOpts,
    widgets,
    start(params) {
      if (pageOpts.onInit) pageOpts.onInit.call(pageOpts, params);
      pageOpts.build.call(pageOpts, params);
      return page;
    },
    // przesuwa sztuczny zegar, odpalając timery po kolei
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
      return widgets.filter((w) => w.type === "TEXT" && w.visible && !w.deleted).map((w) => w.props.text);
    },
    hasText(t) {
      return page.texts().some((x) => String(x).includes(t));
    },
    imgs() {
      return widgets.filter((w) => w.type === "IMG" && w.visible && !w.deleted).map((w) => w.props.src);
    },
    find(pred) {
      return widgets.find((w) => !w.deleted && pred(w));
    },
    tap(w) {
      assert.ok(w, "brak widżetu do stuknięcia");
      assert.ok((w.listeners.CLICK_UP || []).length, "widżet nie reaguje na stuknięcie: " + JSON.stringify(w.props));
      w.listeners.CLICK_UP.forEach((fn) => fn({}));
    },
    tapText(t) {
      page.tap(page.find((w) => w.type === "TEXT" && String(w.props.text).includes(t)));
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

function pet() {
  return JSON.parse(files.get("groot_state.json"));
}
function setPet(fn) {
  const s = pet();
  fn(s);
  files.set("groot_state.json", JSON.stringify(s));
  files.set("groot_state.bak", JSON.stringify(s));
}

let failed = 0;
function test(name, fn) {
  try {
    fn();
    console.log("ok   " + name);
  } catch (e) {
    failed++;
    console.error("BŁĄD " + name + "\n  " + (e.stack || e.message).split("\n").slice(0, 4).join("\n  "));
  }
}

// --- scenariusze ---------------------------------------------------------------------

test("app.js się ładuje", () => {
  const ctx = vm.createContext({ App: () => {}, console: { log() {} } });
  vm.runInContext(fs.readFileSync(path.join(dir, "app.js"), "utf8"), ctx);
});

test("stan z wersji 1.0.0 (LocalStorage) przechodzi do pliku", () => {
  const old = { v: 1, gen: 3, rng: 5, t: clock.now - 60000, born: clock.now - 86400000, hatched: clock.now - 86000000, form: "grocik", stageAt: clock.now - 3600000, hunger: 3, happy: 3, discipline: 1, weight: 12, poops: 0, poopAt: 0, sick: 0, asleep: false, light: true, lightMiss: false, timers: { hunger: 100, happy: 100, poop: 100, whim: 300 }, calls: { hunger: 0, happy: 0, sick: 0, light: 0 }, due: { hunger: 0, happy: 0, sick: 0, light: 0 }, whim: 0, mistakes: 0, totalMistakes: 0, neglect: 0, gone: "", goneAt: 0, seen: ["kielek", "grocik"], history: [] };
  storageMap.set("groot_state", JSON.stringify(old));
  const p = makePage("page_gt_home_index.page.js").start();
  assert.equal(pet().gen, 3);
  assert.equal(pet().form, "grocik");
  p.destroy();
  storageMap.clear();
  files.clear();
});

test("ekran główny: nowe jajo, wyklucie, karmienie, przyciski", () => {
  const p = makePage("page_gt_home_index.page.js").start();
  assert.equal(pet().form, "egg");
  assert.ok(p.imgs().includes("pet/egg/egg0.png"), p.imgs().join(","));
  assert.ok(p.hasText("Nowy patyczek!"));
  p.run(400);
  assert.equal(log.push.pop(), "page/gt/choose/index.page", "pierwsze uruchomienie: wybór jajka");
  p.run(4 * 60000);
  assert.equal(pet().form, "kielek");
  assert.ok(p.imgs().some((s) => s.startsWith("pet/kielek/")), p.imgs().join(","));
  assert.ok(p.hasText("Kiełek"));
  // pierścień: 8 ikon, pierwsza wybrana
  const ring = p.widgets.filter((w) => w.type === "IMG" && String(w.props.src).startsWith("ring/"));
  assert.equal(ring.length, 8);
  assert.equal(ring[0].props.src, "ring/meal_sel.png");
  const hunger = pet().hunger;
  p.tap(ring[0]);
  assert.equal(pet().hunger, hunger + 1);
  // wynik akcji przetrwa zamknięcie i ponowne otwarcie (inne strony, inne instancje pamięci)
  const reopened = makePage("page_gt_home_index.page.js").start();
  assert.equal(pet().hunger, hunger + 1);
  reopened.destroy();
  assert.ok(p.hasText("Glug glug!"));
  assert.ok(p.imgs().some((s) => /\/eat[01]\.png$/.test(s)), p.imgs().join(","));
  // przyciski: w dół = następna ikona, wybór = akcja, skrót zostaje dla systemu
  assert.equal(p.key("KEY_SHORTCUT"), false);
  p.key("KEY_DOWN");
  assert.equal(ring[1].props.src, "ring/snack_sel.png");
  assert.equal(ring[0].props.src, "ring/meal.png");
  assert.equal(p.key("KEY_BACK"), false, "inne przyciski zostają dla systemu");
  const happy = pet().happy;
  p.key("KEY_SELECT");
  assert.equal(pet().happy, Math.min(4, happy + 1));
  p.key("KEY_UP");
  p.key("KEY_UP");
  assert.equal(ring[7].props.src, "ring/stats_sel.png");
  p.key("KEY_SELECT");
  assert.equal(log.push.pop(), "page/gt/stats/index.page");
  p.tap(ring[3]);
  assert.equal(log.push.pop(), "page/gt/games/index.page");
  // za wcześnie na spanie
  p.tap(ring[2]);
  assert.ok(p.hasText("Jeszcze nie pora spać"));
  p.run(3000);
  // kupa się pojawia i znika po sprzątnięciu
  setPet((s) => {
    s.poops = 2;
    s.poopAt = s.t;
  });
  p.run(1100);
  assert.equal(p.imgs().filter((s) => s === "ui/poop.png").length, 2);
  p.tap(ring[5]);
  assert.equal(pet().poops, 0);
  assert.equal(p.imgs().filter((s) => s === "ui/poop.png").length, 0);
  // stuknięcie w drzewko
  p.tap(p.find((w) => w.type === "IMG" && String(w.props.src).startsWith("pet/")));
  p.run(60000);
  assert.equal(p.destroy(), 0, "zostały timery po zamknięciu");
});

test("ekran główny: noc, zgaszone światło, odejście i nowe jajo", () => {
  setPet((s) => {
    s.form = "groot";
    s.stageAt = s.t - 5 * 86400000;
    s.hunger = 4;
    s.happy = 4;
    s.poops = 0;
    s.sick = 0;
    s.weight = 30;
    s.timers = { hunger: 2000, happy: 2000, poop: 2000, whim: 2000, ask: 5000 };
    s.request = null;
  });
  clock.now += 11 * 3600000 + 30 * 60000; // 20:30
  const p = makePage("page_gt_home_index.page.js").start();
  assert.ok(p.hasText("Ziewa"), p.texts().join("|"));
  const light = p.widgets.filter((w) => w.type === "IMG" && String(w.props.src).startsWith("ring/"))[2];
  p.tap(light);
  assert.equal(pet().asleep, true);
  assert.equal(pet().light, false);
  // drugie naciśnięcie (np. przycisk przy wychodzeniu) nie zapala światła
  p.key("KEY_DOWN");
  p.key("KEY_UP");
  p.tap(light);
  assert.equal(pet().light, false);
  p.run(1000);
  assert.ok(p.imgs().some((s) => /groot\/dark[01]\.png$/.test(s)), p.imgs().join(","));
  assert.ok(p.imgs().includes("ui/zzz.png"));
  // tło sceny w wersji nocnej (dorosły Groot: Knowhere)
  assert.ok(p.imgs().includes("ui/bg_knowhere_n.png"), p.imgs().join(","));
  p.destroy();
  // po ponownym otwarciu o 23:00 dalej śpi przy zgaszonym świetle
  clock.now += 2.5 * 3600000;
  const again = makePage("page_gt_home_index.page.js").start();
  assert.equal(pet().light, false);
  assert.equal(pet().asleep, true);
  assert.ok(again.hasText("Zzz"), again.texts().join("|"));
  again.destroy();

  // ktoś zapomniał o nim na tydzień
  clock.now += 7 * 86400000;
  const q = makePage("page_gt_home_index.page.js").start();
  assert.equal(pet().gone, "forest");
  assert.ok(q.imgs().includes("ui/forest.png"));
  assert.ok(q.hasText("Stuknij: nowy"));
  q.tap(q.find((w) => w.type === "IMG" && w.props.src === "ui/forest.png"));
  assert.equal(log.push.pop(), "page/gt/choose/index.page");
  // wybór: niebieskie jajo (roślinożercy), imię o dwa dalej
  const ch = makePage("page_gt_choose_index.page.js").start("egg");
  assert.ok(ch.hasText("Wybierz doniczkę"));
  assert.ok(ch.imgs().includes("ui/egg_bloom.png"));
  ch.tap(ch.find((w) => w.props.src === "ui/egg_bloom.png"));
  assert.ok(ch.hasText("Pąk → Kwiatuś → Wisienka → Sakura"), ch.texts().join("|"));
  const backs = log.back;
  ch.tapText("Dalej");
  assert.ok(ch.hasText("bez imienia"), ch.texts().join("|"));
  const arrowR = ch.find((w) => w.props.src === "ui/arrow_r.png");
  assert.equal(arrowR.visible, true);
  ch.tap(arrowR);
  ch.tap(arrowR);
  assert.ok(ch.hasText("Grucio"));
  ch.tapText("Gotowe");
  assert.equal(log.back, backs + 1);
  assert.equal(pet().form, "egg");
  assert.equal(pet().gen, 2);
  assert.equal(pet().line, "bloom");
  assert.equal(pet().name, "Grucio");
  assert.ok(pet().seen.includes("kielek"));
  ch.destroy();
  // ekran główny łapie zmianę: niebieskie jajo i imię w tytule
  q.run(1100);
  assert.ok(q.imgs().some((x) => x.startsWith("pet/eggb/")), q.imgs().join(","));
  assert.ok(q.hasText("Grucio"), q.texts().join("|"));
  assert.ok(q.imgs().includes("ui/bg_kokpit.png"), q.imgs().join(","));
  assert.ok(q.imgs().includes("ring/meal_sel.png"), q.imgs().join(","));
  q.run(4 * 60000);
  assert.equal(pet().form, "pak");
  assert.ok(q.hasText("Grucio"), q.texts().join("|"));
  assert.ok(q.hasText("Podlewanie"), q.texts().join("|"));
  q.destroy();
});

test("zmiana imienia ze statystyk (przyciski)", () => {
  const ch = makePage("page_gt_choose_index.page.js").start("name");
  assert.ok(ch.hasText("Imię"));
  assert.ok(ch.hasText("Grucio"));
  assert.equal(ch.find((w) => w.props.src === "ui/egg_classic.png").visible, false);
  ch.key("KEY_DOWN");
  ch.key("KEY_SELECT");
  assert.equal(pet().name, "Patyk");
  assert.equal(pet().line, "bloom");
  ch.destroy();
});

function hatchAdult() {
  setPet((s) => {
    Object.assign(s, { form: "wisienka", hatched: s.t - 86400000, stageAt: s.t, hunger: 4, happy: 2, weight: 26, asleep: false, light: true, sick: 0 });
  });
}

test("przypomnienie: alarm przy wyjściu, wibracja, gdy alarm otworzy aplikację", () => {
  files.delete("groot_alarm.json");
  setPet((s) => {
    Object.assign(s, { form: "groot", hatched: s.t - 3 * 86400000, stageAt: s.t, hunger: 4, happy: 4, poops: 0, sick: 0, asleep: false, light: true, whim: 0, gone: "" });
    s.timers = { hunger: 2000, happy: 2000, poop: 90, whim: 2000 };
  });
  clock.now = Date.UTC(2026, 9, 25, 10, 0) - TZ_MS;
  setPet((s) => (s.t = clock.now));
  const p = makePage("page_gt_home_index.page.js").start();
  const buzzBefore = log.buzz.length;
  p.destroy();
  const a = log.alarms.pop();
  assert.ok(a, "nie ustawiono alarmu");
  assert.equal(a.url, "page/gt/home/index.page");
  assert.equal(a.time, Math.floor((Date.UTC(2026, 9, 25, 11, 30) - TZ_MS) / 1000));
  assert.equal(a.store, true);
  clock.now = a.time * 1000 + 20000;
  const q = makePage("page_gt_home_index.page.js").start();
  assert.ok(log.buzz.length > buzzBefore, "brak wibracji");
  assert.ok(q.hasText("Groot cię woła!"), q.texts().join("|"));
  assert.ok(q.imgs().includes("ui/poop.png"));
  assert.ok(log.cancels.length > 0);
  q.destroy();
  // zwykłe otwarcie (nie o porze alarmu) nie wibruje
  clock.now += 5 * 60000;
  const n = log.buzz.length;
  makePage("page_gt_home_index.page.js").start().destroy();
  assert.equal(log.buzz.length, n);
});

test("statystyki i kolekcja", () => {
  hatchAdult();
  const p = makePage("page_gt_stats_index.page.js").start();
  // dorosły chodzi sam: zamiast kropli wody słoneczka energii
  assert.ok(p.hasText("Energia"), p.texts().join("|"));
  assert.equal(p.imgs().filter((s) => s === "ui/sunpt.png").length, 4);
  assert.equal(p.imgs().filter((s) => s === "ui/heart.png").length, 2 + pet().discipline);
  assert.ok(p.hasText("Wisienka"), p.texts().join("|"));
  assert.ok(p.hasText("Waga 26 g"), p.texts().join("|"));
  assert.ok(p.hasText("Patyk · Wisienka"), p.texts().join("|"));
  p.tapText("Imię");
  assert.equal(log.push.pop(), "page/gt/choose/index.page");
  p.tapText("Kolekcja");
  assert.equal(log.push.pop(), "page/gt/collection/index.page");
  p.destroy();
  const c = makePage("page_gt_collection_index.page.js").start();
  assert.ok(c.hasText("Kolekcja 2/18"), c.texts().join("|"));
  assert.equal(c.imgs().filter((x) => x.startsWith("thumb/")).length, 18);
  assert.ok(c.imgs().includes("thumb/kielek.png"));
  assert.ok(c.imgs().includes("thumb/groot_x.png"));
  c.tap(c.find((w) => w.props.src === "thumb/kielek.png"));
  assert.ok(c.hasText("Kiełek · klasyczny"), c.texts().join("|"));
  c.tap(c.find((w) => w.props.src === "thumb/groot_x.png"));
  assert.ok(c.hasText("???"));
  c.destroy();
});

test("menu zabaw", () => {
  const p = makePage("page_gt_games_index.page.js").start();
  ["Rzut Orbem", "Kołysanie do snu", "Balans na belce", "Lewo czy prawo?"].forEach((t, i) => {
    p.tapText(t);
    assert.equal(log.push.pop(), "page/gt/" + ["throw", "rock", "balance", "guess"][i] + "/index.page");
  });
});

function screenRestored() {
  const d = log.display.slice();
  log.display.length = 0;
  assert.ok(d.includes("pause") && d.includes("resetWrist"), "ekran: " + d.join(","));
  assert.ok(d.lastIndexOf("resetWrist") > d.lastIndexOf("pause"));
}

test("rzut piłką: machnięcia o sile pasującej do celu wygrywają", () => {
  hatchAdult();
  const before = pet();
  const backs = log.back;
  const p = makePage("page_gt_throw_index.page.js").start();
  const game = () => p.opts.state.game;
  for (let i = 0; i < 3 && !game().done; i++) {
    p.run(1500);
    // odwrotność throwDistance: siła, która da odległość celu
    const target = game().targets[game().round];
    const peak = 600 + ((target - 8) / 92) * 2600;
    accelReading = { x: Math.sqrt((peak + 980) ** 2 - 980 * 980), y: 0, z: 980 };
    p.run(120);
    accelReading = { x: 0, y: 0, z: 980 };
    p.run(1000);
  }
  p.run(2500);
  assert.equal(game().done, true);
  assert.equal(game().win, true, JSON.stringify(game()));
  assert.ok(p.hasText("Wygrana!"));
  assert.equal(pet().happy, before.happy + 1);
  assert.equal(pet().weight, before.weight - 1);
  p.tapText("Wróć");
  assert.equal(log.back, backs + 1);
  assert.equal(p.destroy(), 0);
  screenRestored();
});

test("kołysanie: delikatne bujanie usypia", () => {
  const p = makePage("page_gt_rock_index.page.js").start();
  const t0 = clock.now;
  for (let i = 0; i < 600 && !p.opts.state.rocker.state.done; i++) {
    const a = ((15 * Math.PI) / 180) * Math.sin((2 * Math.PI * (clock.now - t0)) / 1600);
    accelReading = { x: 980 * Math.sin(a), y: 0, z: 980 * Math.cos(a) };
    p.run(40);
  }
  assert.equal(p.opts.state.rocker.state.win, true);
  assert.ok(p.hasText("Wygrana!"));
  p.destroy();
  screenRestored();
});

test("kołysanie: potrząsanie budzi i przegrywa", () => {
  const p = makePage("page_gt_rock_index.page.js").start();
  for (let i = 0; i < 1000 && !p.opts.state.rocker.state.done; i++) {
    accelReading = { x: i % 2 ? 1600 : -1600, y: 0, z: 980 };
    p.run(40);
  }
  assert.equal(p.opts.state.rocker.state.win, false);
  assert.ok(p.hasText("Tym razem nie"));
  assert.ok(log.buzz.length > 0);
  p.destroy();
  screenRestored();
});

test("balans: gracz kontrujący przechyłem wygrywa, bez reakcji spada", () => {
  const win = makePage("page_gt_balance_index.page.js").start();
  accelReading = { x: 0, y: 0, z: 980 };
  win.run(700); // kalibracja
  for (let i = 0; i < 600 && !win.opts.state.ball.done; i++) {
    const b = win.opts.state.ball;
    const tilt = -0.6 * b.pos - 0.3 * b.vel; // w g, dodatni = z górki w prawo
    accelReading = { x: -tilt * 980, y: 0, z: 980 };
    win.run(40);
  }
  assert.equal(win.opts.state.ball.win, true);
  assert.ok(win.hasText("Wygrana!"));
  win.destroy();
  screenRestored();

  const lose = makePage("page_gt_balance_index.page.js").start();
  accelReading = { x: 0, y: 0, z: 980 };
  lose.run(700);
  accelReading = { x: -200, y: 0, z: 980 }; // stały przechył w prawo
  lose.run(16000);
  assert.equal(lose.opts.state.ball.win, false);
  assert.ok(lose.hasText("Spadł"));
  lose.destroy();
  screenRestored();
});

test("lewo czy prawo: trafienia strzałkami i przyciskami", () => {
  const p = makePage("page_gt_guess_index.page.js").start();
  const g = () => p.opts.state.game;
  const arrows = {
    left: p.find((w) => w.props.src === "ui/arrow_l.png"),
    right: p.find((w) => w.props.src === "ui/arrow_r.png"),
  };
  p.tap(arrows[g().dirs[0]]);
  p.run(1200);
  p.key(g().dirs[1] === "left" ? "KEY_UP" : "KEY_DOWN");
  p.run(1200);
  p.tap(arrows[g().dirs[2]]);
  p.run(1200);
  assert.equal(g().done, true);
  assert.equal(g().win, true);
  assert.ok(p.hasText("Wygrana!"));
  assert.equal(arrows.left.visible, false);
  assert.equal(p.destroy(), 0);
});

// --- nowe wyzwania -------------------------------------------------------------

function freshPet() {
  setPet((s) => {
    Object.assign(s, { form: "grocik", gone: "", asleep: false, light: true, sick: 0, hunger: 4, happy: 2, weight: 14, poops: 0, whim: 0, hatched: s.t - 86400000, stageAt: s.t });
    s.walks = {};
    s.request = null;
    s.bonus = null;
    s.timers.ask = 5000;
  });
}

test("menu zabaw: 22 gry w grupach, przewijana lista", () => {
  const p = makePage("page_gt_games_index.page.js").start();
  const names = ["Taniec Groota", "Części dla Rocketa", "Pilotaż Milano", "Strzała Yondu", "Refleks", "Ryby na Knowhere", "Ucieczka przed Abiliskiem", "Potrząśnij drzewem", "Płetwa Yondu", "Bomba Rocketa", "Medytacja z Mantis", "Wyścig z Rocketem", "Trening z Draxem", "Łapanie sygnału", "Wspinaczka", "Kamień Nieskończoności", "Wyprawa po Orb", "Nadajniki", "Lewo czy prawo?", "Rzut Orbem", "Kołysanie do snu", "Balans na belce"];
  for (const n of names) assert.ok(p.hasText(n), "brak " + n);
  p.tapText("Wyprawa");
  assert.equal(log.push.pop(), "page/gt/trip/index.page");
  const lowest = Math.max(...p.widgets.filter((w) => w.type === "TEXT").map((w) => w.props.y));
  assert.ok(lowest > 480, "lista powinna wychodzić poza ekran (przewijanie)");
});

// Każda nowa gra: ładuje się, chodzi 3 s bez błędów, po zamknięciu nie zostają timery,
// a gry ruchowe przywracają gaszenie ekranu
const NEW_GAMES = ["simon", "catch", "runner", "tree", "dig", "balloon", "eggroll", "reflex", "fishing", "aim", "forage", "climb", "dive", "trip", "marks", "race", "calm", "warmup", "defend", "mix", "galaxy"];
for (const id of NEW_GAMES) {
  test("gra " + id + ": start, 3 s, zamknięcie", () => {
    freshPet();
    accelReading = { x: 0, y: 0, z: 980 };
    log.display.length = 0;
    const p = makePage("page_gt_" + id + "_index.page.js").start();
    for (let i = 0; i < 30; i++) {
      accelReading = { x: Math.sin(i) * 30, y: Math.cos(i) * 30, z: 980 };
      p.run(100);
    }
    assert.ok(p.texts().length > 2);
    assert.equal(p.destroy(), 0, "zostały timery");
    if (log.display.includes("pause")) assert.ok(log.display.lastIndexOf("resetWrist") > log.display.lastIndexOf("pause"), "ekran nie przywrócony");
  });
}

test("powtórz ruch: przechyły zgodne z sekwencją wygrywają", () => {
  freshPet();
  const before = pet().happy;
  accelReading = { x: 0, y: 0, z: 980 };
  const p = makePage("page_gt_simon_index.page.js").start();
  const tiltFor = { left: { x: 500, y: 0 }, right: { x: -500, y: 0 }, up: { x: 0, y: -500 }, down: { x: 0, y: 500 } };
  for (let guard = 0; guard < 4000 && !p.opts.state.game.done; guard++) {
    const st = p.opts.state;
    if (st.phase === "input") {
      const d = st.game.seq[st.game.pos];
      accelReading = { x: tiltFor[d].x, y: tiltFor[d].y, z: 850 };
      p.run(80);
      accelReading = { x: 0, y: 0, z: 980 };
      p.run(80);
    } else p.run(100);
  }
  assert.equal(p.opts.state.game.win, true);
  assert.ok(p.hasText("Wygrana!"));
  assert.equal(pet().happy, before + 1);
  p.destroy();
});

test("powtórz ruch: po rundzie gwiazdka i czekanie, aż ręka wróci do poziomu", () => {
  freshPet();
  accelReading = { x: 0, y: 0, z: 980 };
  const p = makePage("page_gt_simon_index.page.js").start();
  const tiltFor = { left: { x: 500, y: 0 }, right: { x: -500, y: 0 }, up: { x: 0, y: -500 }, down: { x: 0, y: 500 } };
  for (let guard = 0; guard < 400 && p.opts.state.phase !== "input"; guard++) p.run(100);
  const st = p.opts.state;
  // cała pierwsza sekwencja; ostatni przechył zostaje (ręka nie wraca od razu)
  let d;
  for (let i = 0; i < st.game.level; i++) {
    d = st.game.seq[st.game.pos];
    accelReading = { x: tiltFor[d].x, y: tiltFor[d].y, z: 850 };
    p.run(80);
    if (i < st.game.level - 1) {
      accelReading = { x: 0, y: 0, z: 980 };
      p.run(80);
    }
  }
  assert.equal(st.phase, "wait");
  assert.ok(p.hasText("Dobrze! Dłuższa sekwencja"));
  p.run(3000); // nadal przechylony - nowy pokaz nie rusza
  assert.equal(st.phase, "wait", "pokaz ruszył przy przechylonym zegarku");
  accelReading = { x: 0, y: 0, z: 980 };
  p.run(400);
  assert.equal(st.phase, "wait", "za szybko po powrocie do poziomu");
  p.run(600);
  assert.equal(st.phase, "show");
  assert.equal(st.game.level, 3);
  p.destroy();
});

test("łapanie sygnału: obrót w stronę sygnału łapie go", () => {
  freshPet();
  const p = makePage("page_gt_forage_index.page.js").start();
  sensors.heading = null;
  p.run(300);
  assert.ok(p.hasText("Skalibruj kompas"));
  for (let i = 0; i < 300 && !p.opts.state.game.done; i++) {
    const g = p.opts.state.game;
    sensors.heading = g.targets[g.found] + 3;
    p.run(100);
  }
  assert.equal(p.opts.state.game.win, true);
  assert.ok(p.hasText("Sygnał złapany!"));
  p.destroy();
  sensors.heading = 0;
});

test("wspinaczka: start, zamknięcie, 3 m wyżej po powrocie = nagroda", () => {
  freshPet();
  sensors.altitude = 220;
  const before = pet().happy;
  const p = makePage("page_gt_climb_index.page.js").start();
  p.tap(p.find((w) => w.type === "TEXT" && w.props.text === "Start"));
  assert.equal(pet().walks.climb.alt0, 220);
  p.run(1000);
  assert.ok(p.hasText("+0.0 m"), p.texts().join("|"));
  p.destroy();
  // spacer po schodach z zamkniętą aplikacją
  clock.now += 20 * 60000;
  sensors.altitude = 223.4;
  const q = makePage("page_gt_climb_index.page.js").start();
  assert.ok(q.hasText("Na szczycie!"), q.texts().join("|"));
  assert.equal(pet().happy, Math.min(4, before + 2));
  assert.equal(pet().walks.climb, undefined);
  q.destroy();
});

test("wyprawa: cel zapamiętany, strzałka, dotarcie = nagroda", () => {
  freshPet();
  sensors.fix = { lat: 50.0614, lon: 19.9366 };
  sensors.heading = 0;
  const p = makePage("page_gt_trip_index.page.js").start();
  p.tapText("Wyznacz cel");
  const trip = pet().walks.trip;
  assert.ok(trip && trip.dist >= 200 && trip.dist <= 500);
  p.run(1000);
  const arrow = p.find((w) => w.props.src === "ui/pointer.png");
  assert.equal(arrow.visible, true);
  assert.ok(p.hasText(" m"));
  p.destroy();
  // dotarcie do celu, aplikacja otwarta ponownie
  sensors.fix = { lat: trip.lat + 0.00005, lon: trip.lon };
  const q = makePage("page_gt_trip_index.page.js").start();
  assert.ok(q.hasText("Orb zdobyty!"), q.texts().join("|"));
  assert.equal(pet().walks.trip, undefined);
  q.destroy();
  sensors.fix = { lat: 50.0614, lon: 19.9366 };
});

test("znaczenie terenu: za blisko, potem 3 miejsca", () => {
  freshPet();
  const p = makePage("page_gt_marks_index.page.js").start();
  sensors.fix = { lat: 50.0, lon: 20.0 };
  p.tapText("Postaw nadajnik");
  sensors.fix = { lat: 50.0003, lon: 20.0 }; // ok. 33 m
  p.tapText("Postaw nadajnik");
  assert.ok(p.hasText("Za blisko"), p.texts().join("|"));
  sensors.fix = { lat: 50.002, lon: 20.0 };
  p.tapText("Postaw nadajnik");
  sensors.fix = { lat: 50.004, lon: 20.0 };
  p.tapText("Postaw nadajnik");
  p.run(1000);
  assert.ok(p.hasText("Nadajniki stoją!"), p.texts().join("|"));
  p.destroy();
  sensors.fix = { lat: 50.0614, lon: 19.9366 };
});

test("balon: pompowanie ruchem i puszczenie przyciskiem", () => {
  freshPet();
  const p = makePage("page_gt_balloon_index.page.js").start();
  const g = () => p.opts.state.game;
  for (let t = 0; t < 30000 && g().size < g().lo; t += 40) {
    accelReading = { x: 0, y: 800 * Math.sin((2 * Math.PI * t) / 700), z: 980 };
    p.run(40);
  }
  assert.ok(g().size >= g().lo);
  p.key("KEY_SELECT");
  assert.equal(g().done, true);
  assert.equal(g().win, g().size <= g().hi);
  p.destroy();
});

// --- prośby, gry o premię, poranna rozgrzewka ------------------------------------

test("prośba o zabawę: dymek, napis, stuknięcie otwiera grę, wygrana daje premię", () => {
  freshPet();
  setPet((s) => {
    s.request = { game: "reflex", kind: "ask", t: s.t, until: s.t + 3 * 3600000 };
    s.happy = 1;
  });
  const p = makePage("page_gt_home_index.page.js").start();
  p.run(3000);
  assert.ok(p.imgs().includes("ui/bubble.png"), p.imgs().join(","));
  assert.ok(p.hasText("Chce zagrać: Refleks"), p.texts().join("|"));
  p.tap(p.find((w) => w.props.src === "ui/bubble.png"));
  assert.equal(log.push.pop(), "page/gt/reflex/index.page");
  p.destroy();
  const m = makePage("page_gt_games_index.page.js").start();
  assert.ok(m.hasText("Refleks · prosi!"));
  m.destroy();
  // wygrana w refleks (szybkie machnięcia po sygnale)
  const g = makePage("page_gt_reflex_index.page.js").start();
  for (let i = 0; i < 800 && !g.opts.state.game.done; i++) {
    const st = g.opts.state.game;
    accelReading = st.phase === "go" && clock.now - st.goAt > 250 ? { x: 1600, y: 0, z: 980 } : { x: 0, y: 0, z: 980 };
    g.run(40);
  }
  assert.equal(g.opts.state.game.win, true);
  assert.ok(g.hasText("Prośba spełniona!"), g.texts().join("|"));
  assert.equal(pet().happy, 3);
  assert.equal(pet().request, null);
  g.destroy();
});

test("gra o premię po przekąsce: przycisk przez chwilę, premia zapisana, gra otwarta", () => {
  freshPet();
  const p = makePage("page_gt_home_index.page.js").start();
  const ring = p.widgets.filter((w) => w.type === "IMG" && String(w.props.src).startsWith("ring/"));
  const offer = () => p.find((w) => w.type === "TEXT" && String(w.props.text).startsWith("Gra o premię"));
  assert.equal(offer().visible, false);
  p.tap(ring[1]); // przekąska
  p.run(1100);
  assert.equal(offer().visible, true);
  p.tap(offer());
  assert.equal(pet().bonus.game, "catch");
  assert.equal(log.push.pop(), "page/gt/catch/index.page");
  p.run(7000);
  assert.equal(offer().visible, false);
  // bez stuknięcia przycisk znika
  p.tap(ring[5]); // sprzątanie (czysto) - bez przycisku, bo akcja nic nie zrobiła
  p.run(1100);
  assert.equal(offer().visible, false);
  p.destroy();
});

test("lekarstwo z grą: chory może zagrać w celowanie, wygrana leczy", () => {
  freshPet();
  setPet((s) => (s.sick = 2));
  const p = makePage("page_gt_home_index.page.js").start();
  const ring = p.widgets.filter((w) => w.type === "IMG" && String(w.props.src).startsWith("ring/"));
  p.tap(ring[4]); // lekarstwo: 1 z 2 dawek
  assert.equal(pet().sick, 1);
  p.run(500);
  p.tapText("Gra o premię");
  assert.equal(log.push.pop(), "page/gt/aim/index.page");
  p.destroy();
  // celowanie: celownik prosto na cel, stuknięcie
  accelReading = { x: 0, y: 0, z: 980 };
  const a = makePage("page_gt_aim_index.page.js").start();
  a.run(800);
  for (let k = 0; k < 10 && !a.opts.state.game.done; k++) {
    const g = a.opts.state.game;
    // przechył: x = -tx/gain (znak jak w Labiryncie), y = +ty/gain
    accelReading = { x: (-g.tx / 260) * 980, y: (g.ty / 260) * 980, z: 980 };
    a.run(1500);
    a.key("KEY_SELECT");
  }
  assert.equal(a.opts.state.game.win, true, "trafienia " + a.opts.state.game.hits);
  assert.ok(a.hasText("Bez mszyc!"), a.texts().join("|"));
  assert.equal(pet().sick, 0);
  a.destroy();
});

test("poranna rozgrzewka: zaproszenie po pobudce i premia", () => {
  freshPet();
  setPet((s) => {
    s.request = { game: "warmup", kind: "morning", t: s.t, until: s.t + 4 * 3600000 };
    s.happy = 1;
  });
  const p = makePage("page_gt_home_index.page.js").start();
  p.run(3000);
  assert.ok(p.hasText("Poranna rozgrzewka!"), p.texts().join("|"));
  p.tap(p.find((w) => w.props.src === "ui/bubble.png"));
  assert.equal(log.push.pop(), "page/gt/warmup/index.page");
  p.destroy();
  const w = makePage("page_gt_warmup_index.page.js").start();
  for (let t = 0; t < 120000 && !w.opts.state.game.done; t += 40) {
    const g = w.opts.state.game;
    if (g.step < 2) accelReading = { x: 0, y: 900 * Math.sin((2 * Math.PI * t) / 700), z: 980 };
    else accelReading = Math.floor(t / 800) % 2 ? { x: 965, y: 0, z: 170 } : { x: 0, y: 0, z: 980 };
    w.run(40);
  }
  { const g = w.opts.state.game; assert.equal(g.win, true, "krok " + g.step + " powtórzeń " + g.count + " czas " + g.elapsed + " zrobione " + g.done); }
  assert.ok(w.hasText("Poranna premia!"), w.texts().join("|"));
  assert.equal(pet().happy, 3);
  w.destroy();
});

test("refleks i wędkowanie: bez ruchu ręki nic się nie zalicza (wibracja to nie ruch)", () => {
  for (const id of ["reflex", "fishing"]) {
    freshPet();
    accelReading = { x: 0, y: 0, z: 980 };
    vibrateAt = -1e12; // zegarek spokojny na starcie gry
    const p = makePage("page_gt_" + id + "_index.page.js").start();
    for (let i = 0; i < 2000 && !p.opts.state.game.done; i++) p.run(40);
    const g = p.opts.state.game;
    assert.equal(g.done, true, id);
    assert.ok(g.results.every((r) => r.late), id + ": " + JSON.stringify(g.results));
    assert.equal(g.win, false);
    p.destroy();
  }
});

test("kopanie: wibracja przy każdym kopnięciu nie nabija kolejnych", () => {
  freshPet();
  accelReading = { x: 0, y: 0, z: 980 };
  vibrateAt = -1e12;
  const p = makePage("page_gt_dig_index.page.js").start();
  // dokładnie 5 ruchów łopatą, potem spokój (a każde kopnięcie wibruje)
  for (let t = 0; t < 12000; t += 40) {
    const moving = t < 5 * 700;
    accelReading = moving ? { x: 0, y: 800 * Math.sin((2 * Math.PI * t) / 700), z: 980 } : { x: 0, y: 0, z: 980 };
    p.run(40);
  }
  const digs = p.opts.state.game.digs;
  assert.ok(digs >= 4 && digs <= 5, "kopnięć " + digs);
  p.destroy();
});

test("drzewo: wibracja przy owocu nie strąca kolejnych", () => {
  freshPet();
  accelReading = { x: 0, y: 0, z: 980 };
  vibrateAt = -1e12;
  const p = makePage("page_gt_tree_index.page.js").start();
  // 3 wyraźne potrząśnięcia co sekundę, poza tym ręka nieruchomo
  for (let t = 0; t < 6000; t += 40) {
    const shake = t % 1000 < 80 && t < 3000;
    accelReading = shake ? { x: 1500, y: 0, z: 980 } : { x: 0, y: 0, z: 980 };
    p.run(40);
  }
  assert.equal(p.opts.state.game.fruits, 3);
  p.destroy();
});

test("balon i inne gry z powtórzeniami: jeden ruch ręką nie pompuje do końca", () => {
  for (const id of ["balloon", "dig", "race", "warmup"]) {
    freshPet();
    accelReading = { x: 0, y: 0, z: 980 };
    vibrateAt = -1e12;
    const p = makePage("page_gt_" + id + "_index.page.js").start();
    p.run(1000);
    // jeden ruch w górę i w dół, potem ręka nieruchomo przez 8 s
    for (let t = 0; t < 700; t += 40) {
      accelReading = { x: 0, y: 800 * Math.sin((2 * Math.PI * t) / 700), z: 980 };
      p.run(40);
    }
    accelReading = { x: 0, y: 0, z: 980 };
    p.run(8000);
    const g = p.opts.state.game;
    const count = id === "balloon" ? Math.round(g.size / 5) : id === "dig" ? g.digs : id === "race" ? g.you : g.count + g.step * 8;
    assert.ok(count <= 2, id + ": jeden ruch dał " + count + " powtórzeń");
    p.destroy();
  }
});

test("wędkowanie: podgryza (wibracja), spławik nurkuje, poderwanie łowi rybę", () => {
  freshPet();
  shake = { ms: 1200, gaps: true };
  const p = makePage("page_gt_fishing_index.page.js").start();
  for (let i = 0; i < 3000 && !p.opts.state.game.done; i++) {
    const st = p.opts.state.game;
    const jerk = st.phase === "go" && clock.now - st.goAt > 600 && clock.now - st.goAt < 700;
    accelReading = jerk ? { x: 0, y: 1800, z: 980 } : { x: 0, y: 0, z: 980 };
    p.run(40);
  }
  const g = p.opts.state.game;
  assert.equal(g.win, true, JSON.stringify(g.results));
  assert.ok(g.results.every((r) => r.ok), JSON.stringify(g.results));
  assert.equal(log.buzz.length > 0, true);
  p.destroy();
  shake = { ms: VIBRATION_SHAKE_MS, gaps: false };
});

test("wędkowanie: długie, nieregularne drgania po wibracji nie łowią ani nie płoszą ryby", () => {
  freshPet();
  shake = { ms: 1400, gaps: true };
  accelReading = { x: 0, y: 0, z: 980 };
  vibrateAt = -1e12;
  const p = makePage("page_gt_fishing_index.page.js").start();
  for (let i = 0; i < 3000 && !p.opts.state.game.done; i++) p.run(40);
  const g = p.opts.state.game;
  assert.equal(g.done, true);
  assert.ok(g.results.every((r) => r.late), JSON.stringify(g.results));
  p.destroy();
  shake = { ms: VIBRATION_SHAKE_MS, gaps: false };
});

test("nurkowanie: ręka w dół, perła (wibracja), do góry - trzy razy = wygrana", () => {
  freshPet();
  const before = pet().happy;
  const HANG = { x: 960, y: 60, z: 120 };
  const FLAT = { x: 30, y: 40, z: 975 };
  accelReading = FLAT;
  const p = makePage("page_gt_dive_index.page.js").start();
  p.run(1000);
  for (let i = 0; i < 3; i++) {
    accelReading = HANG;
    p.run(1500);
    accelReading = FLAT;
    p.run(1000);
  }
  const g = p.opts.state.game;
  assert.equal(g.dives, 3);
  assert.equal(g.win, true);
  assert.ok(p.hasText("Trzy kamienie!"), p.texts().join("|"));
  assert.ok(pet().happy >= before);
  assert.equal(p.destroy(), 0);
});

test("nurkowanie: sama wibracja przy ekranie do góry nie nurkuje", () => {
  freshPet();
  shake = { ms: 1400, gaps: true };
  accelReading = { x: 30, y: 40, z: 975 };
  const p = makePage("page_gt_dive_index.page.js").start();
  for (let t = 0; t < 10000; t += 1000) {
    vibrateAt = clock.now;
    p.run(1000);
  }
  assert.equal(p.opts.state.game.dives, 0);
  p.destroy();
  shake = { ms: VIBRATION_SHAKE_MS, gaps: false };
  vibrateAt = -1e12;
});

test("kroki: energia, lądowanie na Xandarze, tło planety, strona Galaktyka", () => {
  freshPet();
  setPet((s) => {
    s.hunger = 1;
    s.trip = undefined;
  });
  sensors.steps = 6500;
  const q = makePage("page_gt_home_index.page.js").start();
  q.run(500);
  assert.equal(pet().hunger, 4, "3 x 2000 kroków = +3 energii");
  assert.deepEqual(pet().trip.visited, ["xandar"]);
  assert.ok(q.hasText("Xandar"), q.texts().join("|"));
  assert.ok(q.imgs().includes("ui/bg_xandar.png"), q.imgs().join(","));
  q.destroy();
  const g = makePage("page_gt_galaxy_index.page.js").start();
  assert.ok(g.hasText("Dziś 6 500 kroków"), g.texts().join("|"));
  assert.ok(g.hasText("Contraxia"), g.texts().join("|"));
  assert.ok(g.imgs().includes("ui/pc_xandar.png"));
  assert.ok(g.imgs().includes("ui/pc_knowhere_x.png"));
  g.tap(g.find((w) => w.props.src === "ui/pc_xandar.png"));
  assert.ok(g.hasText("Imperium Nova"), g.texts().join("|"));
  g.destroy();
  // ze statystyk przycisk do podróży
  const st = makePage("page_gt_stats_index.page.js").start();
  st.tapText("Podróż");
  assert.equal(log.push.pop(), "page/gt/galaxy/index.page");
  st.destroy();
  sensors.steps = 0;
});

test("Jestem Groot: stuknięcie, po chwili tłumaczenie Rocketa", () => {
  freshPet();
  setPet((s) => {
    s.hunger = 0;
    s.trip = undefined;
  });
  const q = makePage("page_gt_home_index.page.js").start();
  q.run(3000);
  q.tap(q.find((w) => w.type === "IMG" && String(w.props.src).startsWith("pet/grocik/")));
  assert.ok(q.hasText("Jestem Groot."), q.texts().join("|"));
  q.run(2000);
  assert.ok(q.hasText("Rocket: brakuje mu słońca"), q.texts().join("|"));
  q.destroy();
});

test("Obrona Milano: stukanie w statki wygrywa", () => {
  freshPet();
  const before = pet().happy;
  const p = makePage("page_gt_defend_index.page.js").start();
  for (let i = 0; i < 1200 && !p.opts.state.game.done; i++) {
    p.run(50);
    p.opts.state.pool.filter((sl) => sl.id).forEach((sl) => p.tap(sl.w.widget));
  }
  const g = p.opts.state.game;
  assert.equal(g.win, true, "zestrzelone " + g.killed + ", Milano " + g.lives);
  assert.ok(p.hasText("Wygrana!"));
  assert.ok(pet().happy > before);
  assert.equal(p.destroy(), 0);
});

test("Obrona Milano: bez stukania przegrana, wibracja przy trafieniu", () => {
  freshPet();
  const n = log.buzz.length;
  const p = makePage("page_gt_defend_index.page.js").start();
  p.run(50000);
  assert.equal(p.opts.state.game.win, false);
  assert.ok(log.buzz.length > n);
  assert.ok(p.hasText("Tym razem nie"));
  p.destroy();
});

test("Awesome Mix: wibracja rytmu, stukanie w tym samym rytmie wygrywa", () => {
  freshPet();
  const p = makePage("page_gt_mix_index.page.js").start();
  const n0 = log.buzz.length;
  for (let r = 0; r < 3 && !p.opts.state.game.done; r++) {
    for (let i = 0; i < 300 && p.opts.state.phase !== "play"; i++) p.run(50);
    assert.equal(p.opts.state.phase, "play");
    const pat = p.opts.state.game.pattern;
    p.tapText("Stukaj tu");
    pat.forEach((u) => {
      p.run(u * 480);
      p.tapText("Stukaj tu");
    });
    p.run(2000);
  }
  assert.ok(log.buzz.length - n0 >= 9, "rytm wystukany wibracją");
  assert.equal(p.opts.state.game.win, true);
  assert.ok(p.hasText("Groot tańczy!"));
  assert.equal(p.destroy(), 0);
});

if (failed) {
  console.error(failed + " scenariusz(e) nie przeszły");
  process.exit(1);
}
console.log("smoke: wszystko działa");
