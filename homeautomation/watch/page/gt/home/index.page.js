// Pulpit zegarka (API.md pkt 13a): strony z kafelkami ułożonymi na telefonie dla tego zegarka
// (users/{uid}/watchDashboards/{homeId}/{watchId}); bez pulpitu - urządzenia, do których osoba ma dostęp,
// strona na pokój. Strony leżą jedna pod drugą, kafelki w wierszach (half / full / big, utils/layout.js).
// Widoki: thermostat (dotknięcie otwiera ekran termostatu), toggle (dotknięcie przełącza), stepper (− / +,
// jedno polecenie po 1 s bez dotyku), status, value, scene (▶ wysyła polecenia sceny). Przy dostępie
// „view” bez przycisków. Przy uruchomieniu zegarek zgłasza się (model, ekran) - telefon układa pod niego pulpit.
// Stan przychodzi przez Side Service co ~5 s, tylko gdy ta strona jest otwarta i na wierzchu.
import * as hmUI from "@zos/ui";
import { push } from "@zos/router";
import { setWakeUpRelaunch, setPageBrightTime } from "@zos/display";
import { getDeviceInfo } from "@zos/device";
import { BasePage } from "@zeppos/zml/base-page";
import {
  SEND_DELAY_MS,
  ACK_TIMEOUT_MS,
  chooseValue,
  editLocal,
  sendDue,
  needsSend,
  shownValue,
  settleLocal,
  applyAck,
} from "../../../utils/termostat";
import { tileText } from "../../../utils/devices";
import { canControl, formatPoint, stepPoint, emptyMessage, iconAsset } from "../../../utils/home";
import { layoutPages } from "../../../utils/layout";
import { APP_VERSION } from "../../../utils/version";
import { ask, setTop, isTop, onTap, toast } from "../../../utils/page";
import {
  SCREEN,
  GEOMETRY_PX,
  TITLE_STYLE,
  STATUS_STYLE,
  CENTER_STYLE,
  headerStyle,
  tileParts,
  bottomSpacer,
  COLOR_TEXT,
  COLOR_GREY,
  COLOR_ORANGE,
  COLOR_RED,
  COLOR_ON,
  COLOR_OFF,
} from "zosLoader:./index.page.[pf].layout.js";

const THERMOSTAT_PAGE = "page/gt/thermostat/index.page";
const POLL_MS = 5000;
const AWAY_CHECK_MS = 1000; // pod ekranem termostatu tylko sprawdzamy, czy już wrócił
const POLL_AFTER_SEND_MS = 2000;
const DOUBLE_TAP_MS = 300;
const TARGET_SPEC = { min: 15, max: 30, step: 0.5, unit: "°C", decimals: 1 }; // nastawa bez opisu (pkt 7)

// Dane zegarka do zgłoszenia (pkt 13a); deviceName bywa liczbą - wtedy nazwę ustali Side Service
function watchInfo() {
  try {
    const d = getDeviceInfo();
    return { deviceSource: d.deviceSource, name: typeof d.deviceName === "string" ? d.deviceName : "", width: d.width, height: d.height, shape: SCREEN.shape };
  } catch (e) {
    return null;
  }
}

const localKey = (item) => item.device + "/" + item.point;

// scena wykonana na zegarku tylko w części (utils/home.js sceneSteps)
const PARTIAL = {
  hub: "wysłano część (opóźnienia wymagają huba)",
  access: "wysłano część (bez uprawnień do niektórych urządzeń)",
};

