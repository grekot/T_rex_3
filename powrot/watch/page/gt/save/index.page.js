// Zapisywanie bieżącego miejsca: wybierasz nazwę (gotowa albo wpisana), zapis następuje
// od razu albo - gdy GPS jeszcze szuka - automatycznie po ustaleniu pozycji.
import * as hmUI from "@zos/ui";
import { back } from "@zos/router";
import { showToast } from "@zos/interaction";
import { Vibrator, VIBRATOR_SCENE_SHORT_MIDDLE } from "@zos/sensor";
import { px } from "@zos/utils";
import { BasePage } from "@zeppos/zml/base-page";
import { viewPlaces, addOps, sync } from "../../../utils/store";
import { savePlaceOps } from "../../../utils/places";
import { PRESET_NAMES } from "../../../utils/points";
import { startGps } from "../../../utils/sensors";
import { STABLE_FIXES, averageFix } from "../../../utils/geo";
import { stayInApp, keepBright } from "../../../utils/screen";
import { setCovered } from "../../../utils/cover";
import { canType, askText } from "../../../utils/input";
import { button, gridRect, COLOR_GREEN, COLOR_WHITE, COLOR_ORANGE } from "../../../utils/ui";
import {
  DEVICE_WIDTH,
  TITLE_STYLE,
  STATUS_STYLE,
  GRID_TOP,
  bottomSpacerProps,
} from "zosLoader:./index.page.[pf].layout.js";

Page(
  BasePage({
  state: {
    status: null,
    fix: null,
    fixes: 0,
    recent: [], // ostatnie odczyty GPS do uśrednienia
    startedAt: 0,
    gps: null,
    timer: null,
    saved: false,
    pending: null, // nazwa wybrana przed ustaleniem pozycji
  },

  build() {
    const s = this.state;
    stayInApp();
    keepBright(60000);
    hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);
    s.status = hmUI.createWidget(hmUI.widget.TEXT, STATUS_STYLE);

    const names = PRESET_NAMES.concat(canType() ? ["Wpisz nazwę"] : []).concat(["Bez nazwy"]);
    names.forEach((name, i) => {
      const kind = i < PRESET_NAMES.length ? "primary" : "secondary";
      button(gridRect(i, GRID_TOP, DEVICE_WIDTH), name, kind, () => this.choose(name));
    });
    const last = gridRect(names.length - 1, GRID_TOP, DEVICE_WIDTH);
    hmUI.createWidget(hmUI.widget.FILL_RECT, bottomSpacerProps(last.y + last.h + px(10)));

    s.startedAt = Date.now();
    s.gps = startGps((fix) => {
      if (fix) {
        s.fixes++;
        s.recent = s.recent.concat([fix]).slice(-STABLE_FIXES);
        s.fix = averageFix(s.recent);
      }
      if (this.ready() && s.pending !== null) this.save(s.pending);
      else this.updateStatus();
    });
    // Licznik sekund, gdy GPS jeszcze szuka
    s.timer = setInterval(() => this.updateStatus(), 1000);
  },

  onDestroy() {
    const s = this.state;
    setCovered(false);
    if (s.gps) s.gps.stop();
    if (s.timer) clearInterval(s.timer);
  },

  ready() {
    return this.state.fixes >= STABLE_FIXES;
  },

  updateStatus() {
    const s = this.state;
    if (s.saved) return;
    let text;
    let color = COLOR_WHITE;
    if (this.ready()) {
      text = "Pozycja ustalona\nwybierz nazwę";
      color = COLOR_GREEN;
    } else if (s.fix) {
      const next = s.pending !== null ? "zapiszę: " + (s.pending || "Bez nazwy") : "możesz już wybrać nazwę";
      text = "Ustalam pozycję... " + s.fixes + "/" + STABLE_FIXES + "\n" + next;
      if (s.pending !== null) color = COLOR_ORANGE;
    } else {
      const sec = Math.floor((Date.now() - s.startedAt) / 1000);
      if (s.pending !== null) {
        text = "Czekam na GPS... " + sec + " s\nzapiszę: " + (s.pending || "Bez nazwy");
        color = COLOR_ORANGE;
      } else {
        text = "Szukam GPS... " + sec + " s\nmożesz już wybrać nazwę";
      }
    }
    s.status.setProperty(hmUI.prop.MORE, { ...STATUS_STYLE, text, color });
  },

  choose(name) {
    if (name === "Wpisz nazwę") {
      askText((text) => this.saveWhenReady(text));
      return;
    }
    this.saveWhenReady(name === "Bez nazwy" ? "" : name);
  },

  // Bez stabilnej pozycji zapamiętujemy wybór (kolejne dotknięcie go zmienia) i zapisujemy po ustaleniu
  saveWhenReady(name) {
    const s = this.state;
    if (this.ready()) {
      this.save(name);
      return;
    }
    s.pending = name;
    this.updateStatus();
  },

  save(name) {
    const s = this.state;
    if (s.saved || !this.ready()) return;
    s.saved = true;
    const ops = savePlaceOps(viewPlaces(), name, s.fix.lat, s.fix.lon, Date.now());
    addOps(ops);
    // Wyślij od razu na telefon; bez połączenia ekran listy ponowi wysyłkę sam
    sync(this, () => {});
    try {
      const v = new Vibrator();
      v.setMode(VIBRATOR_SCENE_SHORT_MIDDLE);
      v.start();
    } catch (e) {}
    showToast({ content: "Zapisano: " + ops[ops.length - 1].p.name });
    back();
  },
  })
);
