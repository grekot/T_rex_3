// Ekran główny: postęp „12 / 28”, karta GPS (najbliższy szczyt albo „Jesteś na szczycie!”
// z przyciskiem Zaliczam) i lista wszystkich szczytów. Stuknięcie w szczyt = szczegóły.
import * as hmUI from "@zos/ui";
import { push } from "@zos/router";
import { showToast } from "@zos/interaction";
import { scrollTo } from "@zos/page";
import { px } from "@zos/utils";
import { PEAKS, OFFICIAL, findPeak } from "../../../utils/peaks";
import { bearing, formatDistance, cardinal } from "../../../utils/geo";
import { progress, nearestUnclimbed, createSummitWatcher, todayKey, formatDate } from "../../../utils/korona";
import { loadClimbs, climbsStamp, saveClimb } from "../../../utils/store";
import { startGps } from "../../../utils/sensors";
import { setupScreen, vibrate } from "../../../utils/device";
import { button, setText, onTap, COLOR_WHITE, COLOR_GREY, COLOR_GREEN, COLOR_ORANGE, COLOR_TRACK } from "../../../utils/ui";
import {
  TITLE_STYLE,
  COUNT_STYLE,
  BAR_TRACK,
  barFill,
  CARD_BG,
  CARD_LINE1,
  CARD_LINE2,
  ACTION_RECT,
  LIST_HEADER_STYLE,
  rowY,
  variantsHeaderStyle,
  rowBg,
  rowDot,
  rowName,
  rowRight,
  bottomSpacer,
} from "zosLoader:./index.page.[pf].layout.js";

const PEAK_PAGE = "page/gt/peak/index.page";
const NEAREST_PAGE = "page/gt/nearest/index.page";
const STAMP_POLL_MS = 1000; // po powrocie ze szczegółów / wyboru daty

