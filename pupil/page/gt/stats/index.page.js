// Statystyki pupila: głód, humor, dyscyplina (0-4 serc), waga, wiek, forma, błędy opieki.
import { push } from "@zos/router";
import { FORMS, MAX_HEARTS, ageDays, stageOf, baseWeight } from "../../../utils/pet";
import { load } from "../../../utils/store";
import { COLOR, label, image, button, daysText } from "../../../utils/ui";
import { HEART } from "../../../utils/geometry";
import {
  TITLE,
  HEART_ROWS,
  ROW_LABEL,
  HEARTS_X,
  HEART_STEP,
  INFO,
  COLLECTION_BTN,
  NAME_BTN,
} from "zosLoader:./index.page.[pf].layout.js";

const REFRESH_MS = 5000;

Page({
  state: {},

  build() {
    const s = this.state;
    label({ ...TITLE, text: "Statystyki" });
    s.hearts = HEART_ROWS.map((row) => {
      label({ ...ROW_LABEL, y: row.y, text: row.label, color: COLOR.grey, left: true });
      const list = [];
      for (let i = 0; i < MAX_HEARTS; i++)
        list.push(image("ui/heart_empty.png", HEARTS_X + i * HEART_STEP, row.y + (ROW_LABEL.h - HEART) / 2));
      return list;
    });
    s.info = INFO.map((o) => label({ ...o }));
    button(NAME_BTN, () => push({ url: "page/gt/choose/index.page", params: "name" }));
    button(COLLECTION_BTN, () => push({ url: "page/gt/collection/index.page" }));
    this.render();
    s.timer = setInterval(() => this.render(), REFRESH_MS);
  },

  onDestroy() {
    if (this.state.timer) clearInterval(this.state.timer);
  },

  render() {
    const s = this.state;
    const p = load().state;
    const egg = stageOf(p) === "egg";
    const values = [p.hunger, p.happy, p.discipline];
    s.hearts.forEach((list, r) =>
      list.forEach((w, i) => w.set(!egg && !p.gone && i < values[r] ? "ui/heart.png" : "ui/heart_empty.png")),
    );
    const over = p.weight - baseWeight(p);
    const shape = egg ? "" : over >= 15 ? " · za gruby" : over >= 8 ? " · pulchny" : "";
    const lines = [
      (p.name ? p.name + " · " : "") + FORMS[p.form].name + (p.sick ? " · chory" : "") + shape,
      (egg ? "Jeszcze w jajku" : "Waga " + p.weight + " g") + " · " + daysText(ageDays(p)),
      "Pokolenie " + p.gen + " · błędy: " + p.totalMistakes,
    ];
    s.info.forEach((w, i) => w.set(lines[i], i === 0 ? COLOR.accent : COLOR.text));
  },
});
