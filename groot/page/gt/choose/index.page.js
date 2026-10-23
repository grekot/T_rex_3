// Nowe jajo: wybór linii (3 jajka), potem imienia. Wywołana z parametrem "name" -
// tylko zmiana imienia obecnego Groota (ze statystyk).
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { onKey, offKey, KEY_UP, KEY_DOWN, KEY_SELECT, KEY_EVENT_CLICK } from "@zos/interaction";
import { LINES, LINE_ORDER, NAMES, FORMS, chooseEgg, setName } from "../../../utils/pet";
import { load, apply, newSeed } from "../../../utils/store";
import { COLOR, label, image, rect, button, onTap, goBack } from "../../../utils/ui";
import {
  TITLE,
  EGG_Y,
  EGG_X,
  EGG_SIZE,
  EGG_LABEL,
  EGG_INFO,
  NAME,
  ARROW_L,
  ARROW_R,
  ARROW_SIZE,
  NAME_HINT,
  NEXT_BTN,
} from "zosLoader:./index.page.[pf].layout.js";

function show(w, v) {
  w.setProperty(hmUI.prop.VISIBLE, v);
}

function lineText(id) {
  const L = LINES[id];
  return [L.baby, L.child, L.teen, L.best].map((f) => FORMS[f].name).join(" → ");
}

Page({
  state: {},

  onInit(params) {
    this.state.onlyName = String(params || "").indexOf("name") >= 0;
  },

  build() {
    const s = this.state;
    const p = load().state;
    s.step = s.onlyName ? "name" : "egg";
    s.line = LINE_ORDER.indexOf(p.line) >= 0 ? LINE_ORDER.indexOf(p.line) : 0;
    s.nameIdx = Math.max(0, NAMES.indexOf(p.name || ""));

    s.title = label({ ...TITLE });

    // krok 1: jajka
    s.eggW = [];
    s.highlight = rect(EGG_X[0] - 6, EGG_Y - 6, EGG_SIZE + 12, EGG_SIZE + 12, COLOR.pillOn, 24);
    s.eggW.push(s.highlight);
    LINE_ORDER.forEach((id, i) => {
      const img = image("ui/egg_" + id + ".png", EGG_X[i], EGG_Y);
      const lab = label({ ...EGG_LABEL, x: EGG_X[i] + EGG_SIZE / 2 - EGG_LABEL.w / 2, text: LINES[id].name, color: COLOR.grey });
      onTap([img.widget, lab.widget], () => this.pickLine(i));
      s.eggW.push(img.widget, lab.widget);
    });
    s.eggInfo = label({ ...EGG_INFO, color: COLOR.grey });
    s.eggW.push(s.eggInfo.widget);

    // krok 2: imię
    s.nameW = [];
    s.name = label({ ...NAME, color: COLOR.accent });
    const left = image("ui/arrow_l.png", ARROW_L.x, ARROW_L.y);
    const right = image("ui/arrow_r.png", ARROW_R.x, ARROW_R.y);
    onTap([left.widget], () => this.moveName(-1));
    onTap([right.widget], () => this.moveName(1));
    s.nameHint = label({ ...NAME_HINT, color: COLOR.grey, text: "strzałki albo przyciski góra/dół" });
    s.nameW.push(s.name.widget, left.widget, right.widget, s.nameHint.widget);

    s.next = button({ ...NEXT_BTN, text: "" }, () => this.next());
    this.render();

    try {
      onKey({
        callback: (key, event) => {
          if (key !== KEY_UP && key !== KEY_DOWN && key !== KEY_SELECT) return false;
          if (event !== KEY_EVENT_CLICK) return true;
          if (key === KEY_SELECT) this.next();
          else if (s.step === "egg") this.pickLine((s.line + (key === KEY_UP ? 2 : 1)) % 3);
          else this.moveName(key === KEY_UP ? -1 : 1);
          return true;
        },
      });
      s.keyHooked = true;
    } catch (e) {}
  },

  onDestroy() {
    if (this.state.keyHooked) {
      try {
        offKey();
      } catch (e) {}
    }
  },

  pickLine(i) {
    this.state.line = i;
    this.render();
  },

  moveName(d) {
    const s = this.state;
    s.nameIdx = (s.nameIdx + d + NAMES.length) % NAMES.length;
    this.render();
  },

  next() {
    const s = this.state;
    if (s.step === "egg") {
      s.step = "name";
      this.render();
      return;
    }
    const name = NAMES[s.nameIdx];
    const line = LINE_ORDER[s.line];
    if (s.onlyName) apply((p) => ({ state: setName(p, name) }));
    else apply((p) => ({ state: chooseEgg(p, Date.now(), newSeed(), line, name) }));
    goBack();
  },

  render() {
    const s = this.state;
    const egg = s.step === "egg";
    s.eggW.forEach((w) => show(w, egg));
    s.nameW.forEach((w) => show(w, !egg));
    if (egg) {
      s.title.set("Wybierz doniczkę");
      s.highlight.setProperty(hmUI.prop.MORE, {
        x: px(EGG_X[s.line] - 6),
        y: px(EGG_Y - 6),
        w: px(EGG_SIZE + 12),
        h: px(EGG_SIZE + 12),
        radius: px(24),
        color: COLOR.pillOn,
      });
      s.eggInfo.set(lineText(LINE_ORDER[s.line]));
      s.next.txt.set("Dalej ›");
    } else {
      s.title.set("Imię");
      s.name.set(NAMES[s.nameIdx] || "bez imienia", NAMES[s.nameIdx] ? COLOR.accent : COLOR.grey);
      s.next.txt.set("Gotowe");
    }
  },
});
