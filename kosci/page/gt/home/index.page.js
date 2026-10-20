// Stół: kości, suma, przycisk RZUĆ. Rzut także potrząśnięciem i przyciskiem zegarka,
// stuknięcie w kość zatrzymuje ją przy następnym rzucie.
import * as hmUI from "@zos/ui";
import { push } from "@zos/router";
import { onKey, offKey, KEY_UP, KEY_DOWN, KEY_EVENT_CLICK, showToast } from "@zos/interaction";
import { VIBRATOR_SCENE_SHORT_MIDDLE } from "@zos/sensor";
import {
  PIP_SPOTS,
  TUMBLE_DELAYS,
  configLabel,
  layoutDice,
  pipsFor,
  rollHand,
  tumbleFaces,
  toggleLock,
  allLocked,
  summary,
  createShakeDetector,
} from "../../../utils/dice";
import { loadConfig, configStamp, loadHand, saveHand } from "../../../utils/store";
import { startAccel, readAccel, stopAccel, setupScreen, createBuzzer } from "../../../utils/device";
import {
  CONFIG_BG,
  CONFIG_STYLE,
  SUMMARY_STYLE,
  PREV_STYLE,
  ROLL_BG,
  ROLL_STYLE,
  DIE_COLORS,
  LOCKED_COLORS,
  PIP_ONE_COLOR,
  COLOR_TEXT,
  COLOR_GREY,
  COLOR_ORANGE,
  dieGeometry,
} from "zosLoader:./index.page.[pf].layout.js";

const SETUP_PAGE = "page/gt/setup/index.page";
const CONFIG_POLL_MS = 1000; // po powrocie z ustawień
const ACCEL_POLL_MS = 40;

function onTap(widgets, handler) {
  widgets.forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, handler));
}

// setProperty tylko gdy wartość się zmieniła - przy toczeniu to dziesiątki widżetów na klatkę
function setCached(cache, key, value, apply) {
  if (cache[key] === value) return;
  cache[key] = value;
  apply();
}

