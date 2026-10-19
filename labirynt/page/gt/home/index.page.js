// Menu: graj od zapisanego poziomu, zacznij od nowa albo sprawdź czujnik.
import * as hmUI from "@zos/ui";
import { push } from "@zos/router";
import { loadLevel, saveLevel, loadBest } from "../../../utils/store";
import {
  TITLE_ICON,
  TITLE_STYLE,
  buttonBg,
  buttonText,
  RECORD_STYLE,
  TIP_STYLE,
} from "zosLoader:./index.page.[pf].layout.js";

const GAME_PAGE = "page/gt/game/index.page";
const SENSOR_PAGE = "page/gt/sensor/index.page";

// Menu sprawdza co tyle, czy po powrocie z gry zmienił się poziom albo rekord
const REFRESH_MS = 1000;

Page({
  state: {},

  build() {
    const s = this.state;
    s.shownKey = "";
    hmUI.createWidget(hmUI.widget.IMG, TITLE_ICON);
    hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);

    s.play = this.button(0, "", () => push({ url: GAME_PAGE, params: JSON.stringify({ level: loadLevel() }) }));
    this.button(1, "Od poziomu 1", () => {
      saveLevel(1);
      push({ url: GAME_PAGE, params: JSON.stringify({ level: 1 }) });
    });
    this.button(2, "Czujnik", () => push({ url: SENSOR_PAGE }));

    s.record = hmUI.createWidget(hmUI.widget.TEXT, RECORD_STYLE);
    hmUI.createWidget(hmUI.widget.TEXT, TIP_STYLE);

    this.refresh();
    s.timer = setInterval(() => this.refresh(), REFRESH_MS);
  },

  onDestroy() {
    if (this.state.timer) clearInterval(this.state.timer);
  },

  button(index, text, onClick) {
    const bg = hmUI.createWidget(hmUI.widget.FILL_RECT, buttonBg(index));
    const label = hmUI.createWidget(hmUI.widget.TEXT, buttonText(index, text));
    [bg, label].forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, onClick));
    return label;
  },

  refresh() {
    const s = this.state;
    const level = loadLevel();
    const best = loadBest();
    const key = level + "/" + best.maxLevel;
    if (key === s.shownKey) return;
    s.shownKey = key;
    s.play.setProperty(hmUI.prop.MORE, buttonText(0, "Graj · poziom " + level));
    s.record.setProperty(hmUI.prop.MORE, {
      ...RECORD_STYLE,
      text: best.maxLevel ? "rekord: poziom " + best.maxLevel : "",
    });
  },
});
