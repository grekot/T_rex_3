// Ustawienia: ile kości, jaki rodzaj, czy potrząśnięcie rzuca. Zapis od razu przy każdej
// zmianie - strona kości zauważa go po powrocie.
import * as hmUI from "@zos/ui";
import { back } from "@zos/router";
import { DICE_TYPES, MAX_DICE, typeLabel } from "../../../utils/dice";
import { loadConfig, saveConfig } from "../../../utils/store";
import {
  TITLE_STYLE,
  COUNT_LABEL,
  MINUS_BG,
  PLUS_BG,
  MINUS_STYLE,
  PLUS_STYLE,
  COUNT_STYLE,
  TYPE_LABEL,
  typeBg,
  typeStyle,
  shakeBg,
  shakeStyle,
  DONE_BG,
  DONE_STYLE,
  COLOR_TEXT,
  COLOR_GREY,
} from "zosLoader:./index.page.[pf].layout.js";

function onTap(widgets, handler) {
  widgets.forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, handler));
}

Page({
  state: {},

  build() {
    const s = this.state;
    s.cfg = loadConfig();

    hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);
    hmUI.createWidget(hmUI.widget.TEXT, COUNT_LABEL);

    s.minusBg = hmUI.createWidget(hmUI.widget.FILL_RECT, MINUS_BG);
    s.minus = hmUI.createWidget(hmUI.widget.TEXT, MINUS_STYLE);
    s.plusBg = hmUI.createWidget(hmUI.widget.FILL_RECT, PLUS_BG);
    s.plus = hmUI.createWidget(hmUI.widget.TEXT, PLUS_STYLE);
    s.count = hmUI.createWidget(hmUI.widget.TEXT, COUNT_STYLE);
    onTap([s.minusBg, s.minus], () => this.change({ count: Math.max(1, s.cfg.count - 1) }));
    onTap([s.plusBg, s.plus], () => this.change({ count: Math.min(MAX_DICE, s.cfg.count + 1) }));

    hmUI.createWidget(hmUI.widget.TEXT, TYPE_LABEL);
    s.types = DICE_TYPES.map((sides, i) => {
      const bg = hmUI.createWidget(hmUI.widget.FILL_RECT, typeBg(i, false));
      const text = hmUI.createWidget(hmUI.widget.TEXT, typeStyle(i, typeLabel(sides)));
      onTap([bg, text], () => this.change({ sides }));
      return bg;
    });

    s.shakeBg = hmUI.createWidget(hmUI.widget.FILL_RECT, shakeBg(true));
    s.shakeText = hmUI.createWidget(hmUI.widget.TEXT, shakeStyle(true));
    onTap([s.shakeBg, s.shakeText], () => this.change({ shake: !s.cfg.shake }));

    const doneBg = hmUI.createWidget(hmUI.widget.FILL_RECT, DONE_BG);
    const done = hmUI.createWidget(hmUI.widget.TEXT, DONE_STYLE);
    onTap([doneBg, done], () => {
      try {
        back();
      } catch (e) {}
    });

    this.render();
  },

  change(patch) {
    const s = this.state;
    s.cfg = { ...s.cfg, ...patch };
    saveConfig(s.cfg);
    this.render();
  },

  render() {
    const s = this.state;
    const c = s.cfg;
    s.count.setProperty(hmUI.prop.MORE, { ...COUNT_STYLE, text: String(c.count) });
    s.minus.setProperty(hmUI.prop.MORE, { ...MINUS_STYLE, color: c.count > 1 ? COLOR_TEXT : COLOR_GREY });
    s.plus.setProperty(hmUI.prop.MORE, { ...PLUS_STYLE, color: c.count < MAX_DICE ? COLOR_TEXT : COLOR_GREY });
    s.types.forEach((bg, i) => bg.setProperty(hmUI.prop.MORE, typeBg(i, DICE_TYPES[i] === c.sides)));
    s.shakeBg.setProperty(hmUI.prop.MORE, shakeBg(c.shake));
    s.shakeText.setProperty(hmUI.prop.MORE, shakeStyle(c.shake));
  },
});
