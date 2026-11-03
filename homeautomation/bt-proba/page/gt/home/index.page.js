// Pomiar drogi zegarek -> ESP32: czy połączenie działa razem z telefonem, ile trwa skan + łączenie,
// ile zapis -> powiadomienie. „Pomiar”: jedno połączenie i 20 ramek. „Seria”: 5 połączeń pod rząd
// (pierwsze ze skanem, kolejne po znanym adresie, jak w aplikacji). Czasy: min/średnia/max.
import * as hmUI from "@zos/ui";
import { connectStatus } from "@zos/ble";
import { setPageBrightTime, resetPageBrightTime } from "@zos/display";
import { BasePage } from "@zeppos/zml/base-page";
import { BLEMaster } from "@silver-zepp/easy-ble";
import { summary, line, verdict } from "../../../utils/stats";

const DEVICE_NAME = "HA-BT";
const SERVICE_UUID = "FFA0";
const CMD_UUID = "FFA1";
const EVT_UUID = "FFA2";
const CCCD_UUID = "2902";

const SCAN_TIMEOUT_MS = 8000;
const STEP_TIMEOUT_MS = 8000;
const PROFILE_TIMEOUT_MS = 2500; // zwykle ok. 950 ms; dłużej = połączenie nie powstało, ponawiamy
const FIRST_ECHO_TIMEOUT_MS = 2000;
const TRIES = 3;
const RETRY_PAUSE_MS = 200;
const ECHO_TIMEOUT_MS = 1500;
const FIRST_ECHO_EVERY_MS = 200;
const PING_EVERY_MS = 300;
const PINGS = 20;
const PING_BYTES = 20;
const LONG_BYTES = [21, 23, 40, 60, 100]; // rozmiar:odpowiedź; „-” albo mniej = granica MTU
const PHONE_PINGS = 5;
const PHONE_TIMEOUT_MS = 5000;
const CYCLES = 20;
const CYCLE_PAUSE_MS = 1500;
const BRIGHT_MS = 180000;
const MAX_LINES = 11;

const COLOR_TEXT = 0xffffff;
const COLOR_BTN = 0x224466;
const COLOR_BTN_DOWN = 0x335577;

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function timeout(promise, ms, what) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(what)), ms);
    promise.then(
      (v) => {
        clearTimeout(timer);
        resolve(v);
      },
      (e) => {
        clearTimeout(timer);
        reject(e);
      }
    );
  });
}

function frame(kind, seq, size) {
  const a = new Uint8Array(size);
  a[0] = kind;
  a[1] = seq & 0xff;
  return a.buffer;
}

function messaging() {
  try {
    return getApp()._options.globalData.messaging;
  } catch (e) {
    return null;
  }
}

