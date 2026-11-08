// Co to za szczyt? Godzina 12 zegarka wskazuje górę - ekran pokazuje jej nazwę, wysokość,
// odległość, sąsiadów po bokach i pasek horyzontu. GPS + kompas + baza z assets, offline.
import * as hmUI from "@zos/ui";
import { push } from "@zos/router";
import { onKey, offKey, KEY_UP, KEY_DOWN, KEY_EVENT_CLICK } from "@zos/interaction";
import { distance, smoothAngle, angleDiff } from "../../../utils/geo";
import { declination, yearOf, trueHeading } from "../../../utils/declination";
import { loadPeaksNear, MAGIC } from "../../../utils/peakdb";
import { buildCandidates, farFilter, pickOptions } from "../../../utils/pick";
import { screenModel } from "../../../utils/view";
import { startGps, startCompass, startAltimeter } from "../../../utils/sensors";
import { setupScreen, openAsset, PEAKS_FILE, loadLastPos, saveLastPos, loadCfg, cfgStamp } from "../../../utils/device";
import {
  TOP_STYLE,
  STATUS_STYLE,
  NAME_STYLE,
  DETAILS_STYLE,
  HINT_STYLE,
  STRIP_LINE,
  STRIP_MARK,
  PEAK_ICON,
  stripIconPos,
  LEFT_ARROW,
  RIGHT_ARROW,
  LEFT_STYLE,
  RIGHT_STYLE,
  BEHIND_STYLE,
  INFO_BG,
  INFO_STYLE,
  TARGET_BG,
  TARGET_STYLE,
  FREEZE_AREA,
  COLOR_ORANGE,
  COLOR_FROZEN,
} from "zosLoader:./index.page.[pf].layout.js";
import { px } from "@zos/utils";

const INFO_PAGE = "page/gt/info/index.page";
const TARGET_PAGE = "page/gt/cel/index.page";
const TICK_MS = 200; // odczyt kompasu i odświeżenie ekranu
const SMOOTH = 0.25; // wygładzanie kompasu (0..1, mniej = spokojniej, ale wolniej)
const SMOOTH_FAST = 0.6; // przy szybkim obrocie (> 20°) dochodzimy szybciej
const FAST_DEG = 20;
const COMPASS_GRACE_MS = 3000; // krótkie zaniki kompasu nie gaszą wyniku
const RELOAD_M = 5000; // po takim przejściu wczytujemy kafle od nowa
const RELOAD_ELE_M = 300; // ...albo zmianie wysokości (dalekie szczyty są wybierane wg niej)
const LOAD_MARGIN_KM = 6;
const RECOMPUTE_M = 300; // przeliczenie kandydatów po przejściu / zmianie wysokości
const RECOMPUTE_ELE_M = 40;
const SAVE_POS_MS = 60000;
const ALT_SMOOTH = 0.2;
const CFG_POLL_TICKS = 5; // co 1 s: zmiana ustawień na stronie informacji

function onTap(widgets, handler) {
  widgets.forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, handler));
}