Page(
  BasePage({
    state: {},

    build() {
      const s = this.state;
      setTop("home");
      s.info = watchInfo();
      s.homeId = null;
      s.title = "";
      s.pages = [];
      s.devices = {};
      s.locals = {}; // "urządzenie/punkt" -> wartość ustawiona dotknięciem, zanim baza ją pokaże
      s.awaiting = {}; // urządzenie -> { key, at }
      s.sendTimers = {};
      s.tiles = [];
      s.extra = [];
      s.signature = "";
      s.taps = {};
      s.sending = 0;
      s.screen = "Łączenie z telefonem...";
      try {
        setWakeUpRelaunch({ relaunch: true });
      } catch (e) {}
      try {
        setPageBrightTime({ brightTime: 30000 });
      } catch (e) {}

      s.titleText = hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);
      s.status = hmUI.createWidget(hmUI.widget.TEXT, STATUS_STYLE);
      s.center = hmUI.createWidget(hmUI.widget.TEXT, CENTER_STYLE);
      this.render();
      this.register();
      this.poll();
    },

    onDestroy() {
      const s = this.state;
      s.destroyed = true;
      if (s.pollTimer) clearTimeout(s.pollTimer);
      Object.keys(s.sendTimers).forEach((k) => clearTimeout(s.sendTimers[k]));
    },

    // Telefon dał znać, że w ustawieniach zalogowano się albo zmieniono dom - odśwież od razu
    onCall(req) {
      if (req && req.type === "LOGGED_IN") {
        if (!this.state.registered) this.register();
        this.pollSoon(0);
      }
    },

    // Zgłoszenie zegarka (raz na uruchomienie; bez logowania - ponownie po zalogowaniu)
    register() {
      const s = this.state;
      if (!s.info || s.registering) return;
      s.registering = true;
      ask(this, { method: "REGISTER", params: { info: s.info, app: APP_VERSION } })
        .then((r) => {
          s.registering = false;
          if (r && r.ok) s.registered = true;
        })
        .catch(() => {
          s.registering = false;
        });
    },

    once(name) {
      const s = this.state;
      const now = Date.now();
      if (now - (s.taps[name] || 0) < DOUBLE_TAP_MS) return false;
      s.taps[name] = now;
      return true;
    },

    // --- odczyt ---

    pollSoon(ms) {
      const s = this.state;
      if (s.destroyed) return;
      if (s.polling) {
        s.pollAgain = true;
        return;
      }
      if (s.pollTimer) clearTimeout(s.pollTimer);
      s.pollTimer = setTimeout(() => {
        s.pollTimer = null;
        this.poll();
      }, ms);
    },

    poll() {
      const s = this.state;
      if (s.destroyed || s.polling) return;
      // otwarty ekran termostatu sam odpytuje swoje urządzenie; pulpit czeka na powrót
      if (!isTop("home")) {
        s.away = true;
        return this.pollSoon(AWAY_CHECK_MS);
      }
      if (s.away) {
        s.away = false;
        this.render();
      }
      s.polling = true;
      const pending = {};
      Object.keys(s.awaiting).forEach((id) => {
        pending[id] = s.awaiting[id].key;
      });
      const done = (r, failed) => {
        s.polling = false;
        if (s.destroyed) return;
        if (failed) this.phoneDown();
        else this.received(r || {});
        const again = s.pollAgain;
        s.pollAgain = false;
        this.pollSoon(again ? 0 : POLL_MS);
      };
      const watch = s.info && s.info.deviceSource !== undefined ? String(s.info.deviceSource) : null;
      const screen = s.info ? { width: s.info.width, height: s.info.height, shape: s.info.shape } : null;
      ask(this, { method: "HOME", params: { watch, screen, pending: Object.keys(pending).length ? pending : null } })
        .then((r) => done(r, false))
        .catch(() => done(null, true));
    },

    phoneDown() {
      const s = this.state;
      s.phoneDown = true;
      if (!s.pages.length) s.screen = "Brak połączenia z telefonem";
      this.checkAckTimeouts();
      this.render();
    },

    received(r) {
      const s = this.state;
      const now = Date.now();
      s.phoneDown = false;
      s.error = "";
      if (!r.ok) {
        if (r.notConfigured) this.showScreen("Brak konfiguracji");
        else if (r.needsLogin) this.showScreen("Zaloguj się w aplikacji Zepp: Dom → Ustawienia");
        else if (s.pages.length) s.error = r.error || "błąd";
        else s.screen = "Błąd: " + (r.error || "nieznany");
        return this.render();
      }
      if (r.noHome) return this.showScreen("Nie należysz do żadnego domu. Załóż dom albo dołącz kodem w aplikacji HomeAutomation.");
      if (r.homeId !== s.homeId) this.forget();
      s.homeId = r.homeId;
      s.title = r.title || "";
      if (!r.pages || !r.pages.length) {
        s.pages = [];
        s.devices = {};
        s.screen = emptyMessage(r.diag);
        return this.render();
      }
      s.pages = r.pages;
      s.devices = r.devices || {};
      Object.keys(s.devices).forEach((id) => {
        const d = s.devices[id];
        const wait = s.awaiting[id];
        if (wait && d.ack) {
          if (!d.ack.ok) toast(d.name + ": " + d.ack.text);
          this.eachLocal(id, (k) => {
            s.locals[k] = applyAck(s.locals[k], d.ack, wait.key, now);
          });
          delete s.awaiting[id];
        }
      });
      this.checkAckTimeouts();
      Object.keys(s.locals).forEach((k) => {
        const [id, point] = splitKey(k);
        const d = s.devices[id];
        s.locals[k] = d ? settleLocal(s.locals[k], (d.values || {})[point], now) : null;
        if (!s.locals[k]) delete s.locals[k];
      });
      this.render();
    },

    eachLocal(id, fn) {
      Object.keys(this.state.locals).forEach((k) => {
        if (splitKey(k)[0] === id) fn(k);
      });
    },

    checkAckTimeouts() {
      const s = this.state;
      const now = Date.now();
      Object.keys(s.awaiting).forEach((id) => {
        if (now - s.awaiting[id].at < ACK_TIMEOUT_MS) return;
        delete s.awaiting[id];
        const d = s.devices[id];
        toast((d ? d.name + ": " : "") + (d && d.tile.offline ? "nie odpowiada" : "brak potwierdzenia"));
      });
    },

    forget() {
      const s = this.state;
      Object.keys(s.sendTimers).forEach((k) => clearTimeout(s.sendTimers[k]));
      s.sendTimers = {};
      s.locals = {};
      s.awaiting = {};
    },

    showScreen(text) {
      const s = this.state;
      s.pages = [];
      s.devices = {};
      this.forget();
      s.title = "";
      s.screen = text;
      this.render();
    },

    // --- dotknięcia ---

    // buttons = kafelek ma własne − / + (dotknięcie przycisku nie może też otwierać termostatu)
    tapped(item, buttons) {
      const s = this.state;
      if (!this.once(item.key)) return;
      if (item.kind === "scene") return this.runScene(item);
      const d = s.devices[item.device];
      if (!d) return;
      if (item.kind === "thermostat" || (item.kind === "stepper" && !buttons && d.type === "thermostat")) {
        setTop("thermostat");
        push({ url: THERMOSTAT_PAGE, params: JSON.stringify({ home: s.homeId, id: item.device, name: d.name, level: item.level }) });
        return;
      }
      if (item.kind === "toggle" && canControl(item.level) && d.tile.hasData) this.toggle(item, d);
    },

    // Polecenie przez telefon; done(r) dostaje odpowiedź Side Service albo null (telefon niedostępny)
    sendSet(id, values, done) {
      const s = this.state;
      s.sending++;
      this.render();
      const finish = (r) => {
        s.sending--;
        if (s.destroyed) return;
        done(r);
        this.render();
      };
      ask(this, { method: "SET", params: { home: s.homeId, id, values } })
        .then((r) => finish(r || null))
        .catch(() => finish(null));
    },

    // Wysyła wartość z locals[k]; po odpowiedzi czekamy na lastCommand
    sendLocal(k) {
      const s = this.state;
      const [id, point] = splitKey(k);
      const d = s.devices[id];
      const local = s.locals[k];
      if (!d || !local) return;
      const remote = (d.values || {})[point];
      if (!needsSend(local, remote)) {
        delete s.locals[k];
        return this.render();
      }
      const sent = { ...local, sentAt: Date.now() };
      s.locals[k] = sent;
      const values = {};
      values[point] = sent.value;
      this.sendSet(id, values, (r) => {
        const mine = s.locals[k] && s.locals[k].sentAt === sent.sentAt;
        if (r && r.ok && r.key) {
          if (mine) s.locals[k] = { ...s.locals[k], key: r.key };
          s.awaiting[id] = { key: r.key, at: Date.now() };
          this.pollSoon(POLL_AFTER_SEND_MS);
        } else {
          if (mine) delete s.locals[k];
          toast(notSent(r));
        }
      });
    },

    toggle(item, d) {
      const s = this.state;
      const k = localKey(item);
      const remote = (d.values || {})[item.point];
      s.locals[k] = chooseValue(s.locals[k] || null, !shownValue(s.locals[k] || null, remote === true), Date.now());
      this.sendLocal(k);
      this.render();
    },

    // − / + w kafelku stepper: naciśnięcia zbieramy, jedno polecenie po 1 s bez dotyku
    step(item, dir) {
      const s = this.state;
      const d = s.devices[item.device];
      if (!d || !d.tile.hasData || !canControl(item.level)) return;
      const k = localKey(item);
      const remote = (d.values || {})[item.point];
      const next = stepPoint(shownValue(s.locals[k] || null, remote), dir, specOf(item));
      if (next === null) return;
      s.locals[k] = editLocal(s.locals[k] || null, next, Date.now());
      this.render();
      if (s.sendTimers[k]) clearTimeout(s.sendTimers[k]);
      s.sendTimers[k] = setTimeout(() => {
        delete s.sendTimers[k];
        if (sendDue(s.locals[k], Date.now())) this.sendLocal(k);
      }, SEND_DELAY_MS);
    },

    // Scena: z hubem jedno polecenie {"runScene": id}, bez huba akcje po kolei; komunikat po ostatnim
    runScene(item) {
      const steps = item.hub ? [{ device: item.hub, set: { runScene: item.sceneId } }] : item.scene.slice();
      let failed = null;
      const next = () => {
        const step = steps.shift();
        if (!step) {
          const done = PARTIAL[item.partial] || "wysłano";
          toast(item.name + ": " + (failed || done));
          return this.pollSoon(POLL_AFTER_SEND_MS);
        }
        this.sendSet(step.device, step.set, (r) => {
          if (!(r && r.ok)) failed = notSent(r);
          next();
        });
      };
      next();
    },

    // --- ekran ---

    // Kafelki tworzymy od nowa tylko, gdy zmienia się układ (strony, kafelki, nazwy, rodzaje, uprawnienia)
    rebuild() {
      const s = this.state;
      s.tiles.forEach((t) => t.widgets.forEach((w) => hmUI.deleteWidget(w)));
      s.extra.forEach((w) => hmUI.deleteWidget(w));
      s.tiles = [];
      s.extra = [];
      const { blocks, height } = layoutPages(s.pages, SCREEN, GEOMETRY_PX);
      blocks.forEach((b) => {
        if (b.type === "header") {
          s.extra.push(hmUI.createWidget(hmUI.widget.TEXT, headerStyle(b)));
          return;
        }
        const item = b.item;
        const buttons = item.kind === "stepper" && b.size !== "half" && canControl(item.level);
        const dev = item.device ? s.devices[item.device] : null;
        const parts = tileParts(b, buttons, item.kind === "thermostat", iconAsset(item.icon, item.kind, dev && dev.type));
        const t = { item, size: b.size, parts, widgets: [] };
        const add = (type, style) => {
          if (!style) return null;
          const w = hmUI.createWidget(type, style);
          t.widgets.push(w);
          return w;
        };
        t.bg = add(hmUI.widget.FILL_RECT, parts.bg);
        add(hmUI.widget.IMG, parts.icon);
        t.name = add(hmUI.widget.TEXT, { ...parts.name, text: item.name });
        t.sub = add(hmUI.widget.TEXT, parts.sub);
        t.value = add(hmUI.widget.TEXT, parts.value);
        t.pill = add(hmUI.widget.FILL_RECT, parts.pill);
        t.pillText = add(hmUI.widget.TEXT, parts.pillText);
        t.badge = add(hmUI.widget.TEXT, parts.badge);
        onTap(t.widgets.slice(), () => this.tapped(item, buttons));
        [
          [parts.minus, -1],
          [parts.plus, 1],
        ].forEach(([btn, dir]) => {
          if (!btn) return;
          const circle = add(hmUI.widget.CIRCLE, btn.circle);
          const label = add(hmUI.widget.TEXT, btn.text);
          onTap([circle, label], () => {
            if (this.once(item.key + dir)) this.step(item, dir);
          });
        });
        s.tiles.push(t);
      });
      if (blocks.length) s.extra.push(hmUI.createWidget(hmUI.widget.FILL_RECT, bottomSpacer(height - GEOMETRY_PX.bottom, GEOMETRY_PX.bottom)));
    },

    render() {
      const s = this.state;
      if (s.destroyed || !isTop("home")) return;
      const sig = JSON.stringify(s.pages.map((p) => [p.title, p.items.map((it) => [it.key, it.kind, it.name, it.level, it.device, it.size, it.point, it.icon])]));
      if (sig !== s.signature) {
        s.signature = sig;
        this.rebuild();
      }
      s.titleText.setProperty(hmUI.prop.TEXT, String(s.title || "Dom").toUpperCase());
      const hasTiles = s.pages.length > 0;
      s.center.setProperty(hmUI.prop.VISIBLE, !hasTiles);
      if (!hasTiles) s.center.setProperty(hmUI.prop.TEXT, s.screen || "");
      s.tiles.forEach((t) => this.renderTile(t));

      let status = "";
      if (s.phoneDown) status = "Telefon niedostępny";
      else if (s.error) status = "Błąd: " + s.error;
      else if (s.sending) status = "Wysyłanie...";
      s.status.setProperty(hmUI.prop.TEXT, status);
    },

    renderTile(t) {
      const s = this.state;
      const item = t.item;
      const parts = t.parts;
      const d = s.devices[item.device] || { tile: { hasData: false }, values: {} };
      const values = d.values || {};
      const offline = !!(d.tile.hasData && d.tile.offline);
      const control = canControl(item.level);
      const local = item.point ? s.locals[localKey(item)] || null : null;
      let value = "";
      let valueColor = COLOR_TEXT;
      let sub = "";
      let subColor = COLOR_GREY;
      let alert = "";
      let pill = null; // { text, on, pending }
      let badge = null; // { text, alert }

      if (item.kind === "thermostat") {
        const txt = tileText(d.tile);
        value = txt.value;
        valueColor = d.tile.offline || d.tile.sensorFault ? COLOR_GREY : COLOR_TEXT;
        sub = txt.sub;
        subColor = txt.heating ? COLOR_ORANGE : COLOR_GREY;
        if (txt.alert) alert = txt.sub;
        badge = txt.badge;
      } else if (item.kind === "toggle") {
        const on = shownValue(local, values[item.point] === true) === true;
        // bez stanu w chmurze: węzeł bez chmury (przełącznik do czasu huba) albo urządzenie jeszcze nie połączone
        sub = !d.tile.hasData ? "brak danych w chmurze" : on ? "włączone" : "wyłączone";
        if (d.type === "dimmer" && on && typeof values.level === "number") sub = "jasność " + values.level + "%";
        if (control && d.tile.hasData && t.size !== "big") pill = { text: on ? "WŁ" : "WYŁ", on, pending: !!local };
        else {
          value = d.tile.hasData ? (on ? "WŁ" : "WYŁ") : "--";
          valueColor = local ? COLOR_GREY : on ? COLOR_ORANGE : COLOR_GREY;
        }
      } else if (item.kind === "stepper" || item.kind === "value") {
        const v = item.kind === "stepper" ? shownValue(local, values[item.point]) : values[item.point];
        value = d.tile.hasData ? formatPoint(v, specOf(item)) : "--";
        valueColor = local ? COLOR_TEXT : item.kind === "stepper" ? COLOR_ORANGE : COLOR_TEXT;
        sub = String(item.pointName || item.point || "").toLowerCase();
      } else if (item.kind === "status") {
        const on = values[item.point] === true;
        value = d.tile.hasData ? (on ? "tak" : "nie") : "--";
        if (item.point === "heating" && d.tile.hasData) value = on ? "grzeje" : "nie grzeje";
        valueColor = on ? COLOR_ORANGE : COLOR_GREY;
        sub = String(item.pointName || item.point || "").toLowerCase();
      } else if (item.kind === "scene") {
        sub = "scena";
        if (t.size === "big") value = "▶";
        else pill = { text: "▶", on: true, pending: false };
      } else {
        sub = "nieobsługiwane urządzenie";
      }
      if (offline && item.kind !== "scene") {
        alert = "Brak kontaktu";
        valueColor = COLOR_GREY;
      }
      if (alert) {
        sub = alert;
        subColor = COLOR_RED;
      }
      if (!control && pill && item.kind !== "scene") pill = null;

      // pół kafelka nie ma linii opisu - ostrzeżenie zastępuje wartość
      let valueStyle = { ...parts.value, text: value, color: valueColor };
      if (!parts.sub && alert) valueStyle = { ...parts.value, text: alert, color: COLOR_RED, text_size: parts.smallValue };
      if (t.sub) t.sub.setProperty(hmUI.prop.MORE, { ...parts.sub, text: sub, color: subColor });
      if (t.badge) t.badge.setProperty(hmUI.prop.MORE, { ...parts.badge, text: badge ? badge.text : "", color: badge && badge.alert ? COLOR_RED : COLOR_ORANGE });
      t.value.setProperty(hmUI.prop.VISIBLE, !pill || !!alert);
      t.value.setProperty(hmUI.prop.MORE, valueStyle);
      if (t.pill) {
        t.pill.setProperty(hmUI.prop.VISIBLE, !!pill && !alert);
        t.pillText.setProperty(hmUI.prop.VISIBLE, !!pill && !alert);
        if (pill) {
          t.pill.setProperty(hmUI.prop.MORE, { ...parts.pill, color: pill.on ? COLOR_ON : COLOR_OFF });
          // dotknięte, jeszcze niepotwierdzone - szary napis na pigułce
          t.pillText.setProperty(hmUI.prop.MORE, { ...parts.pillText, text: pill.text, color: pill.pending ? COLOR_GREY : COLOR_TEXT });
        }
      }
    },
  })
);

function splitKey(k) {
  const i = k.indexOf("/");
  return [k.slice(0, i), k.slice(i + 1)];
}

// Zakres i format wartości: z opisu punktu (pkt 14), dla nastawy termostatu - stały (pkt 7)
function specOf(item) {
  const base = item.point === "target" ? TARGET_SPEC : {};
  const pick = (k) => (item[k] !== undefined && item[k] !== null && item[k] !== "" ? item[k] : base[k]);
  return { min: pick("min"), max: pick("max"), step: pick("step"), unit: pick("unit"), decimals: pick("decimals") };
}

function notSent(r) {
  return r ? "Nie wysłano: " + (r.needsLogin ? "zaloguj się" : r.error || "błąd") : "Telefon niedostępny";
}
