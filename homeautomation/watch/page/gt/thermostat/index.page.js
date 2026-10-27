// Ekran termostatu: temperatura w pokoju, nastawa − / + co 0,5 °C, płomień przy grzaniu, tryb
// RĘCZNY | AUTO, temperatura na zewnątrz, ostrzeżenia. Dane idą przez Side Service (telefon) i Firebase
// Realtime Database; strona pyta o stan co ~5 s tylko wtedy, gdy jest otwarta.
// Naciśnięcia − / + (także przyciski zegarka góra/dół) zbieramy i wysyłamy jedno polecenie po 1 s
// bez dotyku. Otwiera ją kafelek termostatu na liście (params: {"id": deviceId}).
import * as hmUI from "@zos/ui";
import { onKey, offKey, KEY_UP, KEY_DOWN, KEY_EVENT_CLICK } from "@zos/interaction";
import { setWakeUpRelaunch, setPageBrightTime } from "@zos/display";
import { BasePage } from "@zeppos/zml/base-page";
import {
  SEND_DELAY_MS,
  ACK_TIMEOUT_MS,
  formatTemp,
  warningOf,
  modeInfo,
  outdoorText,
  pressTarget,
  chooseValue,
  sendDue,
  needsSend,
  shownValue,
  settleLocal,
  applyAck,
} from "../../../utils/termostat";
import { ask, setTop, onTap, toast, parseParams } from "../../../utils/page";
import { canControl } from "../../../utils/home";
import {
  NAME_STYLE,
  ALERT_STYLE,
  TEMP_STYLE,
  FLAME_IMG,
  OUTDOOR_STYLE,
  MINUS_BTN,
  PLUS_BTN,
  TARGET_LABEL_STYLE,
  TARGET_STYLE,
  MODE_BG,
  modeSegment,
  modeText,
  INFO_STYLE,
  MSG_STYLE,
  CENTER_STYLE,
  COLOR_TEXT,
  COLOR_GREY,
  COLOR_ORANGE,
  COLOR_RED,
  COLOR_PILL,
  COLOR_PILL_DOWN,
} from "zosLoader:./index.page.[pf].layout.js";

const POLL_MS = 5000;
const POLL_AFTER_SEND_MS = 2000; // pierwsze sprawdzenie potwierdzenia
const DOUBLE_TAP_MS = 150; // jedno dotknięcie trafia i w koło, i w napis na nim
const MODES = ["manual", "auto"];

