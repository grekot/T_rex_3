// Wybór daty zdobycia (z przeszłości albo poprawka): dzień / miesiąc / rok przyciskami + i −.
import * as hmUI from "@zos/ui";
import { back } from "@zos/router";
import { showToast } from "@zos/interaction";
import { px } from "@zos/utils";
import { findPeak } from "../../../utils/peaks";
import { todayKey, parseKey, dateKey, stepDate, formatDate, climbOf } from "../../../utils/korona";
import { loadClimbs, loadCustom, saveClimb } from "../../../utils/store";
import { setupScreen } from "../../../utils/device";
import { button, setText, parseParams } from "../../../utils/ui";
import {
  TITLE_STYLE,
  NAME_STYLE,
  FIELDS,
  labelStyle,
  plusRect,
  valueStyle,
  minusRect,
  WEEKDAY_STYLE,
  SAVE_RECT,
} from "zosLoader:./index.page.[pf].layout.js";

const WEEKDAYS = ["niedziela", "poniedziałek", "wtorek", "środa", "czwartek", "piątek", "sobota"];
const two = (n) => (n < 10 ? "0" : "") + n;

Page({
  state: {},

  onInit(params) {
    this.state.id = parseParams(params).id || "";
  },

  build() {
    const s = this.state;
    s.custom = loadCustom();
    s.peak = findPeak(s.id, s.custom);
    setupScreen(60000);
    hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);
    hmUI.createWidget(hmUI.widget.TEXT, { ...NAME_STYLE, text: s.peak ? s.peak.name : "Nie ma szczytu" });
    if (!s.peak) return;

    const climb = climbOf(s.peak.id, loadClimbs(), s.custom);
    s.date = parseKey(climb ? climb.d : todayKey(Date.now()));
    s.values = {};
    FIELDS.forEach((f) => {
      hmUI.createWidget(hmUI.widget.TEXT, labelStyle(f));
      button(plusRect(f), "+", "secondary", () => this.step(f, 1), px(36));
      s.values[f] = hmUI.createWidget(hmUI.widget.TEXT, valueStyle(f));
      // Stuknięcie w rok cofa o 10 lat (szybciej do starych wyjść)
      if (f === "y") s.values[f].addEventListener(hmUI.event.CLICK_UP, () => this.step("y", -10));
      button(minusRect(f), "−", "secondary", () => this.step(f, -1), px(36));
    });
    s.weekday = hmUI.createWidget(hmUI.widget.TEXT, WEEKDAY_STYLE);
    button(SAVE_RECT, "Zapisz", "primary", () => this.save(), px(28));
    this.render();
  },

  step(field, delta) {
    const s = this.state;
    s.date = stepDate(s.date, field, delta, Date.now());
    this.render();
  },

  render() {
    const s = this.state;
    setText(s.values.d, valueStyle("d"), two(s.date.d));
    setText(s.values.m, valueStyle("m"), two(s.date.m));
    setText(s.values.y, valueStyle("y"), String(s.date.y));
    const wd = new Date(s.date.y, s.date.m - 1, s.date.d).getDay();
    setText(s.weekday, WEEKDAY_STYLE, WEEKDAYS[wd] + " · stuknij rok: −10 lat");
  },

  save() {
    const s = this.state;
    const key = dateKey(s.date.y, s.date.m, s.date.d);
    const old = climbOf(s.peak.id, loadClimbs(), loadCustom());
    // „Zaliczony przez GPS” zostaje tylko, gdy data się nie zmieniła
    saveClimb(s.peak.id, key, !!(old && old.gps && old.d === key));
    try {
      showToast({ content: s.peak.name + ": " + formatDate(key) });
    } catch (e) {}
    back();
  },
});
