// Najbliższe niezdobyte szczyty ze strzałką kompasu (jak w aplikacji Powrót).
// Bez parametrów: ze wszystkich list, { g }: z jednej listy - kolejne po odległości (‹ ›).
// Z { id }: prowadzi do jednego szczytu.
import * as hmUI from "@zos/ui";
import { push } from "@zos/router";
import { showToast } from "@zos/interaction";
import { px } from "@zos/utils";
import { findPeak, findGroup, allPeaks } from "../../../utils/peaks";
import { distance, bearing, relativeAngle, smoothAngle, formatDistance, cardinal } from "../../../utils/geo";
import { nearestUnclimbed, createSummitWatcher, climbOf, todayKey, peakLine } from "../../../utils/korona";
import { loadClimbs, loadCustom, stamp, saveClimb } from "../../../utils/store";
import { startGps, startCompass } from "../../../utils/sensors";
import { setupScreen, vibrate } from "../../../utils/device";
import { button, setText, parseParams, COLOR_WHITE, COLOR_GREY, COLOR_GREEN, COLOR_ORANGE } from "../../../utils/ui";
import {
  NAME_STYLE,
  LINE_STYLE,
  ARROW_PROPS,
  PREV_RECT,
  NEXT_RECT,
  INDEX_STYLE,
  DISTANCE_STYLE,
  DIRECTION_STYLE,
  HINT_STYLE,
  BUTTON_RECT,
} from "zosLoader:./index.page.[pf].layout.js";

const PEAK_PAGE = "page/gt/peak/index.page";
const STAMP_POLL_MS = 1000;
// Im mniej, tym spokojniejsza (ale wolniejsza) strzałka
const SMOOTHING = 0.35;