Page({
  state: {},

  build() {
    const s = this.state;
    s.fix = null;
    s.summit = null;
    s.watcher = createSummitWatcher();
    s.action = null;
    s.actionKey = "";
    s.rows = [];
    setupScreen(30000);

    hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);
    s.count = hmUI.createWidget(hmUI.widget.TEXT, COUNT_STYLE);
    hmUI.createWidget(hmUI.widget.FILL_RECT, BAR_TRACK);
    s.bar = hmUI.createWidget(hmUI.widget.FILL_RECT, barFill(0, 1));

    const cardBg = hmUI.createWidget(hmUI.widget.FILL_RECT, CARD_BG);
    s.line1 = hmUI.createWidget(hmUI.widget.TEXT, CARD_LINE1);
    s.line2 = hmUI.createWidget(hmUI.widget.TEXT, CARD_LINE2);
    onTap([cardBg, s.line1, s.line2], () => this.cardTapped());

    hmUI.createWidget(hmUI.widget.TEXT, LIST_HEADER_STYLE);
    hmUI.createWidget(hmUI.widget.TEXT, variantsHeaderStyle(OFFICIAL.length));
    let y = 0;
    PEAKS.forEach((peak, i) => {
      y = rowY(i, OFFICIAL.length);
      const row = {
        peak,
        y,
        bg: hmUI.createWidget(hmUI.widget.FILL_RECT, rowBg(y)),
        dot: hmUI.createWidget(hmUI.widget.CIRCLE, rowDot(y)),
        name: hmUI.createWidget(hmUI.widget.TEXT, { ...rowName(y), text: peak.name }),
        right: hmUI.createWidget(hmUI.widget.TEXT, rowRight(y)),
      };
      onTap([row.bg, row.name, row.right], () => push({ url: PEAK_PAGE, params: JSON.stringify({ id: peak.id }) }));
      s.rows.push(row);
    });
    hmUI.createWidget(hmUI.widget.FILL_RECT, bottomSpacer(y + rowBg(y).h + 10));

    this.refresh();
    s.stampTimer = setInterval(() => {
      if (climbsStamp() !== s.stamp) this.refresh();
    }, STAMP_POLL_MS);

    s.gps = startGps((fix) => {
      s.fix = fix || s.fix;
      const r = s.watcher.update(fix);
      s.summit = r.peak;
      if (r.entered) this.onSummit();
      this.renderCard();
    });
  },

  onDestroy() {
    const s = this.state;
    if (s.stampTimer) clearInterval(s.stampTimer);
    if (s.gps) s.gps.stop();
  },

  // Postęp i wiersze listy (po każdej zmianie zapisów)
  refresh() {
    const s = this.state;
    s.stamp = climbsStamp();
    s.climbs = loadClimbs();
    const p = progress(s.climbs);
    setText(s.count, COUNT_STYLE, p.done + " / " + p.total, p.complete ? COLOR_GREEN : COLOR_WHITE);
    s.bar.setProperty(hmUI.prop.MORE, barFill(p.done, p.total));
    s.bar.setProperty(hmUI.prop.VISIBLE, p.done > 0);
    s.rows.forEach((row) => {
      const c = s.climbs[row.peak.id];
      setText(row.name, rowName(row.y), row.peak.name, c ? COLOR_WHITE : COLOR_GREY);
      setText(row.right, rowRight(row.y), c ? formatDate(c.d) : row.peak.h + " m", c ? COLOR_GREEN : COLOR_GREY);
      row.dot.setProperty(hmUI.prop.MORE, { ...rowDot(row.y), color: c ? COLOR_GREEN : COLOR_TRACK });
    });
    this.renderCard();
  },

  renderCard() {
    const s = this.state;
    if (!s.line1) return;
    const climbs = s.climbs || {};
    if (s.summit) {
      const c = climbs[s.summit.id];
      setText(s.line1, CARD_LINE1, "Jesteś na szczycie!", COLOR_GREEN);
      setText(
        s.line2,
        CARD_LINE2,
        s.summit.name + " · " + s.summit.h + " m" + (c ? " · zdobyty " + formatDate(c.d) : ""),
        COLOR_WHITE
      );
      this.setAction(c ? "details" : "climb");
      return;
    }
    if (!s.fix) {
      setText(s.line1, CARD_LINE1, "Szukam GPS...", COLOR_ORANGE);
      setText(s.line2, CARD_LINE2, "Szczyt zaliczysz, gdy otworzysz aplikację na wierzchołku", COLOR_GREY);
      this.setAction(progress(climbs).complete ? "none" : "nearest");
      return;
    }
    const near = nearestUnclimbed(s.fix, climbs, 1)[0];
    if (!near) {
      setText(s.line1, CARD_LINE1, "Korona zdobyta!", COLOR_GREEN);
      setText(s.line2, CARD_LINE2, "Wszystkie 28 szczytów", COLOR_GREY);
      this.setAction("none");
      return;
    }
    const b = bearing(s.fix.lat, s.fix.lon, near.peak.lat, near.peak.lon);
    setText(s.line1, CARD_LINE1, "Najbliższy: " + near.peak.name, COLOR_WHITE);
    setText(s.line2, CARD_LINE2, formatDistance(near.distance) + " · " + cardinal(b) + " · " + near.peak.range, COLOR_GREY);
    this.setAction("nearest");
  },

  // Przycisk pod kartą - tworzony na nowo tylko przy zmianie rodzaju
  setAction(key) {
    const s = this.state;
    if (s.actionKey === key) return;
    s.actionKey = key;
    if (s.action) hmUI.deleteWidget(s.action);
    s.action = null;
    if (key === "climb") s.action = button(ACTION_RECT, "Zaliczam", "success", () => this.climb(), px(30));
    if (key === "details") s.action = button(ACTION_RECT, "Szczegóły", "secondary", () => this.cardTapped());
    if (key === "nearest") s.action = button(ACTION_RECT, "Najbliższe ›", "primary", () => this.cardTapped());
  },

  cardTapped() {
    const s = this.state;
    if (s.summit) push({ url: PEAK_PAGE, params: JSON.stringify({ id: s.summit.id }) });
    else if (!progress(s.climbs || {}).complete) push({ url: NEAREST_PAGE });
  },

  onSummit() {
    vibrate();
    try {
      scrollTo({ y: 0 });
    } catch (e) {}
  },

  climb() {
    const s = this.state;
    if (!s.summit) return;
    const peak = findPeak(s.summit.id);
    saveClimb(peak.id, todayKey(Date.now()), true);
    try {
      showToast({ content: "Zaliczone: " + peak.name });
    } catch (e) {}
    this.refresh();
  },
});