Page({
  state: {},

  build() {
    const s = this.state;
    setupScreen();
    s.cfg = loadCfg();
    s.pick = pickOptions(s.cfg.rangeKm);
    s.stamp = cfgStamp();
    s.pos = loadLastPos();
    if (s.pos) s.pos.live = false;
    s.ele = s.pos && isFinite(s.pos.ele) ? s.pos.ele : null;
    s.heading = null;
    s.headingAt = 0;
    s.frozen = false;
    s.peaks = null;
    s.cands = null;
    s.noDb = false;
    s.dbError = "";
    s.db = null;
    s.ticks = 0;
    s.savedAt = 0;
    s.cache = {};

    s.freeze = hmUI.createWidget(hmUI.widget.FILL_RECT, FREEZE_AREA);
    s.top = hmUI.createWidget(hmUI.widget.TEXT, TOP_STYLE);
    s.status = hmUI.createWidget(hmUI.widget.TEXT, STATUS_STYLE);
    s.name = hmUI.createWidget(hmUI.widget.TEXT, NAME_STYLE);
    s.details = hmUI.createWidget(hmUI.widget.TEXT, DETAILS_STYLE);
    s.hint = hmUI.createWidget(hmUI.widget.TEXT, HINT_STYLE);
    onTap([s.freeze, s.name, s.details, s.hint], () => this.toggleFreeze());

    hmUI.createWidget(hmUI.widget.FILL_RECT, STRIP_LINE);
    s.icons = [];
    for (let i = 0; i < s.pick.stripMax; i++) {
      const icon = hmUI.createWidget(hmUI.widget.IMG, { x: 0, y: 0, w: px(PEAK_ICON.w), h: px(PEAK_ICON.h), src: "peak.png" });
      icon.setProperty(hmUI.prop.VISIBLE, false);
      s.icons.push({ w: icon, key: "" });
    }
    hmUI.createWidget(hmUI.widget.FILL_RECT, STRIP_MARK);

    s.leftArrow = hmUI.createWidget(hmUI.widget.IMG, LEFT_ARROW);
    s.rightArrow = hmUI.createWidget(hmUI.widget.IMG, RIGHT_ARROW);
    s.left = hmUI.createWidget(hmUI.widget.TEXT, LEFT_STYLE);
    s.right = hmUI.createWidget(hmUI.widget.TEXT, RIGHT_STYLE);
    s.behind = hmUI.createWidget(hmUI.widget.TEXT, BEHIND_STYLE);

    s.infoBg = hmUI.createWidget(hmUI.widget.FILL_RECT, INFO_BG);
    s.infoText = hmUI.createWidget(hmUI.widget.TEXT, INFO_STYLE);
    onTap([s.infoBg, s.infoText], () => push({ url: INFO_PAGE }));
    s.targetBg = hmUI.createWidget(hmUI.widget.FILL_RECT, TARGET_BG);
    s.targetText = hmUI.createWidget(hmUI.widget.TEXT, TARGET_STYLE);
    onTap([s.targetBg, s.targetText], () => push({ url: TARGET_PAGE }));

    s.compass = startCompass();
    s.alt = startAltimeter();
    s.gps = startGps((fix) => this.onFix(fix));
    // Najpierw ekran, potem baza: wczytanie kafli i liczenie kandydatów trwa na zegarku
    // zauważalnie, a bez tego przez ten czas widać tylko czarny ekran
    this.render();
    s.loadTimer = setTimeout(() => {
      s.loadTimer = null;
      this.refreshPeaks();
      this.render();
      s.timer = setInterval(() => this.tick(), TICK_MS);
    }, 50);

    try {
      onKey({
        callback: (key, event) => {
          if (key !== KEY_UP && key !== KEY_DOWN) return false;
          if (event === KEY_EVENT_CLICK) this.toggleFreeze();
          return true;
        },
      });
      s.keyHooked = true;
    } catch (e) {}
  },

  onDestroy() {
    const s = this.state;
    if (s.loadTimer) clearTimeout(s.loadTimer);
    if (s.timer) clearInterval(s.timer);
    s.gps.stop();
    s.compass.stop();
    s.alt.stop();
    if (s.pos && s.pos.live) this.savePos();
    if (s.db) s.db.close();
    if (s.keyHooked) {
      try {
        offKey();
      } catch (e) {}
    }
  },

  onFix(fix) {
    const s = this.state;
    if (!fix) return;
    s.pos = { lat: fix.lat, lon: fix.lon, t: Date.now(), live: true };
    if (s.pos.t - s.savedAt > SAVE_POS_MS) this.savePos();
    this.refreshPeaks();
  },

  savePos() {
    const s = this.state;
    s.savedAt = Date.now();
    const p = { lat: s.pos.lat, lon: s.pos.lon, t: s.pos.t };
    if (s.ele !== null) p.ele = Math.round(s.ele);
    saveLastPos(p);
  },

  // Kafle z bazy wokół pozycji (rzadko) i kandydaci z odległością/kierunkiem (po przejściu)
  refreshPeaks() {
    const s = this.state;
    if (!s.pos || s.noDb) return;
    const { lat, lon } = s.pos;
    const ele = s.ele === null ? 0 : s.ele;
    if (
      !s.peaks ||
      distance(lat, lon, s.peaksAt.lat, s.peaksAt.lon) > RELOAD_M ||
      Math.abs(ele - s.peaksAt.ele) > RELOAD_ELE_M
    ) {
      if (!s.db) {
        const f = openAsset(PEAKS_FILE, MAGIC);
        if (f.error) {
          console.log("peaks.bin: " + f.error);
          s.noDb = true;
          s.dbError = f.error;
          return;
        }
        s.db = f;
      }
      let res = null;
      try {
        const o = s.pick;
        res = loadPeaksNear(s.db.read, lat, lon, o.rangeM / 1000 + LOAD_MARGIN_KM, farFilter({ lat, lon, ele }, o));
      } catch (e) {
        s.dbError = s.db.how + ": " + e;
      }
      if (!res) {
        if (!s.dbError) s.dbError = s.db.how + ": zły nagłówek";
        console.log("peaks.bin: " + s.dbError);
        s.noDb = true;
        return;
      }
      s.peaks = res.peaks;
      s.peaksAt = { lat, lon, ele };
      s.cands = null;
    }
    if (
      !s.cands ||
      distance(lat, lon, s.candsAt.lat, s.candsAt.lon) > RECOMPUTE_M ||
      Math.abs(ele - s.candsAt.ele) > RECOMPUTE_ELE_M
    ) {
      s.cands = buildCandidates(s.peaks, { lat, lon, ele }, s.pick);
      s.candsAt = { lat, lon, ele };
    }
  },

  toggleFreeze() {
    const s = this.state;
    if (!s.frozen && s.heading === null) return;
    s.frozen = !s.frozen;
    this.render();
  },

  tick() {
    const s = this.state;
    const now = Date.now();
    s.ticks++;
    if (s.ticks % CFG_POLL_TICKS === 0) {
      if (cfgStamp() !== s.stamp) {
        s.stamp = cfgStamp();
        const old = s.cfg.rangeKm;
        s.cfg = loadCfg();
        if (s.cfg.rangeKm !== old) {
          // inny zasięg - kafle i kandydaci od nowa
          s.pick = pickOptions(s.cfg.rangeKm);
          s.peaks = null;
          s.cands = null;
          this.refreshPeaks();
        }
      }
      const a = s.alt.read();
      if (a !== null) {
        s.ele = s.ele === null ? a : s.ele + (a - s.ele) * ALT_SMOOTH;
        this.refreshPeaks();
      }
    }
    if (!s.frozen) {
      const raw = s.compass.read();
      if (raw !== null) {
        const h = s.cfg.decl && s.pos ? trueHeading(raw, declination(s.pos.lat, s.pos.lon, yearOf(now))) : raw;
        const fast = s.heading !== null && Math.abs(angleDiff(h, s.heading)) > FAST_DEG;
        s.heading = smoothAngle(s.heading, h, fast ? SMOOTH_FAST : SMOOTH);
        s.headingAt = now;
      } else if (now - s.headingAt > COMPASS_GRACE_MS) s.heading = null;
    }
    this.render();
  },

  setText(key, widget, style, value, color) {
    const c = this.state.cache;
    const k = value + "|" + (color || "");
    if (c[key] === k) return;
    c[key] = k;
    widget.setProperty(hmUI.prop.MORE, color ? { ...style, text: value, color } : { ...style, text: value });
  },

  setVisible(key, widget, visible) {
    const c = this.state.cache;
    if (c[key] === visible) return;
    c[key] = visible;
    widget.setProperty(hmUI.prop.VISIBLE, visible);
  },

  render() {
    const s = this.state;
    const m = screenModel({
      pos: s.pos,
      ele: s.ele,
      heading: s.heading,
      cands: s.cands,
      frozen: s.frozen,
      now: Date.now(),
      noDb: s.noDb,
      loading: !s.cands,
      dbError: s.dbError,
      target: s.cfg.target,
    }, s.pick);
    this.setText("top", s.top, TOP_STYLE, m.top, s.frozen ? COLOR_FROZEN : COLOR_ORANGE);
    this.setText("status", s.status, STATUS_STYLE, m.status);
    this.setText("name", s.name, NAME_STYLE, m.name);
    this.setText("details", s.details, DETAILS_STYLE, m.details);
    this.setText("hint", s.hint, HINT_STYLE, m.hint);
    this.setText("left", s.left, LEFT_STYLE, m.left);
    this.setText("right", s.right, RIGHT_STYLE, m.right);
    this.setText("behind", s.behind, BEHIND_STYLE, m.behind);
    this.setVisible("la", s.leftArrow, !!m.left);
    this.setVisible("ra", s.rightArrow, !!m.right);
    s.icons.forEach((icon, i) => {
      const p = m.strip[i];
      if (!p) {
        this.setVisible("icon" + i, icon.w, false);
        return;
      }
      const pos = stripIconPos(p.off, p.elev);
      const src = p.best ? "peak_best.png" : "peak.png";
      const key = pos.x + "," + pos.y + src;
      if (icon.key !== key) {
        icon.key = key;
        icon.w.setProperty(hmUI.prop.MORE, { ...pos, w: px(PEAK_ICON.w), h: px(PEAK_ICON.h), src });
      }
      this.setVisible("icon" + i, icon.w, true);
    });
  },
});
