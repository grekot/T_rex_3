// Jedna lista (KGP, pasmo albo własne): postęp i wszystkie szczyty - najpierw zdobyte (najnowsze
// na górze, z datą), potem niezdobyte od najwyższego. Stuknięcie = szczegóły szczytu.
import * as hmUI from "@zos/ui";
import { push } from "@zos/router";
import { findGroup, MY_GROUP } from "../../../utils/peaks";
import { progress, groupRows, formatDate } from "../../../utils/korona";
import { loadClimbs, loadCustom, stamp } from "../../../utils/store";
import { setupScreen } from "../../../utils/device";
import { button, setText, parseParams, COLOR_WHITE, COLOR_GREEN } from "../../../utils/ui";
import { px } from "@zos/utils";
import {
  NAME_STYLE,
  COUNT_STYLE,
  BAR_TRACK,
  barFill,
  NEAREST_RECT,
  EMPTY_STYLE,
  listProps,
} from "zosLoader:./index.page.[pf].layout.js";

const PEAK_PAGE = "page/gt/peak/index.page";
const NEAREST_PAGE = "page/gt/nearest/index.page";
const STAMP_POLL_MS = 1000;

// Prawa kolumna: data zdobycia albo wysokość (warianty KGP oznaczone)
function rightText(row) {
  if (row.climb) return formatDate(row.climb.d);
  const h = row.peak.h ? row.peak.h + " m" : "";
  return row.peak.variantOf ? (h ? h + " war." : "wariant") : h;
}

Page({
  state: {},

  onInit(params) {
    this.state.groupId = parseParams(params).g || "kgp";
  },

  build() {
    const s = this.state;
    s.group = findGroup(s.groupId) || findGroup("kgp");
    s.mine = s.group.id === MY_GROUP;
    s.list = null;
    s.empty = null;
    setupScreen(30000);

    hmUI.createWidget(hmUI.widget.TEXT, { ...NAME_STYLE, text: s.group.name });
    s.count = hmUI.createWidget(hmUI.widget.TEXT, COUNT_STYLE);
    if (!s.mine) {
      hmUI.createWidget(hmUI.widget.FILL_RECT, BAR_TRACK);
      s.bar = hmUI.createWidget(hmUI.widget.FILL_RECT, barFill(0, 1));
      button(NEAREST_RECT, "Najbliższe ›", "primary", () => push({ url: NEAREST_PAGE, params: JSON.stringify({ g: s.group.id }) }), px(22));
    }
    this.refresh();
    s.stampTimer = setInterval(() => {
      if (stamp() !== s.stamp) this.refresh();
    }, STAMP_POLL_MS);
  },

  onDestroy() {
    if (this.state.stampTimer) clearInterval(this.state.stampTimer);
  },

  refresh() {
    const s = this.state;
    s.stamp = stamp();
    const climbs = loadClimbs();
    const custom = loadCustom();
    const p = progress(s.group.id, climbs, custom);
    setText(s.count, COUNT_STYLE, s.mine ? String(p.done) : p.done + " / " + p.total, p.complete ? COLOR_GREEN : COLOR_WHITE);
    if (s.bar) {
      s.bar.setProperty(hmUI.prop.MORE, barFill(p.done, p.total));
      s.bar.setProperty(hmUI.prop.VISIBLE, p.done > 0);
    }

    s.rows = groupRows(s.group.id, climbs, custom);
    // Lista budowana od nowa tylko przy zmianie (po powrocie ze szczegółów)
    if (s.list) hmUI.deleteWidget(s.list);
    if (s.empty) hmUI.deleteWidget(s.empty);
    s.list = null;
    s.empty = null;
    if (!s.rows.length) {
      s.empty = hmUI.createWidget(hmUI.widget.TEXT, {
        ...EMPTY_STYLE,
        text: "Brak własnych szczytów.\nNa szczycie spoza list wybierz na ekranie głównym „Dodaj szczyt tutaj”.",
      });
      return;
    }
    const data = s.rows.map((row) => ({ name: row.peak.name, right: rightText(row) }));
    const climbed = s.rows.filter((row) => row.climb).length;
    s.list = hmUI.createWidget(
      hmUI.widget.SCROLL_LIST,
      listProps(data, climbed, (index) => {
        const row = s.rows[index];
        if (row) push({ url: PEAK_PAGE, params: JSON.stringify({ id: row.peak.id }) });
      })
    );
  },
});