Page({
  state: {},

  build() {
    const s = this.state;
    s.dice = [];
    s.rolling = false;
    s.buzzer = createBuzzer();
    s.shake = createShakeDetector();
    setupScreen();

    s.configBg = hmUI.createWidget(hmUI.widget.FILL_RECT, CONFIG_BG);
    s.configText = hmUI.createWidget(hmUI.widget.TEXT, CONFIG_STYLE);
    onTap([s.configBg, s.configText], () => {
      if (!s.rolling) push({ url: SETUP_PAGE });
    });

    s.summary = hmUI.createWidget(hmUI.widget.TEXT, SUMMARY_STYLE);
    s.prev = hmUI.createWidget(hmUI.widget.TEXT, PREV_STYLE);
    s.rollBg = hmUI.createWidget(hmUI.widget.FILL_RECT, ROLL_BG);
    s.rollText = hmUI.createWidget(hmUI.widget.TEXT, ROLL_STYLE);
    onTap([s.rollBg, s.rollText], () => this.roll());

    this.applyConfig();
    s.configTimer = setInterval(() => {
      if (configStamp() !== s.stamp && !s.rolling) this.applyConfig();
    }, CONFIG_POLL_MS);

    try {
      onKey({
        callback: (key, event) => {
          if (key !== KEY_UP && key !== KEY_DOWN) return false;
          if (event === KEY_EVENT_CLICK) this.roll();
          return true;
        },
      });
      s.keyHooked = true;
    } catch (e) {}
  },

  onDestroy() {
    const s = this.state;
    if (s.configTimer) clearInterval(s.configTimer);
    if (s.frameTimer) clearTimeout(s.frameTimer);
    this.stopShake();
    if (s.keyHooked) {
      try {
        offKey();
      } catch (e) {}
    }
    s.buzzer.stop();
  },

  // Ustawienia z pamięci -> kości na ekranie (przy starcie i po zmianie w ustawieniach)
  applyConfig() {
    const s = this.state;
    s.stamp = configStamp();
    s.cfg = loadConfig();
    s.hand = loadHand(s.cfg);
    s.configText.setProperty(hmUI.prop.MORE, { ...CONFIG_STYLE, text: configLabel(s.cfg) + "  ›" });
    this.buildDice();
    this.render(s.hand.values);
    if (s.cfg.shake) this.startShake();
    else this.stopShake();
  },

  buildDice() {
    const s = this.state;
    s.dice.forEach((d) => d.widgets.forEach((w) => hmUI.deleteWidget(w)));
    s.dice = layoutDice(s.cfg.count).map((spot, i) => {
      const g = dieGeometry(spot);
      const shadow = hmUI.createWidget(hmUI.widget.FILL_RECT, { ...g.shadow, color: 0x000000 });
      const face = hmUI.createWidget(hmUI.widget.FILL_RECT, { ...g.face, color: 0x000000 });
      const pips = PIP_SPOTS.map((p) => hmUI.createWidget(hmUI.widget.CIRCLE, { ...g.pip(p), color: 0x000000 }));
      const text = hmUI.createWidget(hmUI.widget.TEXT, { ...g.text, color: 0x000000 });
      const widgets = [shadow, face, ...pips, text];
      onTap(widgets, () => this.toggle(i));
      return { g, shadow, face, pips, text, widgets, cache: {} };
    });
  },

  // Rysuje ścianki (values = null: kości jeszcze nie rzucone, pokazuje "?")
  render(values) {
    const s = this.state;
    const sides = s.cfg.sides;
    s.dice.forEach((d, i) => {
      const locked = !!(s.hand.values && s.hand.locked[i]);
      const [faceColor, shadowColor, inkColor] = locked ? LOCKED_COLORS : DIE_COLORS[sides];
      setCached(d.cache, "face", faceColor, () => d.face.setProperty(hmUI.prop.MORE, { ...d.g.face, color: faceColor }));
      setCached(d.cache, "shadow", shadowColor, () =>
        d.shadow.setProperty(hmUI.prop.MORE, { ...d.g.shadow, color: shadowColor }),
      );
      const value = values ? values[i] : null;
      const showPips = sides === 6 && value !== null;
      const on = showPips ? pipsFor(value) : null;
      d.pips.forEach((pip, k) => {
        const visible = !!(on && on[k]);
        setCached(d.cache, "v" + k, visible, () => pip.setProperty(hmUI.prop.VISIBLE, visible));
        if (!visible) return;
        const color = value === 1 && !locked ? PIP_ONE_COLOR : inkColor;
        setCached(d.cache, "c" + k, color, () =>
          pip.setProperty(hmUI.prop.MORE, { ...d.g.pip(PIP_SPOTS[k]), color }),
        );
      });
      const label = showPips ? "" : value === null ? "?" : String(value);
      setCached(d.cache, "text", label + "/" + inkColor, () =>
        d.text.setProperty(hmUI.prop.MORE, { ...d.g.text, text: label, color: inkColor }),
      );
    });
    if (!s.rolling) this.renderSummary();
  },

  renderSummary() {
    const s = this.state;
    const h = s.hand;
    if (!h.values) {
      s.summary.setProperty(hmUI.prop.MORE, {
        ...SUMMARY_STYLE,
        text: s.cfg.shake ? "Rzuć albo potrząśnij" : "Stuknij RZUĆ",
        text_size: SUMMARY_STYLE.text_size - 4,
        color: COLOR_GREY,
      });
      s.prev.setProperty(hmUI.prop.MORE, { ...PREV_STYLE, text: "" });
    } else {
      const sm = summary(h);
      s.summary.setProperty(hmUI.prop.MORE, {
        ...SUMMARY_STYLE,
        text: [sm.extra, sm.main].filter(Boolean).join("  "),
        color: sm.extra ? COLOR_ORANGE : COLOR_TEXT,
      });
      let prev = "";
      if (h.prev !== null && h.count > 1) prev = "poprzednio " + h.prev;
      else if (h.count > 1 && !h.locked.some(Boolean)) prev = "stuknij kość = zatrzymaj";
      s.prev.setProperty(hmUI.prop.MORE, { ...PREV_STYLE, text: prev });
    }
    const blocked = allLocked(h);
    s.rollBg.setProperty(hmUI.prop.MORE, { ...ROLL_BG, color: blocked ? 0x3a3a3a : ROLL_BG.color });
  },

  toggle(i) {
    const s = this.state;
    if (s.rolling || !s.hand.values || s.cfg.count < 2) return;
    s.hand = toggleLock(s.hand, i);
    saveHand(s.hand);
    this.render(s.hand.values);
  },

  roll() {
    const s = this.state;
    if (s.rolling) return;
    if (allLocked(s.hand)) {
      try {
        showToast({ content: "Wszystkie kości zatrzymane" });
      } catch (e) {}
      return;
    }
    s.rolling = true;
    s.shake.quiet(Date.now());
    s.summary.setProperty(hmUI.prop.MORE, { ...SUMMARY_STYLE, text: "", color: COLOR_TEXT });
    s.prev.setProperty(hmUI.prop.MORE, { ...PREV_STYLE, text: "" });
    let frame = 0;
    const next = () => {
      if (frame < TUMBLE_DELAYS.length) {
        this.render(tumbleFaces(s.hand));
        s.frameTimer = setTimeout(next, TUMBLE_DELAYS[frame++]);
        return;
      }
      s.frameTimer = null;
      s.hand = rollHand(s.hand);
      saveHand(s.hand);
      s.rolling = false;
      this.render(s.hand.values);
      s.buzzer.buzz(VIBRATOR_SCENE_SHORT_MIDDLE);
      s.shake.quiet(Date.now());
    };
    next();
  },

  startShake() {
    const s = this.state;
    if (s.accel) return;
    s.accel = startAccel();
    if (!s.accel.sensor) {
      s.accel = null;
      return;
    }
    s.accelTimer = setInterval(() => {
      if (s.shake.feed(readAccel(s.accel), Date.now())) this.roll();
    }, ACCEL_POLL_MS);
  },

  stopShake() {
    const s = this.state;
    if (s.accelTimer) clearInterval(s.accelTimer);
    s.accelTimer = null;
    stopAccel(s.accel);
    s.accel = null;
  },
});
