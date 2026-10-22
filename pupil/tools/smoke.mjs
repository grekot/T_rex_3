// Smoke test prawdziwych bundli zeusa w Node vm (bez zegarka i symulatora).
//
// 1. Zbuduj z przechwyceniem bundli (PowerShell, z folderu pupil):
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
      Accelerometer: class {
        setFreqMode() {}
        onChange() {}
        offChange() {}
        start() {}
        stop() {}
        getCurrent() {
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
    start() {
      if (pageOpts.onInit) pageOpts.onInit.call(pageOpts);
      pageOpts.build.call(pageOpts);
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
  return JSON.parse(files.get("pupil_state.json"));
}
function setPet(fn) {
  const s = pet();
  fn(s);
  files.set("pupil_state.json", JSON.stringify(s));
  files.set("pupil_state.bak", JSON.stringify(s));
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
  const old = { v: 1, gen: 3, rng: 5, t: clock.now - 60000, born: clock.now - 86400000, hatched: clock.now - 86000000, form: "tupek", stageAt: clock.now - 3600000, hunger: 3, happy: 3, discipline: 1, weight: 12, poops: 0, poopAt: 0, sick: 0, asleep: false, light: true, lightMiss: false, timers: { hunger: 100, happy: 100, poop: 100, whim: 300 }, calls: { hunger: 0, happy: 0, sick: 0, light: 0 }, due: { hunger: 0, happy: 0, sick: 0, light: 0 }, whim: 0, mistakes: 0, totalMistakes: 0, neglect: 0, gone: "", goneAt: 0, seen: ["pisklak", "tupek"], history: [] };
  storageMap.set("pupil_state", JSON.stringify(old));
  const p = makePage("page_gt_home_index.page.js").start();
  assert.equal(pet().gen, 3);
  assert.equal(pet().form, "tupek");
  p.destroy();
  storageMap.clear();
  files.clear();
});

test("ekran główny: nowe jajo, wyklucie, karmienie, przyciski", () => {
  const p = makePage("page_gt_home_index.page.js").start();
  assert.equal(pet().form, "egg");
  assert.ok(p.imgs().includes("pet/egg/egg0.png"), p.imgs().join(","));
  assert.ok(p.hasText("Nowe jajo!"));
  p.run(4 * 60000);
  assert.equal(pet().form, "pisklak");
  assert.ok(p.imgs().some((s) => s.startsWith("pet/pisklak/")), p.imgs().join(","));
  assert.ok(p.hasText("Pisklak"));
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
  assert.ok(p.hasText("Mniam!"));
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
  // stuknięcie w dinozaura
  p.tap(p.find((w) => w.type === "IMG" && String(w.props.src).startsWith("pet/")));
  p.run(60000);
  assert.equal(p.destroy(), 0, "zostały timery po zamknięciu");
});

test("ekran główny: noc, zgaszone światło, odejście i nowe jajo", () => {
  setPet((s) => {
    s.form = "rex";
    s.stageAt = s.t - 5 * 86400000;
    s.hunger = 4;
    s.happy = 4;
    s.poops = 0;
    s.sick = 0;
    s.weight = 30;
    s.timers = { hunger: 2000, happy: 2000, poop: 2000, whim: 2000 };
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
  assert.ok(p.imgs().some((s) => /rex\/dark[01]\.png$/.test(s)), p.imgs().join(","));
  assert.ok(p.imgs().includes("ui/zzz.png"));
  const bg = p.widgets[0];
  assert.equal(bg.props.color, 0x060918);
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
  assert.ok(q.hasText("Stuknij: nowe jajo"));
  q.tap(q.find((w) => w.type === "IMG" && w.props.src === "ui/forest.png"));
  assert.equal(pet().form, "egg");
  assert.equal(pet().gen, 2);
  assert.ok(pet().seen.includes("pisklak"));
  q.destroy();
});

function hatchAdult() {
  setPet((s) => {
    Object.assign(s, { form: "rogal", hatched: s.t - 86400000, stageAt: s.t, hunger: 4, happy: 2, weight: 26, asleep: false, light: true, sick: 0 });
  });
}

test("przypomnienie: alarm przy wyjściu, wibracja, gdy alarm otworzy aplikację", () => {
  files.delete("pupil_alarm.json");
  setPet((s) => {
    Object.assign(s, { form: "rex", hatched: s.t - 3 * 86400000, stageAt: s.t, hunger: 4, happy: 4, poops: 0, sick: 0, asleep: false, light: true, whim: 0, gone: "" });
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
  assert.ok(q.hasText("Pupil cię woła!"), q.texts().join("|"));
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
  assert.equal(p.imgs().filter((s) => s === "ui/heart.png").length, 4 + 2 + pet().discipline);
  assert.ok(p.hasText("Rogal"), p.texts().join("|"));
  assert.ok(p.hasText("Waga 26 g"), p.texts().join("|"));
  p.tapText("Kolekcja");
  assert.equal(log.push.pop(), "page/gt/collection/index.page");
  p.destroy();
  const c = makePage("page_gt_collection_index.page.js").start();
  assert.ok(c.hasText("Kolekcja 1/10"), c.texts().join("|"));
  assert.ok(c.imgs().includes("thumb/pisklak.png"));
  assert.ok(c.imgs().includes("thumb/rex_x.png"));
  c.tap(c.find((w) => w.props.src === "thumb/pisklak.png"));
  assert.ok(c.hasText("Pisklak"));
  c.tap(c.find((w) => w.props.src === "thumb/rex_x.png"));
  assert.ok(c.hasText("???"));
  c.destroy();
});

test("menu zabaw", () => {
  const p = makePage("page_gt_games_index.page.js").start();
  ["Rzut piłką", "Kołysanie do snu", "Balans na kłodzie", "Lewo czy prawo?"].forEach((t, i) => {
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
  assert.equal(log.back, 1);
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

if (failed) {
  console.error(failed + " scenariusz(e) nie przeszły");
  process.exit(1);
}
console.log("smoke: wszystko działa");
