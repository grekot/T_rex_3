// Historia pomiarów: zmiana w 7 / 30 dniach i lista dni od najnowszego (przewijana).
import * as hmUI from "@zos/ui";
import { formatKg, formatDelta, shortDate, historyRows, periodChange } from "../../../utils/weight";
import { loadData, todayKey } from "../../../utils/store";
import {
  TITLE_STYLE,
  EMPTY_STYLE,
  summaryStyle,
  rowStyles,
  bottomSpacer,
  COLOR_GREY,
  COLOR_GREEN,
  COLOR_RED,
} from "zosLoader:./index.page.[pf].layout.js";

const MAX_ROWS = 60;

function deltaColor(d) {
  return d === null || d === 0 ? COLOR_GREY : d < 0 ? COLOR_GREEN : COLOR_RED;
}

function periodText(label, d) {
  return label + ": " + (d === null ? "–" : formatDelta(d) + " kg");
}

Page({
  build() {
    const data = loadData();
    const today = todayKey();

    hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);
    if (!data.e.length) {
      hmUI.createWidget(hmUI.widget.TEXT, EMPTY_STYLE);
      return;
    }

    const w7 = periodChange(data, today, 7);
    const w30 = periodChange(data, today, 30);
    hmUI.createWidget(hmUI.widget.TEXT, { ...summaryStyle(0, periodText("7 dni", w7)), color: deltaColor(w7) });
    hmUI.createWidget(hmUI.widget.TEXT, { ...summaryStyle(1, periodText("30 dni", w30)), color: deltaColor(w30) });

    const rows = historyRows(data, MAX_ROWS);
    rows.forEach((r, i) => {
      const st = rowStyles(i);
      hmUI.createWidget(hmUI.widget.FILL_RECT, st.line);
      hmUI.createWidget(hmUI.widget.TEXT, { ...st.date, text: shortDate(r.d) });
      hmUI.createWidget(hmUI.widget.TEXT, { ...st.weight, text: formatKg(r.w) });
      hmUI.createWidget(hmUI.widget.TEXT, {
        ...st.delta,
        text: r.delta === null ? "" : formatDelta(r.delta),
        color: deltaColor(r.delta),
      });
    });
    hmUI.createWidget(hmUI.widget.FILL_RECT, bottomSpacer(rows.length));
  },
});
