// „Dodaj szczyt tutaj”: szczyt spoza list zapisany w miejscu, w którym stoisz (GPS), z dzisiejszą datą.
// Nazwa z klawiatury zegarka (gdy jest), inaczej „Szczyt N” - można ją potem zmienić w szczegółach.
// Jeśli stoisz na szczycie z listy, podpowiadamy zaliczenie jego zamiast dodawania nowego.
import * as hmUI from "@zos/ui";
import { back, replace } from "@zos/router";
import { showToast } from "@zos/interaction";
import { px } from "@zos/utils";
import { allPeaks } from "../../../utils/peaks";
import { summitAt, climbOf, todayKey, newCustomId, autoName } from "../../../utils/korona";
import { loadClimbs, loadCustom, saveClimb, saveCustomPeak } from "../../../utils/store";
import { startGps } from "../../../utils/sensors";
import { setupScreen } from "../../../utils/device";
import { canType, askText } from "../../../utils/input";
import { button, setText, onTap, COLOR_WHITE, COLOR_GREY, COLOR_GREEN, COLOR_ORANGE } from "../../../utils/ui";
import {
  TITLE_STYLE,
  NAME_BG,
  NAME_STYLE,
  NAME_HINT_STYLE,
  POS_STYLE,
  INFO_STYLE,
  SAVE_RECT,
  OTHER_RECT,
} from "zosLoader:./index.page.[pf].layout.js";

const PEAK_PAGE = "page/gt/peak/index.page";

// 49.65532 N, 20.27667 E
function formatPos(fix) {
  const f = (v, pos, neg) => Math.abs(v).toFixed(5) + " " + (v >= 0 ? pos : neg);
  return f(fix.lat, "N", "S") + ", " + f(fix.lon, "E", "W");
}

Page({
  state: {},

  build() {
    const s = this.state;
    s.fix = null;
    s.custom = loadCustom();
    s.climbs = loadClimbs();
    s.peaks = allPeaks(s.custom);
    s.name = autoName(s.custom);
    s.typed = false;
    s.save = null;
    s.other = null;
    s.key = "";
    setupScreen(60000);

    hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);
    const nameBg = hmUI.createWidget(hmUI.widget.FILL_RECT, NAME_BG);
    s.nameText = hmUI.createWidget(hmUI.widget.TEXT, { ...NAME_STYLE, text: s.name });
    hmUI.createWidget(hmUI.widget.TEXT, {
      ...NAME_HINT_STYLE,
      text: canType() ? "stuknij, żeby wpisać nazwę" : "nazwę zmienisz później w szczegółach",
    });
    if (canType()) onTap([nameBg, s.nameText], () => this.typeName());
    s.pos = hmUI.createWidget(hmUI.widget.TEXT, POS_STYLE);
    s.info = hmUI.createWidget(hmUI.widget.TEXT, INFO_STYLE);
    this.render();

    s.gps = startGps((fix) => {
      if (fix) s.fix = fix;
      this.render();
    });
  },

  onDestroy() {
    if (this.state.gps) this.state.gps.stop();
  },

  typeName() {
    askText((text) => {
      const s = this.state;
      s.name = String(text).trim().slice(0, 40) || s.name;
      s.typed = true;
      setText(s.nameText, NAME_STYLE, s.name, COLOR_WHITE);
    });
  },

  render() {
    const s = this.state;
    if (!s.fix) {
      setText(s.pos, POS_STYLE, "Szukam GPS...", COLOR_ORANGE);
      setText(s.info, INFO_STYLE, "Zapiszę szczyt w miejscu, w którym stoisz. Poczekaj na pozycję.");
      this.setButtons("wait");
      return;
    }
    setText(s.pos, POS_STYLE, formatPos(s.fix), COLOR_WHITE);
    const at = summitAt(s.fix, s.peaks);
    s.known = at ? at.peak : null;
    if (s.known) {
      const done = climbOf(s.known.id, s.climbs, s.custom);
      setText(
        s.info,
        INFO_STYLE,
        "Stoisz na szczycie " + s.known.name + (done ? " (już zdobyty)." : " z listy - zalicz go zamiast dodawać nowy."),
        COLOR_GREEN
      );
      this.setButtons(done ? "known-done" : "known");
    } else {
      setText(s.info, INFO_STYLE, "Szczyt trafi do listy „Moje szczyty” z dzisiejszą datą.", COLOR_GREY);
      this.setButtons("new");
    }
  },

  setButtons(key) {
    const s = this.state;
    if (s.key === key) return;
    s.key = key;
    [s.save, s.other].forEach((w) => w && hmUI.deleteWidget(w));
    s.save = null;
    s.other = null;
    if (key === "new") s.save = button(SAVE_RECT, "Zapisz szczyt", "success", () => this.saveNew());
    if (key === "known") {
      s.save = button(SAVE_RECT, "Zalicz " + s.known.name, "success", () => this.climbKnown(), px(24));
      s.other = button(OTHER_RECT, "Mimo to dodaj", "secondary", () => this.saveNew(), px(22));
    }
    if (key === "known-done") s.other = button(OTHER_RECT, "Mimo to dodaj", "secondary", () => this.saveNew(), px(22));
  },

  saveNew() {
    const s = this.state;
    if (!s.fix) return;
    const custom = loadCustom();
    const id = newCustomId(Date.now(), custom);
    const name = s.typed ? s.name : autoName(custom);
    saveCustomPeak(id, { name, lat: s.fix.lat, lon: s.fix.lon, d: todayKey(Date.now()), gps: true });
    try {
      showToast({ content: "Dodano: " + name });
    } catch (e) {}
    back();
  },

  climbKnown() {
    const s = this.state;
    if (!s.known) return;
    saveClimb(s.known.id, todayKey(Date.now()), true);
    try {
      showToast({ content: "Zaliczone: " + s.known.name });
    } catch (e) {}
    replace({ url: PEAK_PAGE, params: JSON.stringify({ id: s.known.id }) });
  },
});