Page(
  BasePage({
    state: {},

    onInit(params) {
      const p = parseParams(params);
      this.state.id = typeof p.id === "string" ? p.id : null;
      this.state.title = typeof p.name === "string" ? p.name : "";
      this.state.home = typeof p.home === "string" ? p.home : null;
      // dostęp „view” (API.md pkt 12): sam podgląd, bez − / + i przełączania trybu
      this.state.control = canControl(p.level);
      setTop("thermostat");
    },

    build() {
      const s = this.state;
      s.view = null;
      s.screen = "Łączenie z telefonem...";
      s.localTarget = null;
      s.localMode = null;
      s.queue = [];
      s.taps = {};
      try {
        setWakeUpRelaunch({ relaunch: true });
      } catch (e) {}
      try {
        setPageBrightTime({ brightTime: 30000 });
      } catch (e) {}

      s.name = hmUI.createWidget(hmUI.widget.TEXT, NAME_STYLE);
      s.center = hmUI.createWidget(hmUI.widget.TEXT, CENTER_STYLE);

      const main = [];
      const add = (w) => {
        main.push(w);
        return w;
      };
      s.alert = add(hmUI.createWidget(hmUI.widget.TEXT, ALERT_STYLE));
      s.temp = add(hmUI.createWidget(hmUI.widget.TEXT, TEMP_STYLE));
      s.flame = hmUI.createWidget(hmUI.widget.IMG, FLAME_IMG);
      s.outdoor = add(hmUI.createWidget(hmUI.widget.TEXT, OUTDOOR_STYLE));
      add(hmUI.createWidget(hmUI.widget.TEXT, TARGET_LABEL_STYLE));
      s.target = add(hmUI.createWidget(hmUI.widget.TEXT, TARGET_STYLE));
      s.buttons = [];
      [MINUS_BTN, PLUS_BTN].forEach((spec, i) => {
        const dir = i ? 1 : -1;
        const circle = hmUI.createWidget(hmUI.widget.CIRCLE, spec.circle);
        const label = hmUI.createWidget(hmUI.widget.TEXT, spec.text);
        s.buttons.push(circle, label);
        const down = () => circle.setProperty(hmUI.prop.MORE, { ...spec.circle, color: COLOR_PILL_DOWN });
        const up = () => circle.setProperty(hmUI.prop.MORE, { ...spec.circle, color: COLOR_PILL });
        [circle, label].forEach((w) => {
          w.addEventListener(hmUI.event.CLICK_DOWN, down);
          w.addEventListener(hmUI.event.MOVE_OUT, up);
        });
        onTap([circle, label], () => {
          up();
          if (this.once(dir > 0 ? "plus" : "minus")) this.press(dir);
        });
      });
      add(hmUI.createWidget(hmUI.widget.FILL_RECT, MODE_BG));
      s.segments = MODES.map((mode, i) => {
        const bg = add(hmUI.createWidget(hmUI.widget.FILL_RECT, modeSegment(i)));
        const label = add(hmUI.createWidget(hmUI.widget.TEXT, modeText(i, i ? "AUTO" : "RĘCZNY")));
        onTap([bg, label], () => {
          if (this.once("mode")) this.chooseMode(mode);
        });
        return { bg, label, mode };
      });
      s.info = add(hmUI.createWidget(hmUI.widget.TEXT, INFO_STYLE));
      s.msg = add(hmUI.createWidget(hmUI.widget.TEXT, MSG_STYLE));
      s.main = main;

      try {
        onKey({
          callback: (key, event) => {
            if (!this.state.control || (key !== KEY_UP && key !== KEY_DOWN)) return false;
            if (event === KEY_EVENT_CLICK) this.press(key === KEY_UP ? 1 : -1);
            return true;
          },
        });
        s.keyHooked = true;
      } catch (e) {}

      this.render();
      if (s.id) this.poll();
      else this.showScreen("Brak urządzenia");
    },

    onDestroy() {
      const s = this.state;
      s.destroyed = true;
      setTop("home");
      if (s.pollTimer) clearTimeout(s.pollTimer);
      if (s.sendTimer) clearTimeout(s.sendTimer);
      if (s.keyHooked) {
        try {
          offKey();
        } catch (e) {}
      }
    },

    // Telefon dał znać, że w ustawieniach zalogowano się - odśwież od razu
    onCall(req) {
      if (req && req.type === "LOGGED_IN") this.pollSoon(0);
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
      s.polling = true;
      const done = (result, failed) => {
        s.polling = false;
        if (s.destroyed) return;
        if (failed) this.phoneDown();
        else this.received(result || {});
        const again = s.pollAgain;
        s.pollAgain = false;
        this.pollSoon(again ? 0 : POLL_MS);
      };
      ask(this, { method: "POLL", params: { home: s.home, id: s.id, pending: s.awaitKey || null } })
        .then((r) => done(r, false))
        .catch(() => done(null, true));
    },

    phoneDown() {
      const s = this.state;
      s.phoneDown = true;
      if (!s.view) s.screen = "Brak połączenia z telefonem";
      this.checkAckTimeout();
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
        else if (s.view) s.error = r.error || "błąd";
        else s.screen = "Błąd: " + (r.error || "nieznany");
        return this.render();
      }
      const v = r.view || { hasData: false };
      s.view = v;
      if (!v.hasData) s.screen = "Termostat nie wysłał jeszcze danych do chmury";

      if (s.awaitKey && r.ack) {
        toast(r.ack.text);
        s.localTarget = applyAck(s.localTarget, r.ack, s.awaitKey, now);
        s.localMode = applyAck(s.localMode, r.ack, s.awaitKey, now);
        s.awaitKey = null;
      }
      this.checkAckTimeout();
      s.localTarget = settleLocal(s.localTarget, v.target, now);
      s.localMode = settleLocal(s.localMode, v.mode, now);
      this.render();
    },

    checkAckTimeout() {
      const s = this.state;
      if (!s.awaitKey || Date.now() - s.awaitAt < ACK_TIMEOUT_MS) return;
      s.awaitKey = null;
      toast(s.view && s.view.offline ? "Termostat nie odpowiada" : "Brak potwierdzenia");
    },

    showScreen(text) {
      const s = this.state;
      s.view = null;
      this.forget();
      s.screen = text;
      this.render();
    },

    // Zmiany niewysłane / niepotwierdzone - po wylogowaniu
    forget() {
      const s = this.state;
      if (s.sendTimer) clearTimeout(s.sendTimer);
      s.sendTimer = null;
      s.localTarget = null;
      s.localMode = null;
      s.awaitKey = null;
    },

    // --- zmiany ---

    press(dir) {
      const s = this.state;
      const v = s.view;
      if (!v || !v.hasData || !s.control) return;
      s.localTarget = pressTarget(s.localTarget, v.target, dir, Date.now());
      this.render();
      if (s.sendTimer) clearTimeout(s.sendTimer);
      s.sendTimer = setTimeout(() => {
        s.sendTimer = null;
        this.flush();
      }, SEND_DELAY_MS);
    },

    chooseMode(mode) {
      const s = this.state;
      const v = s.view;
      if (!v || !v.hasData || !s.control || shownValue(s.localMode, v.mode) === mode) return;
      // najpierw zebrana nastawa, potem tryb - w tej kolejności dotrą do termostatu
      s.localTarget = s.localTarget && !s.localTarget.sentAt ? { ...s.localTarget, touchedAt: 0 } : s.localTarget;
      s.localMode = chooseValue(s.localMode, mode, Date.now());
      this.flush();
      this.render();
    },

    flush() {
      const s = this.state;
      const v = s.view;
      if (!v || !v.hasData) return;
      const now = Date.now();
      if (sendDue(s.localTarget, now)) {
        if (needsSend(s.localTarget, v.target)) {
          s.localTarget = { ...s.localTarget, sentAt: now };
          s.queue.push({ values: { target: s.localTarget.value }, field: "localTarget", local: s.localTarget });
        } else s.localTarget = null;
      }
      if (sendDue(s.localMode, now)) {
        if (needsSend(s.localMode, v.mode)) {
          s.localMode = { ...s.localMode, sentAt: now };
          s.queue.push({ values: { mode: s.localMode.value }, field: "localMode", local: s.localMode });
        } else s.localMode = null;
      }
      this.sendNext();
      this.render();
    },

    // Polecenia po kolei, żeby termostat dostał je w kolejności naciśnięć
    sendNext() {
      const s = this.state;
      if (s.sending || !s.queue.length || s.destroyed) return;
      const item = s.queue.shift();
      s.sending = true;
      const done = (r) => {
        s.sending = false;
        if (s.destroyed) return;
        const mine = (it) => s[it.field] && s[it.field].sentAt === it.local.sentAt;
        if (r && r.ok && r.key) {
          if (mine(item)) s[item.field] = { ...s[item.field], key: r.key };
          s.awaitKey = r.key;
          s.awaitAt = Date.now();
          this.pollSoon(POLL_AFTER_SEND_MS);
        } else {
          // nie wysłano - ekran wraca do wartości z bazy, kolejne polecenia też przepadają
          [item].concat(s.queue).forEach((it) => {
            if (mine(it)) s[it.field] = null;
          });
          s.queue = [];
          toast(r ? "Nie wysłano: " + (r.needsLogin ? "zaloguj się" : r.error || "błąd") : "Telefon niedostępny");
        }
        this.render();
        this.sendNext();
      };
      ask(this, { method: "SET", params: { home: s.home, id: s.id, values: item.values } })
        .then((r) => done(r || null))
        .catch(() => done(null));
    },

    // --- ekran ---

    render() {
      const s = this.state;
      const v = s.view;
      const hasData = !!(v && v.hasData);
      s.name.setProperty(hmUI.prop.TEXT, (v && v.name) || s.title || s.id || "TERMOSTAT");
      s.center.setProperty(hmUI.prop.VISIBLE, !hasData);
      s.main.forEach((w) => w.setProperty(hmUI.prop.VISIBLE, hasData));
      s.buttons.forEach((w) => w.setProperty(hmUI.prop.VISIBLE, hasData && s.control));
      s.flame.setProperty(hmUI.prop.VISIBLE, hasData && v.heating && !v.offline);
      if (!hasData) {
        s.center.setProperty(hmUI.prop.TEXT, s.screen || "");
        return;
      }

      const warning = warningOf(v);
      if (warning) s.alert.setProperty(hmUI.prop.MORE, { ...ALERT_STYLE, text: warning, color: COLOR_RED });
      else s.alert.setProperty(hmUI.prop.TEXT, "");
      s.temp.setProperty(hmUI.prop.MORE, {
        ...TEMP_STYLE,
        text: formatTemp(v.temp),
        color: v.offline || v.sensorFault ? COLOR_GREY : COLOR_TEXT,
      });
      s.outdoor.setProperty(hmUI.prop.TEXT, outdoorText(v));

      const pendingTarget = !!s.localTarget;
      s.target.setProperty(hmUI.prop.MORE, {
        ...TARGET_STYLE,
        text: formatTemp(shownValue(s.localTarget, v.target)),
        color: pendingTarget ? COLOR_TEXT : COLOR_ORANGE,
      });

      const mode = shownValue(s.localMode, v.mode);
      s.segments.forEach((seg, i) => {
        seg.bg.setProperty(hmUI.prop.VISIBLE, seg.mode === mode);
        seg.label.setProperty(hmUI.prop.MORE, { ...modeText(i, i ? "AUTO" : "RĘCZNY"), color: seg.mode === mode ? COLOR_TEXT : COLOR_GREY });
      });
      const info = modeInfo(v, mode);
      s.info.setProperty(hmUI.prop.MORE, { ...INFO_STYLE, text: info.text, color: info.override ? COLOR_ORANGE : COLOR_GREY });

      let msg = "";
      if (s.phoneDown) msg = "Telefon niedostępny";
      else if (s.error) msg = "Błąd: " + s.error;
      else if (s.sending || s.queue.length) msg = "Wysyłanie...";
      else if (s.awaitKey) msg = "Czekam na termostat...";
      s.msg.setProperty(hmUI.prop.TEXT, msg);
    },
  })
);
