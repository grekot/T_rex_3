// Wybór szczytu do naprowadzania: lista najbliższych albo najwybitniejszych w zasięgu (od
// ostatniej pozycji GPS). Stuknięcie = cel na ekranie głównym; pierwsza pozycja wyłącza cel.
import * as hmUI from "@zos/ui";
import { back } from "@zos/router";
import { loadPeaksNear, MAGIC } from "../../../utils/peakdb";
import { targetList, farFilter, pickOptions } from "../../../utils/pick";
import { formatDistance } from "../../../utils/geo";
import { setupScreen, openAsset, PEAKS_FILE, loadLastPos, loadCfg, saveCfg } from "../../../utils/device";
import {
  TITLE_STYLE,
  TAB_NEAR,
  TAB_TOP,
  tabBg,
  tabText,
  MSG_STYLE,
  listProps,
} from "zosLoader:./index.page.[pf].layout.js";

const LIMIT = 60;
const LOAD_MARGIN_KM = 1;

Page({
  state: {},

  build() {
    const s = this.state;
    setupScreen();
    s.cfg = loadCfg();
    s.mode = "near";
    s.list = null;
    s.lists = {};

    hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);
    s.tabs = [
      { mode: "near", rect: TAB_NEAR, label: "Najbliższe" },
      { mode: "top", rect: TAB_TOP, label: "Wybitne" },
    ];
    s.tabs.forEach((t) => {
      t.bg = hmUI.createWidget(hmUI.widget.FILL_RECT, tabBg(t.rect, t.mode === s.mode));
      t.text = hmUI.createWidget(hmUI.widget.TEXT, tabText(t.rect, t.label));
      [t.bg, t.text].forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, () => this.setMode(t.mode)));
    });
    s.msg = hmUI.createWidget(hmUI.widget.TEXT, { ...MSG_STYLE, text: "Wczytuję szczyty..." });
    // ekran najpierw, liczenie chwilę później
    s.loadTimer = setTimeout(() => {
      s.loadTimer = null;
      this.load();
      this.showList();
    }, 50);
  },

  onDestroy() {
    if (this.state.loadTimer) clearTimeout(this.state.loadTimer);
  },

  load() {
    const s = this.state;
    const pos = loadLastPos();
    if (!pos) {
      s.error = "Brak pozycji GPS.\nOtwórz najpierw ekran główny i poczekaj na GPS.";
      return;
    }
    const f = openAsset(PEAKS_FILE, MAGIC);
    if (f.error) {
      s.error = "Brak bazy szczytów";
      return;
    }
    const o = pickOptions(s.cfg.rangeKm);
    const obs = { lat: pos.lat, lon: pos.lon, ele: isFinite(pos.ele) ? pos.ele : 0 };
    let peaks = [];
    try {
      const res = loadPeaksNear(f.read, obs.lat, obs.lon, o.rangeM / 1000 + LOAD_MARGIN_KM, farFilter(obs, o));
      if (res) peaks = res.peaks;
    } catch (e) {}
    f.close();
    s.lists.near = targetList(peaks, obs, "near", LIMIT, o);
    s.lists.top = targetList(peaks, obs, "top", LIMIT, o);
    s.rangeKm = o.rangeM / 1000;
  },

  setMode(mode) {
    const s = this.state;
    if (mode === s.mode || s.loadTimer) return;
    s.mode = mode;
    s.tabs.forEach((t) => t.bg.setProperty(hmUI.prop.MORE, tabBg(t.rect, t.mode === mode)));
    this.showList();
  },

  showList() {
    const s = this.state;
    if (s.list) hmUI.deleteWidget(s.list);
    s.list = null;
    const peaks = s.lists[s.mode] || [];
    const target = s.cfg.target;
    if (s.error || (!peaks.length && !target)) {
      const text = s.error || "Brak szczytów w promieniu " + s.rangeKm + " km";
      s.msg.setProperty(hmUI.prop.MORE, { ...MSG_STYLE, text });
      s.msg.setProperty(hmUI.prop.VISIBLE, true);
      return;
    }
    s.msg.setProperty(hmUI.prop.VISIBLE, false);
    const data = peaks.map((p) => ({ name: p.name, km: formatDistance(p.d), ele: p.ele + " m" }));
    if (target) data.unshift({ name: "Wyłącz: " + target.name, km: "", ele: "" });
    s.list = hmUI.createWidget(
      hmUI.widget.SCROLL_LIST,
      listProps(data, !!target, (index) => {
        const i = target ? index - 1 : index;
        const p = i >= 0 ? peaks[i] : null;
        if (i >= 0 && !p) return;
        saveCfg({ ...loadCfg(), target: p ? { name: p.name, lat: p.lat, lon: p.lon, ele: p.ele } : null });
        back();
      })
    );
  },
});
