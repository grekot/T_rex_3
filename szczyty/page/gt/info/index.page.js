// Informacje: baza (liczba szczytów, data, atrybucja OSM), korekta deklinacji, pomoc.
import * as hmUI from "@zos/ui";
import { back } from "@zos/router";
import { parseHeader, HEADER_SIZE, formatDbDate } from "../../../utils/peakdb";
import { declination, yearOf } from "../../../utils/declination";
import { openAsset, PEAKS_FILE, loadCfg, saveCfg, loadLastPos } from "../../../utils/device";
import {
  TITLE_STYLE,
  DB_STYLE,
  OSM_STYLE,
  DECL_BG,
  DECL_STYLE,
  HELP_STYLE,
  BACK_BG,
  BACK_STYLE,
  COLOR_ON,
  COLOR_OFF,
} from "zosLoader:./index.page.[pf].layout.js";

// 6.27 -> "+6,3°"
const fmtDecl = (d) => (d >= 0 ? "+" : "-") + Math.abs(d).toFixed(1).replace(".", ",") + "°";

function dbLine() {
  const f = openAsset(PEAKS_FILE);
  if (!f) return "Brak bazy szczytów";
  let h = null;
  try {
    h = parseHeader(f.read(0, HEADER_SIZE));
  } catch (e) {}
  f.close();
  return h ? "Baza: " + h.count + " szczytów\nstan OSM: " + formatDbDate(h.date) : "Uszkodzona baza szczytów";
}

Page({
  state: {},

  build() {
    const s = this.state;
    s.cfg = loadCfg();
    const pos = loadLastPos();
    s.decl = pos ? declination(pos.lat, pos.lon, yearOf(Date.now())) : null;

    hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);
    hmUI.createWidget(hmUI.widget.TEXT, { ...DB_STYLE, text: dbLine() });
    hmUI.createWidget(hmUI.widget.TEXT, OSM_STYLE);

    s.declBg = hmUI.createWidget(hmUI.widget.FILL_RECT, DECL_BG);
    s.declText = hmUI.createWidget(hmUI.widget.TEXT, DECL_STYLE);
    [s.declBg, s.declText].forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, () => this.toggleDecl()));
    this.renderDecl();

    hmUI.createWidget(hmUI.widget.TEXT, HELP_STYLE);
    const backBg = hmUI.createWidget(hmUI.widget.FILL_RECT, BACK_BG);
    const backText = hmUI.createWidget(hmUI.widget.TEXT, BACK_STYLE);
    [backBg, backText].forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, () => back()));
  },

  toggleDecl() {
    const s = this.state;
    s.cfg = { ...s.cfg, decl: !s.cfg.decl };
    saveCfg(s.cfg);
    this.renderDecl();
  },

  renderDecl() {
    const s = this.state;
    const value = s.decl === null ? "" : " (" + fmtDecl(s.decl) + ")";
    const text = "Korekta deklinacji: " + (s.cfg.decl ? "TAK" + value : "NIE");
    s.declBg.setProperty(hmUI.prop.MORE, { ...DECL_BG, color: s.cfg.decl ? COLOR_ON : COLOR_OFF });
    s.declText.setProperty(hmUI.prop.MORE, { ...DECL_STYLE, text });
  },
});
