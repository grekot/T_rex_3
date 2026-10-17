// Zapisywanie bieżącego miejsca: czekamy na GPS, wybierasz nazwę (gotowa albo wpisana).
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
import { stayInApp, keepBright } from "../../../utils/screen";
import { canType, askText } from "../../../utils/input";
import { button, gridRect, COLOR_GREEN, COLOR_GREY } from "../../../utils/ui";
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
    startedAt: 0,
    gps: null,
    timer: null,
    saved: false,
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
      if (fix) s.fixes++;
      s.fix = fix || s.fix;
      this.updateStatus();
    });
    // Licznik sekund, gdy GPS jeszcze szuka
    s.timer = setInterval(() => this.updateStatus(), 1000);
  },

  onDestroy() {
    const s = this.state;
    if (s.gps) s.gps.stop();
    if (s.timer) clearInterval(s.timer);
  },

  updateStatus() {
    const s = this.state;
    let text;
    let color = COLOR_GREY;
    if (s.fix) {
      text = "Pozycja ustalona - wybierz nazwę";
      color = COLOR_GREEN;
    } else {
      const sec = Math.floor((Date.now() - s.startedAt) / 1000);
      text = "Szukam sygnału GPS... " + sec + " s\n(najszybciej pod gołym niebem)";
    }
    s.status.setProperty(hmUI.prop.MORE, { ...STATUS_STYLE, text, color });
  },

  choose(name) {
    if (!this.state.fix) {
      showToast({ content: "Poczekaj na sygnał GPS" });
      return;
    }
    if (name === "Wpisz nazwę") {
      askText((text) => this.save(text));
      return;
    }
    this.save(name === "Bez nazwy" ? "" : name);
  },

  save(name) {
    const s = this.state;
    if (s.saved || !s.fix) return;
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
