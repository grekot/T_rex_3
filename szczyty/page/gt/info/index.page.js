// Informacje: baza (liczba szczytów, data, atrybucja OSM), korekta deklinacji, zasięg, pomoc.
import * as hmUI from "@zos/ui";
import { back } from "@zos/router";
import { parseHeader, HEADER_SIZE, MAGIC, formatDbDate } from "../../../utils/peakdb";
import { declination, yearOf } from "../../../utils/declination";
import { RANGE_MIN_KM, RANGE_MAX_KM } from "../../../utils/pick";
import { openAsset, PEAKS_FILE, loadCfg, saveCfg, loadLastPos } from "../../../utils/device";
import {
  TITLE_STYLE,
  DB_STYLE,
  OSM_STYLE,
  DECL_BG,
  DECL_STYLE,
  HELP_STYLE,
  RANGE_MINUS_BG,
  RANGE_MINUS,
  RANGE_PLUS_BG,
  RANGE_PLUS,
  RANGE_STYLE,
  BACK_BG,
  BACK_STYLE,
  COLOR_ON,
  COLOR_OFF,
} from "zosLoader:./index.page.[pf].layout.js";

// 6.27 -> "+6,3°"
const fmtDecl = (d) => (d >= 0 ? "+" : "-") + Math.abs(d).toFixed(1).replace(".", ",") + "°";

// { line, error } - opis bazy u góry; przy błędzie odczytu szczegóły zamiast pomocy
function dbInfo() {
  const f = openAsset(PEAKS_FILE, MAGIC);
  if (f.error) return { line: "Brak bazy szczytów", error: f.error };
  let h = null;
  try {
    h = parseHeader(f.read(0, HEADER_SIZE));
  } catch (e) {}
  f.close();
  if (!h) return { line: "Uszkodzona baza szczytów", error: f.how + ": zły nagłówek" };
  return { line: "Baza: " + h.count + " szczytów (" + f.how + ")\nstan OSM: " + formatDbDate(h.date), error: "" };
}

Page({
  state: {},

  build() {
    const s = this.state;
    s.cfg = loadCfg();
    const pos = loadLastPos();
    s.decl = pos ? declination(pos.lat, pos.lon, yearOf(Date.now())) : null;

    const db = dbInfo();
    hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);
    hmUI.createWidget(hmUI.widget.TEXT, { ...DB_STYLE, text: db.line });
    hmUI.createWidget(hmUI.widget.TEXT, OSM_STYLE);

    s.declBg = hmUI.createWidget(hmUI.widget.FILL_RECT, DECL_BG);
    s.declText = hmUI.createWidget(hmUI.widget.TEXT, DECL_STYLE);
    [s.declBg, s.declText].forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, () => this.toggleDecl()));
    this.renderDecl();

    const minus = [hmUI.createWidget(hmUI.widget.FILL_RECT, RANGE_MINUS_BG), hmUI.createWidget(hmUI.widget.TEXT, RANGE_MINUS)];
    const plus = [hmUI.createWidget(hmUI.widget.FILL_RECT, RANGE_PLUS_BG), hmUI.createWidget(hmUI.widget.TEXT, RANGE_PLUS)];
    minus.forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, () => this.changeRange(-10)));
    plus.forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, () => this.changeRange(10)));
    s.rangeText = hmUI.createWidget(hmUI.widget.TEXT, RANGE_STYLE);
    this.renderRange();

    hmUI.createWidget(
      hmUI.widget.TEXT,
      db.error ? { ...HELP_STYLE, text: "Błąd odczytu:\n" + db.error, color: 0xff5252 } : HELP_STYLE,
    );
    const backBg = hmUI.createWidget(hmUI.widget.FILL_RECT, BACK_BG);
    const backText = hmUI.createWidget(hmUI.widget.TEXT, BACK_STYLE);
    [backBg, backText].forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, () => back()));
  },

  toggleDecl() {
    const s = this.state;
    s.cfg = { ...loadCfg(), decl: !s.cfg.decl };
    saveCfg(s.cfg);
    this.renderDecl();
  },

  // Zasięg wykrywania co 10 km; ekran główny przeładowuje szczyty po zmianie
  changeRange(delta) {
    const s = this.state;
    const km = Math.max(RANGE_MIN_KM, Math.min(RANGE_MAX_KM, s.cfg.rangeKm + delta));
    if (km === s.cfg.rangeKm) return;
    s.cfg = { ...loadCfg(), rangeKm: km };
    saveCfg(s.cfg);
    this.renderRange();
  },

  renderRange() {
    const s = this.state;
    s.rangeText.setProperty(hmUI.prop.MORE, { ...RANGE_STYLE, text: "Zasięg: " + s.cfg.rangeKm + " km" });
  },

  renderDecl() {
    const s = this.state;
    const value = s.decl === null ? "" : " (" + fmtDecl(s.decl) + ")";
    const text = "Korekta deklinacji: " + (s.cfg.decl ? "TAK" + value : "NIE");
    s.declBg.setProperty(hmUI.prop.MORE, { ...DECL_BG, color: s.cfg.decl ? COLOR_ON : COLOR_OFF });
    s.declText.setProperty(hmUI.prop.MORE, { ...DECL_STYLE, text });
  },
});
