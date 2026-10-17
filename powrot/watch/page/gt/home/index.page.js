// Lista miejsc (moich i udostępnionych mi) z odległością na żywo + "Zapisz to miejsce".
import * as hmUI from "@zos/ui";
import { push } from "@zos/router";
import { BasePage } from "@zeppos/zml/base-page";
import { loadPending, viewPlaces, sync, saveIncoming } from "../../../utils/store";
import { isOwn } from "../../../utils/places";
import { startGps } from "../../../utils/sensors";
import { distance, formatDistance, formatSavedAt } from "../../../utils/geo";
import { stayInApp } from "../../../utils/screen";
import { button, wideRect } from "../../../utils/ui";
import {
  DEVICE_WIDTH,
  TITLE_STYLE,
  STATUS_STYLE,
  SAVE_Y,
  EMPTY_STYLE,
  rowY,
  rowBgProps,
  rowNameStyle,
  rowInfoStyle,
  rowDistanceStyle,
  bottomSpacerProps,
} from "zosLoader:./index.page.[pf].layout.js";

// Co tyle sprawdzamy, czy lista miejsc się zmieniła (po zapisaniu/usunięciu na innym ekranie)
const WATCH_MS = 1500;
// Niewysłane zmiany próbujemy wysłać ponownie co tyle
const RETRY_MS = 30000;

Page(
  BasePage({
    state: {
      status: null,
      widgets: [],
      distances: [], // [{ point, widget, index }]
      shown: "",
      fix: null,
      gps: null,
      timer: null,
      account: "", // "", "brak konta", "offline"
      lastSyncAt: 0,
    },

    build() {
      const s = this.state;
      stayInApp();
      hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);
      s.status = hmUI.createWidget(hmUI.widget.TEXT, STATUS_STYLE);
      button(wideRect(SAVE_Y, DEVICE_WIDTH, 66), "+ Zapisz to miejsce", "primary", () =>
        push({ url: "page/gt/save/index.page" })
      );
      this.render();
      s.gps = startGps((fix) => {
        s.fix = fix;
        this.updateDistances();
      });
      this.syncNow();
      s.timer = setInterval(() => {
        if (JSON.stringify(viewPlaces()) !== s.shown) this.render();
        if (loadPending().length && Date.now() - s.lastSyncAt > RETRY_MS) this.syncNow();
      }, WATCH_MS);
    },

    onDestroy() {
      const s = this.state;
      if (s.gps) s.gps.stop();
      if (s.timer) clearInterval(s.timer);
    },

    // Telefon przysłał miejsca sam (np. zaraz po zalogowaniu w ustawieniach)
    onCall(req) {
      if (req && req.type === "DATA") {
        saveIncoming(req.result);
        this.state.account = "";
        this.render();
      }
    },

    syncNow() {
      const s = this.state;
      s.lastSyncAt = Date.now();
      sync(this, (r) => {
        s.account = r.ok ? "" : r.needsLogin ? "bez konta" : r.offline ? "offline" : "";
        this.render();
      });
    },

    render() {
      const s = this.state;
      s.widgets.forEach((w) => hmUI.deleteWidget(w));
      s.widgets = [];
      s.distances = [];
      const places = viewPlaces();
      s.shown = JSON.stringify(places);

      if (!places.length) {
        s.widgets.push(hmUI.createWidget(hmUI.widget.TEXT, EMPTY_STYLE));
        this.updateDistances();
        return;
      }
      const now = Date.now();
      places.forEach((p, i) => {
        const open = () => push({ url: "page/gt/navigate/index.page", params: JSON.stringify({ id: p.id }) });
        const when = formatSavedAt(p.at, now);
        const infoText = isOwn(p) ? when : (p.by ? "od: " + p.by.split("@")[0] : "udostępnione") + " · " + when;
        const bg = hmUI.createWidget(hmUI.widget.FILL_RECT, rowBgProps(i));
        const name = hmUI.createWidget(hmUI.widget.TEXT, { ...rowNameStyle(i), text: p.name });
        const info = hmUI.createWidget(hmUI.widget.TEXT, { ...rowInfoStyle(i), text: infoText });
        const dist = hmUI.createWidget(hmUI.widget.TEXT, rowDistanceStyle(i));
        [bg, name, info, dist].forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, open));
        s.widgets.push(bg, name, info, dist);
        s.distances.push({ point: p, widget: dist, index: i });
      });
      s.widgets.push(hmUI.createWidget(hmUI.widget.FILL_RECT, bottomSpacerProps(rowY(places.length))));
      this.updateDistances();
    },

    // Odległości odświeżamy bez przebudowy listy (GPS daje nową pozycję co sekundę)
    updateDistances() {
      const s = this.state;
      const fix = s.fix;
      const gps = fix ? "GPS: pozycja ustalona" : "GPS: szukam sygnału...";
      s.status.setProperty(hmUI.prop.MORE, { ...STATUS_STYLE, text: s.account ? gps + " · " + s.account : gps });
      s.distances.forEach((d) => {
        const text = fix ? formatDistance(distance(fix.lat, fix.lon, d.point.lat, d.point.lon)) : "";
        d.widget.setProperty(hmUI.prop.MORE, { ...rowDistanceStyle(d.index), text });
      });
    },
  })
);