Page(
  BasePage({
    state: { lines: [], busy: false, scanOn: false, mac: null, ble: null, waiter: null, closed: false },

    log(text) {
      const s = this.state;
      console.log(text);
      s.lines.push(text);
      if (s.lines.length > MAX_LINES) s.lines.shift();
      if (s.text) s.text.setProperty(hmUI.prop.TEXT, s.lines.join("\n"));
    },

    // --- ESP32 ---

    scan(ble) {
      return timeout(
        new Promise((resolve, reject) => {
          const started = ble.startScan((d) => {
            if (d.dev_name !== DEVICE_NAME) return;
            ble.stopScan();
            resolve(d.dev_addr);
          });
          if (!started) reject(new Error("skan nie ruszyl"));
        }),
        SCAN_TIMEOUT_MS,
        "nie znaleziono " + DEVICE_NAME
      );
    },

    connect(ble, mac) {
      return timeout(
        new Promise((resolve, reject) => {
          ble.connect(mac, (r) => {
            if (r.connected) resolve();
            else if (this.state.ble === ble && r.status === "disconnected") this.log("ESP32: rozlaczono");
            else reject(new Error("laczenie: " + r.status));
          });
        }),
        STEP_TIMEOUT_MS,
        "laczenie: brak odpowiedzi"
      );
    },

    prepare(ble) {
      const services = {};
      services[SERVICE_UUID] = {};
      services[SERVICE_UUID][CMD_UUID] = [];
      services[SERVICE_UUID][EVT_UUID] = [CCCD_UUID];
      const profile = ble.generateProfileObject(services);
      return timeout(
        new Promise((resolve, reject) => {
          ble.startListener(profile, (r) => (r.success ? resolve() : reject(new Error("profil: " + r.message))));
        }),
        PROFILE_TIMEOUT_MS,
        "profil: brak odpowiedzi"
      );
    },

    onEcho(data, length) {
      const s = this.state;
      const a = new Uint8Array(data);
      if (s.waiter && a[1] === s.waiter.seq) s.waiter.resolve(length);
    },

    // Zapis bez kolejki biblioteki; -> { ms, length } albo null przy braku odpowiedzi
    async echo(ble, kind, seq, size, limit) {
      const s = this.state;
      const started = Date.now();
      const got = new Promise((resolve) => {
        s.waiter = { seq: seq & 0xff, resolve };
      });
      ble.write.characteristic(CMD_UUID, frame(kind, seq, size), true);
      try {
        const length = await timeout(got, limit, "echo");
        return { ms: Date.now() - started, length };
      } catch (e) {
        return null;
      } finally {
        s.waiter = null;
      }
    },

    // Powiadomienia działają dopiero po zapisie CCCD: ponawiamy ramkę aż wróci, to moment gotowości
    async firstEcho(ble) {
      const s = this.state;
      const end = Date.now() + FIRST_ECHO_TIMEOUT_MS;
      let seq = 200;
      while (Date.now() < end && !s.closed) {
        if (await this.echo(ble, 0x50, seq++, PING_BYTES, FIRST_ECHO_EVERY_MS)) return;
      }
      throw new Error("brak powiadomien");
    },

    // -> { scan, connect, prepare, ready } (ms) i otwarte połączenie w state.ble
    async open() {
      const s = this.state;
      const ble = new BLEMaster();
      const t = { scan: null };
      const start = Date.now();
      let mark = start;
      const lap = () => {
        const now = Date.now();
        const ms = now - mark;
        mark = now;
        return ms;
      };
      if (!s.mac) {
        s.mac = await this.scan(ble);
        t.scan = lap();
      }
      s.ble = ble;
      await this.connect(ble, s.mac);
      t.connect = lap();
      await this.prepare(ble);
      t.prepare = lap();
      ble.on.charaNotification((uuid, data, length) => this.onEcho(data, length));
      // Bez tego zdarzenia kolejka biblioteki czeka na koniec zapisu CCCD pełne 5 s i blokuje kolejne zapisy
      ble.on.descWriteComplete(() => {});
      ble.write.enableCharaNotifications(EVT_UUID, true);
      await this.firstEcho(ble);
      t.first = lap();
      t.ready = Date.now() - start;
      // Stan skanowania na ESP32 zostaje do następnej zmiany, także między połączeniami serii
      await this.echo(ble, s.scanOn ? 0x53 : 0x73, 1, PING_BYTES, ECHO_TIMEOUT_MS);
      return t;
    },

    // Połączenie, które nie powstało, ponawiamy od razu. t.ready liczy czas wszystkich prób
    async openRetry() {
      const start = Date.now();
      for (let tries = 1; ; tries++) {
        try {
          const t = await this.open();
          t.tries = tries;
          t.ready = Date.now() - start;
          return t;
        } catch (e) {
          this.close();
          if (tries >= TRIES || this.state.closed) throw e;
          await wait(RETRY_PAUSE_MS);
        }
      }
    },

    close() {
      const s = this.state;
      if (!s.ble) return;
      const ble = s.ble;
      s.ble = null;
      try {
        ble.quit();
      } catch (e) {}
    },

    // --- telefon ---

    async phoneTimes() {
      const m = messaging();
      const out = [];
      if (!m) return out;
      for (let i = 0; i < PHONE_PINGS; i++) {
        const started = Date.now();
        try {
          await m.request({ method: "PING" }, { timeout: PHONE_TIMEOUT_MS });
          out.push(Date.now() - started);
        } catch (e) {
          out.push(null);
        }
      }
      return out;
    },

    phoneState() {
      return connectStatus() ? "polaczony" : "BRAK";
    },

    // --- pomiary ---

    async measure() {
      const s = this.state;
      this.log("Telefon: " + this.phoneState());
      this.log(line("tel. przed", summary(await this.phoneTimes())));
      const t = await this.openRetry();
      this.log(`skan ${t.scan} lacz ${t.connect} profil ${t.prepare} echo ${t.first}`);
      this.log(`gotowe po ${t.ready} ms`);

      const ble = s.ble;
      const times = [];
      for (let i = 0; i < PINGS && !s.closed; i++) {
        const r = await this.echo(ble, 0x50, i, PING_BYTES, ECHO_TIMEOUT_MS);
        times.push(r ? r.ms : null);
        await wait(PING_EVERY_MS);
      }
      const lost = times.filter((x) => x === null).length;
      this.log(line("echo", summary(times)) + ` strat ${lost}`);

      const sizes = [];
      for (let i = 0; i < LONG_BYTES.length; i++) {
        const r = await this.echo(ble, 0x50, 100 + i, LONG_BYTES[i], ECHO_TIMEOUT_MS);
        sizes.push(`${LONG_BYTES[i]}:${r ? r.length : "-"}`);
      }
      this.log("ramki " + sizes.join(" "));

      this.log("Telefon: " + this.phoneState());
      this.log(line("tel. razem", summary(await this.phoneTimes())));
    },

    async series() {
      const s = this.state;
      const ready = [];
      let first = null;
      let failed = 0;
      let retried = 0;
      for (let i = 0; i < CYCLES && !s.closed; i++) {
        try {
          const t = await this.openRetry();
          if (t.scan !== null) first = t.ready;
          else ready.push(t.ready);
          if (t.tries > 1) retried++;
          this.log(`${i + 1}/${CYCLES}: ${t.ready} ms`);
        } catch (e) {
          failed++;
          this.log(`${i + 1}/${CYCLES}: ${e.message}`);
        }
        this.close();
        await wait(CYCLE_PAUSE_MS);
      }
      s.lines = s.lines.filter((l) => !/ ms$/.test(l));
      if (first !== null) this.log(`ze skanem: ${first} ms`);
      this.log(`z powtorka: ${retried}, nieudane: ${failed}/${CYCLES}`);
      this.log(line("bez skanu", summary(ready)));
      this.log(verdict(ready));
      this.log("Telefon: " + this.phoneState());
    },

    async run(action) {
      const s = this.state;
      if (s.busy) return;
      s.busy = true;
      s.lines = [];
      try {
        await action();
      } catch (e) {
        this.log("Blad: " + e.message);
      }
      this.close();
      s.busy = false;
      this.log("Koniec");
    },

    // --- ekran ---

    button(x, y, w, h, text, click) {
      return hmUI.createWidget(hmUI.widget.BUTTON, {
        x,
        y,
        w,
        h,
        text,
        text_size: 26,
        radius: 16,
        normal_color: COLOR_BTN,
        press_color: COLOR_BTN_DOWN,
        click_func: click,
      });
    },

    build() {
      const s = this.state;
      setPageBrightTime({ brightTime: BRIGHT_MS });
      hmUI.createWidget(hmUI.widget.TEXT, {
        x: 90,
        y: 22,
        w: 300,
        h: 36,
        text: "BT proba",
        text_size: 28,
        color: COLOR_TEXT,
        align_h: hmUI.align.CENTER_H,
      });
      s.text = hmUI.createWidget(hmUI.widget.TEXT, {
        x: 46,
        y: 62,
        w: 388,
        h: 290,
        text: "Otworz w poblizu HA-BT",
        text_size: 22,
        color: COLOR_TEXT,
        text_style: hmUI.text_style.WRAP,
      });
      this.button(62, 356, 174, 58, "Pomiar", () => this.run(() => this.measure()));
      this.button(244, 356, 174, 58, "Seria", () => this.run(() => this.series()));
      s.scanBtn = this.button(130, 420, 220, 48, "Skan ESP: nie", () => {
        if (s.busy) return;
        s.scanOn = !s.scanOn;
        s.scanBtn.setProperty(hmUI.prop.TEXT, s.scanOn ? "Skan ESP: tak" : "Skan ESP: nie");
      });
    },

    onDestroy() {
      this.state.closed = true;
      this.close();
      resetPageBrightTime();
    },
  })
);
