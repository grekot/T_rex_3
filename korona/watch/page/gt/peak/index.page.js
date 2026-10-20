// Szczegóły szczytu: wysokość, pasmo, data zdobycia, odległość. Zaliczenie na szczycie (GPS),
// dodanie daty z przeszłości, zmiana daty i cofnięcie zdobycia.
import * as hmUI from "@zos/ui";
import { push } from "@zos/router";
import { createModal, MODAL_CONFIRM, showToast } from "@zos/interaction";
import { findPeak } from "../../../utils/peaks";
import { distance, bearing, formatDistance, cardinal } from "../../../utils/geo";
import { createSummitWatcher, todayKey, formatDate, peakLine, variantLine } from "../../../utils/korona";
import { loadClimbs, climbsStamp, saveClimb, deleteClimb } from "../../../utils/store";
import { startGps } from "../../../utils/sensors";
import { setupScreen, vibrate } from "../../../utils/device";
import { button, setText, parseParams, COLOR_WHITE, COLOR_GREY, COLOR_GREEN, COLOR_ORANGE } from "../../../utils/ui";
import {
  NAME_STYLE,
  LINE_STYLE,
  NOTE_STYLE,
  STATUS_STYLE,
  SUB_STYLE,
  GPS_STYLE,
  BUTTON1_RECT,
  BUTTON2_RECT,
} from "zosLoader:./index.page.[pf].layout.js";

const DATE_PAGE = "page/gt/date/index.page";
const NEAREST_PAGE = "page/gt/nearest/index.page";
const STAMP_POLL_MS = 1000;

function noteFor(peak) {
  const parts = [];
  if (peak.variantOf) parts.push(variantLine(peak));
  if (peak.note) parts.push(peak.note);
  if (peak.border) parts.push("wierzchołek graniczny");
  return parts.join(" · ");
}

Page({
  state: {},

  onInit(params) {
    this.state.id = parseParams(params).id || "";
  },

  build() {
    const s = this.state;
    s.peak = findPeak(s.id);
    s.fix = null;
    s.here = false;
    s.buttons = [];
    s.buttonsKey = "";
    setupScreen(30000);

    const name = hmUI.createWidget(hmUI.widget.TEXT, NAME_STYLE);
    if (!s.peak) {
      setText(name, NAME_STYLE, "Nie ma szczytu");
      return;
    }
    setText(name, NAME_STYLE, s.peak.name);
    hmUI.createWidget(hmUI.widget.TEXT, { ...LINE_STYLE, text: peakLine(s.peak) });
    hmUI.createWidget(hmUI.widget.TEXT, { ...NOTE_STYLE, text: noteFor(s.peak) });
    s.status = hmUI.createWidget(hmUI.widget.TEXT, STATUS_STYLE);
    s.sub = hmUI.createWidget(hmUI.widget.TEXT, SUB_STYLE);
    s.gpsText = hmUI.createWidget(hmUI.widget.TEXT, GPS_STYLE);

    this.refresh();
    s.stampTimer = setInterval(() => {
      if (climbsStamp() !== s.stamp) this.refresh();
    }, STAMP_POLL_MS);

    // Rozpoznanie tylko tego szczytu - ten sam strażnik co na ekranie głównym
    const watcher = createSummitWatcher();
    s.gps = startGps((fix) => {
      s.fix = fix || s.fix;
      const r = watcher.update(fix);
      const here = !!(r.peak && r.peak.id === s.peak.id);
      if (here && r.entered && !s.climb) vibrate();
      s.here = here;
      this.render();
    });
  },

  onDestroy() {
    const s = this.state;
    if (s.stampTimer) clearInterval(s.stampTimer);
    if (s.gps) s.gps.stop();
  },

  refresh() {
    const s = this.state;
    s.stamp = climbsStamp();
    s.climb = loadClimbs()[s.peak.id] || null;
    this.render();
  },

  render() {
    const s = this.state;
    if (!s.status) return;
    if (s.climb) {
      setText(s.status, STATUS_STYLE, "Zdobyty " + formatDate(s.climb.d), COLOR_GREEN);
      setText(s.sub, SUB_STYLE, s.climb.gps ? "zaliczony na szczycie (GPS)" : "dodany ręcznie");
    } else {
      setText(s.status, STATUS_STYLE, "Niezdobyty", COLOR_GREY);
      setText(s.sub, SUB_STYLE, s.peak.variantOf ? "nie liczy się do 28" : "");
    }

    if (s.here) {
      setText(s.gpsText, GPS_STYLE, "Jesteś na szczycie!", COLOR_GREEN);
    } else if (s.fix) {
      const d = distance(s.fix.lat, s.fix.lon, s.peak.lat, s.peak.lon);
      const b = bearing(s.fix.lat, s.fix.lon, s.peak.lat, s.peak.lon);
      setText(s.gpsText, GPS_STYLE, formatDistance(d) + " stąd · " + cardinal(b), COLOR_WHITE);
    } else {
      setText(s.gpsText, GPS_STYLE, "Szukam GPS...", COLOR_ORANGE);
    }

    let key;
    if (s.climb) key = "climbed";
    else if (s.here) key = "here";
    else key = "todo";
    this.setButtons(key);
  },

  setButtons(key) {
    const s = this.state;
    if (s.buttonsKey === key) return;
    s.buttonsKey = key;
    s.buttons.forEach((w) => hmUI.deleteWidget(w));
    s.buttons = [];
    const openDate = () => push({ url: DATE_PAGE, params: JSON.stringify({ id: s.peak.id }) });
    if (key === "climbed") {
      s.buttons.push(button(BUTTON1_RECT, "Zmień datę", "secondary", openDate));
      s.buttons.push(button(BUTTON2_RECT, "Cofnij", "danger", () => this.undo()));
    } else if (key === "here") {
      s.buttons.push(button(BUTTON1_RECT, "Zaliczam", "success", () => this.climbNow()));
      s.buttons.push(button(BUTTON2_RECT, "Inna data", "secondary", openDate));
    } else {
      s.buttons.push(
        button(BUTTON1_RECT, "Prowadź", "primary", () =>
          push({ url: NEAREST_PAGE, params: JSON.stringify({ id: s.peak.id }) })
        )
      );
      s.buttons.push(button(BUTTON2_RECT, "Dodaj datę", "secondary", openDate));
    }
  },

  climbNow() {
    const s = this.state;
    saveClimb(s.peak.id, todayKey(Date.now()), true);
    try {
      showToast({ content: "Zaliczone: " + s.peak.name });
    } catch (e) {}
    this.refresh();
  },

  undo() {
    const s = this.state;
    const dialog = createModal({
      content: "Cofnąć zdobycie: " + s.peak.name + "?",
      autoHide: true,
      onClick: (k) => {
        if (k && k.type === MODAL_CONFIRM) {
          deleteClimb(s.peak.id);
          this.refresh();
        }
      },
    });
    try {
      dialog.show(true);
    } catch (e) {}
  },
});