Page({
  state: {},

  onInit(params) {
    const p = parseParams(params);
    this.state.fixedId = p.id || "";
    this.state.groupId = findGroup(p.g) ? p.g : null;
  },

  build() {
    const s = this.state;
    s.fix = null;
    s.heading = null; // wygładzony kierunek zegarka (null = kompas nieskalibrowany)
    s.summit = null;
    s.selectedId = s.fixedId;
    s.watcher = createSummitWatcher();
    s.actionKey = "";
    s.action = null;
    setupScreen(60000);

    s.name = hmUI.createWidget(hmUI.widget.TEXT, NAME_STYLE);
    s.line = hmUI.createWidget(hmUI.widget.TEXT, LINE_STYLE);
    s.arrow = hmUI.createWidget(hmUI.widget.IMG, ARROW_PROPS);
    s.arrow.setProperty(hmUI.prop.VISIBLE, false);
    if (!s.fixedId) {
      s.prev = button(PREV_RECT, "‹", "secondary", () => this.select(-1), px(36));
      s.next = button(NEXT_RECT, "›", "secondary", () => this.select(1), px(36));
      s.index = hmUI.createWidget(hmUI.widget.TEXT, INDEX_STYLE);
    }
    s.distance = hmUI.createWidget(hmUI.widget.TEXT, DISTANCE_STYLE);
    s.direction = hmUI.createWidget(hmUI.widget.TEXT, DIRECTION_STYLE);
    s.hint = hmUI.createWidget(hmUI.widget.TEXT, HINT_STYLE);

    this.reload();
    s.stampTimer = setInterval(() => {
      if (stamp() !== s.stamp) this.reload();
    }, STAMP_POLL_MS);

    s.gps = startGps((fix) => {
      s.fix = fix || s.fix;
      const r = s.watcher.update(fix, s.peaks);
      s.summit = r.peak;
      if (r.entered && !climbOf(r.peak.id, s.climbs, s.custom)) vibrate();
      this.update();
    });
    s.compass = startCompass((angle) => {
      s.heading = angle === null ? null : smoothAngle(s.heading, angle, SMOOTHING);
      this.updateArrow();
    });
  },

  onDestroy() {
    const s = this.state;
    if (s.stampTimer) clearInterval(s.stampTimer);
    if (s.gps) s.gps.stop();
    if (s.compass) s.compass.stop();
  },

  reload() {
    const s = this.state;
    s.stamp = stamp();
    s.climbs = loadClimbs();
    s.custom = loadCustom();
    s.peaks = allPeaks(s.custom);
    this.update();
  },

  // Kolejka szczytów wg odległości i wybrany cel
  targets() {
    const s = this.state;
    if (s.fixedId) {
      const p = findPeak(s.fixedId, s.custom);
      return p ? [{ peak: p, distance: s.fix ? distance(s.fix.lat, s.fix.lon, p.lat, p.lon) : null }] : [];
    }
    return nearestUnclimbed(s.fix, s.climbs, s.groupId, 0);
  },

  // Wybrany cel z kolejki policzonej przy ostatniej pozycji GPS
  target() {
    const s = this.state;
    const list = s.list || [];
    // Dopóki nie przełączono ‹ ›, celem jest zawsze najbliższy (zmienia się, gdy idziesz)
    let i = 0;
    if (s.picked) for (let k = 0; k < list.length; k++) if (list[k].peak.id === s.selectedId) i = k;
    const t = list[i] || null;
    s.selectedId = t ? t.peak.id : "";
    return { t, i, n: list.length };
  },

  select(delta) {
    const s = this.state;
    const list = s.list || [];
    if (!list.length) return;
    const { i } = this.target();
    const next = (i + delta + list.length) % list.length;
    s.selectedId = list[next].peak.id;
    s.picked = next !== 0;
    this.update();
  },

  update() {
    const s = this.state;
    if (!s.distance) return;
    s.list = this.targets();
    const { t, i, n } = this.target();
    if (s.index) setText(s.index, INDEX_STYLE, n ? i + 1 + " / " + n : "");
    if (s.groupLabel === undefined) s.groupLabel = s.groupId ? findGroup(s.groupId).short : "";

    if (!t) {
      setText(s.name, NAME_STYLE, s.fix ? "Wszystko zdobyte!" : "Najbliższe szczyty", s.fix ? COLOR_GREEN : COLOR_WHITE);
      setText(s.line, LINE_STYLE, s.groupLabel);
      setText(s.distance, DISTANCE_STYLE, "--", COLOR_GREY);
      setText(s.direction, DIRECTION_STYLE, "");
    } else {
      setText(s.name, NAME_STYLE, t.peak.name);
      setText(s.line, LINE_STYLE, peakLine(t.peak));
      if (s.fix) {
        const b = bearing(s.fix.lat, s.fix.lon, t.peak.lat, t.peak.lon);
        const here = s.summit && s.summit.id === t.peak.id;
        setText(s.distance, DISTANCE_STYLE, here ? "Na szczycie!" : formatDistance(t.distance), here ? COLOR_GREEN : COLOR_WHITE);
        setText(s.direction, DIRECTION_STYLE, here ? "" : cardinal(b) + " · " + Math.round(b) + "°");
      } else {
        setText(s.distance, DISTANCE_STYLE, "--", COLOR_GREY);
        setText(s.direction, DIRECTION_STYLE, "");
      }
    }

    if (!s.fix) {
      setText(s.hint, HINT_STYLE, "Szukam sygnału GPS...", COLOR_ORANGE);
    } else if (s.summit) {
      setText(s.hint, HINT_STYLE, "Jesteś na szczycie " + s.summit.name + "!", COLOR_GREEN);
    }
    this.setAction(s.summit && !climbOf(s.summit.id, s.climbs, s.custom) ? "climb" : t ? "details" : "none");
    this.updateArrow();
  },

  // Obrót strzałki - przy każdej zmianie kompasu (często)
  updateArrow() {
    const s = this.state;
    if (!s.arrow) return;
    const { t } = this.target();
    const here = t && s.summit && s.summit.id === t.peak.id;
    const ready = t && s.fix && s.heading !== null && !here;
    s.arrow.setProperty(hmUI.prop.VISIBLE, !!ready);
    if (s.fix && !s.summit) {
      if (t && s.heading === null) setText(s.hint, HINT_STYLE, "Skalibruj kompas: zatocz nadgarstkiem ósemkę", COLOR_ORANGE);
      else setText(s.hint, HINT_STYLE, "", COLOR_GREY);
    }
    if (!ready) return;
    const b = bearing(s.fix.lat, s.fix.lon, t.peak.lat, t.peak.lon);
    s.arrow.setProperty(hmUI.prop.MORE, { ...ARROW_PROPS, angle: Math.round(relativeAngle(b, s.heading)) });
  },

  setAction(key) {
    const s = this.state;
    if (s.actionKey === key) return;
    s.actionKey = key;
    if (s.action) hmUI.deleteWidget(s.action);
    s.action = null;
    if (key === "climb") s.action = button(BUTTON_RECT, "Zaliczam", "success", () => this.climb(), px(24));
    if (key === "details")
      s.action = button(BUTTON_RECT, "Szczegóły", "secondary", () => {
        const { t } = this.target();
        if (t) push({ url: PEAK_PAGE, params: JSON.stringify({ id: t.peak.id }) });
      }, px(22));
  },

  climb() {
    const s = this.state;
    if (!s.summit) return;
    const name = s.summit.name;
    saveClimb(s.summit.id, todayKey(Date.now()), true);
    try {
      showToast({ content: "Zaliczone: " + name });
    } catch (e) {}
    this.reload();
  },
});
