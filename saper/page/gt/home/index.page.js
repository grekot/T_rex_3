// Menu: wybór poziomu z rekordami i powrót do przerwanej partii.
import * as hmUI from "@zos/ui";
import { push } from "@zos/router";
import { LEVELS } from "../../../utils/geometry";
import { PLAYING, levelOf, formatClock } from "../../../utils/mines";
import { loadGame, loadStats } from "../../../utils/store";
import {
  TITLE_ICON,
  TITLE_STYLE,
  CONTINUE_BG,
  CONTINUE_STYLE,
  PICK_STYLE,
  rowBg,
  rowNameStyle,
  rowRecordStyle,
  TIP_STYLE,
  COLOR_ORANGE,
  COLOR_GREY,
} from "zosLoader:./index.page.[pf].layout.js";

const GAME_PAGE = "page/gt/game/index.page";

// Menu sprawdza co tyle, czy po powrocie z gry zmienił się zapis albo rekordy
const REFRESH_MS = 1000;

function onTap(widgets, handler) {
  widgets.forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, handler));
}

Page({
  state: {},

  build() {
    const s = this.state;
    s.shownKey = "";
    s.records = [];

    hmUI.createWidget(hmUI.widget.IMG, TITLE_ICON);
    hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);

    s.pick = hmUI.createWidget(hmUI.widget.TEXT, PICK_STYLE);
    s.continueBg = hmUI.createWidget(hmUI.widget.FILL_RECT, CONTINUE_BG);
    s.continueText = hmUI.createWidget(hmUI.widget.TEXT, CONTINUE_STYLE);
    onTap([s.continueBg, s.continueText], () => push({ url: GAME_PAGE, params: JSON.stringify({ resume: true }) }));

    LEVELS.forEach((level, k) => {
      const bg = hmUI.createWidget(hmUI.widget.FILL_RECT, rowBg(k));
      const name = hmUI.createWidget(hmUI.widget.TEXT, {
        ...rowNameStyle(k),
        text: level.name + "  " + level.cols + "×" + level.rows,
      });
      const record = hmUI.createWidget(hmUI.widget.TEXT, rowRecordStyle(k));
      onTap([bg, name, record], () => push({ url: GAME_PAGE, params: JSON.stringify({ level: level.id }) }));
      s.records.push(record);
    });

    hmUI.createWidget(hmUI.widget.TEXT, TIP_STYLE);

    this.refresh();
    s.timer = setInterval(() => this.refresh(), REFRESH_MS);
  },

  onDestroy() {
    if (this.state.timer) clearInterval(this.state.timer);
  },

  refresh() {
    const s = this.state;
    const saved = loadGame();
    const stats = loadStats();
    const key = JSON.stringify([saved ? saved.level + "/" + saved.status : "", stats]);
    if (key === s.shownKey) return;
    s.shownKey = key;

    const canContinue = !!saved && saved.status === PLAYING;
    s.continueBg.setProperty(hmUI.prop.VISIBLE, canContinue);
    s.continueText.setProperty(hmUI.prop.VISIBLE, canContinue);
    s.pick.setProperty(hmUI.prop.VISIBLE, !canContinue);
    if (canContinue) {
      s.continueText.setProperty(hmUI.prop.MORE, { ...CONTINUE_STYLE, text: "Kontynuuj · " + levelOf(saved).name });
    }

    LEVELS.forEach((level, k) => {
      const best = stats[level.id] && stats[level.id].best;
      s.records[k].setProperty(hmUI.prop.MORE, {
        ...rowRecordStyle(k),
        text: best ? formatClock(best) : "–",
        color: best ? COLOR_ORANGE : COLOR_GREY,
      });
    });
  },
});
