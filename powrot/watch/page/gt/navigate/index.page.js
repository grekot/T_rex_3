// Nawigacja do zapisanego miejsca: strzałka (GPS + kompas), odległość, kierunek.
import * as hmUI from "@zos/ui";
import { back } from "@zos/router";
import { createModal, MODAL_CONFIRM } from "@zos/interaction";
import { Vibrator, VIBRATOR_SCENE_SHORT_STRONG } from "@zos/sensor";
import { px } from "@zos/utils";
import { BasePage } from "@zeppos/zml/base-page";
import { viewPlaces, addOps, sync } from "../../../utils/store";
import { findPlace, isOwn, removeOp } from "../../../utils/places";
import { startGps, startCompass } from "../../../utils/sensors";
import {
  distance,
  bearing,
  relativeAngle,
  smoothAngle,
  formatDistance,
  formatSavedAt,
  cardinal,
  ARRIVED_M,
} from "../../../utils/geo";
import { stayInApp, keepBright } from "../../../utils/screen";
import { button, COLOR_WHITE, COLOR_GREY, COLOR_ORANGE, COLOR_GREEN } from "../../../utils/ui";
import {
  NAME_STYLE,
  SAVED_STYLE,
  ARROW_PROPS,
  DISTANCE_STYLE,
  DIRECTION_STYLE,
  HINT_STYLE,
  DELETE_RECT,
} from "zosLoader:./index.page.[pf].layout.js";

// Im mniej, tym spokojniejsza (ale wolniejsza) strzałka
const SMOOTHING = 0.35;

function parseParams(params) {
  try {
    return typeof params === "string" ? JSON.parse(params) : params || {};
  } catch (e) {
    return {};
  }
}

Page(
  BasePage({
  state: {
    pointId: "",
    point: null,
    fix: null,
    heading: null, // wygładzony kierunek zegarka (null = kompas nieskalibrowany)
    arrived: false,
    arrow: null,
    distance: null,
    direction: null,
    hint: null,
    gps: null,
    compass: null,
  },

  onInit(params) {
    this.state.pointId = parseParams(params).id || "";
  },

  build() {
    const s = this.state;
    stayInApp();
    keepBright(60000);
    s.point = findPlace(viewPlaces(), s.pointId);
    const name = hmUI.createWidget(hmUI.widget.TEXT, NAME_STYLE);
    const saved = hmUI.createWidget(hmUI.widget.TEXT, SAVED_STYLE);
    if (!s.point) {
      name.setProperty(hmUI.prop.MORE, { ...NAME_STYLE, text: "Miejsce usunięte" });
      return;
    }
    name.setProperty(hmUI.prop.MORE, { ...NAME_STYLE, text: s.point.name });
    const when = formatSavedAt(s.point.at, Date.now());
    const from = isOwn(s.point) ? "zapisano " : (s.point.by ? s.point.by.split("@")[0] : "udostępnione") + " · ";
    saved.setProperty(hmUI.prop.MORE, { ...SAVED_STYLE, text: from + when });

    s.arrow = hmUI.createWidget(hmUI.widget.IMG, ARROW_PROPS);
    s.arrow.setProperty(hmUI.prop.VISIBLE, false);
    s.distance = hmUI.createWidget(hmUI.widget.TEXT, DISTANCE_STYLE);
    s.direction = hmUI.createWidget(hmUI.widget.TEXT, DIRECTION_STYLE);
    s.hint = hmUI.createWidget(hmUI.widget.TEXT, HINT_STYLE);
    button(DELETE_RECT, isOwn(s.point) ? "Usuń" : "Usuń u mnie", "danger", () => this.remove(), px(22));

    s.gps = startGps((fix) => {
      s.fix = fix || s.fix;
      this.update();
    });
    s.compass = startCompass((angle) => {
      s.heading = angle === null ? null : smoothAngle(s.heading, angle, SMOOTHING);
      this.updateArrow();
    });
    this.update();
  },

  onDestroy() {
    const s = this.state;
    if (s.gps) s.gps.stop();
    if (s.compass) s.compass.stop();
  },

  // Odległość, kierunek, podpowiedzi - przy każdej nowej pozycji GPS
  update() {
    const s = this.state;
    if (!s.point || !s.distance) return;
    if (!s.fix) {
      this.setText(s.distance, DISTANCE_STYLE, "--", COLOR_GREY);
      this.setText(s.direction, DIRECTION_STYLE, "", COLOR_GREY);
      this.setText(s.hint, HINT_STYLE, "Szukam sygnału GPS...", COLOR_ORANGE);
      this.updateArrow();
      return;
    }
    const d = distance(s.fix.lat, s.fix.lon, s.point.lat, s.point.lon);
    const b = bearing(s.fix.lat, s.fix.lon, s.point.lat, s.point.lon);

    // Na miejscu: jedna mocna wibracja; ponownie dopiero po oddaleniu się
    if (d <= ARRIVED_M && !s.arrived) {
      s.arrived = true;
      this.vibrate();
    } else if (d > ARRIVED_M * 2) {
      s.arrived = false;
    }

    if (s.arrived) {
      this.setText(s.distance, DISTANCE_STYLE, "Na miejscu!", COLOR_GREEN);
    } else {
      this.setText(s.distance, DISTANCE_STYLE, formatDistance(d), COLOR_WHITE);
    }
    this.setText(s.direction, DIRECTION_STYLE, cardinal(b) + " · " + Math.round(b) + "°", COLOR_GREY);
    this.updateArrow();
  },

  // Obrót strzałki - przy każdej zmianie kompasu (często), więc tylko jedna właściwość
  updateArrow() {
    const s = this.state;
    if (!s.arrow) return;
    const ready = s.fix && s.heading !== null && !s.arrived;
    s.arrow.setProperty(hmUI.prop.VISIBLE, !!ready);
    if (s.fix && s.heading === null && !s.arrived) {
      this.setText(s.hint, HINT_STYLE, "Skalibruj kompas: zatocz nadgarstkiem ósemkę", COLOR_ORANGE);
    } else if (s.fix) {
      this.setText(s.hint, HINT_STYLE, "", COLOR_GREY);
    }
    if (!ready) return;
    const b = bearing(s.fix.lat, s.fix.lon, s.point.lat, s.point.lon);
    s.arrow.setProperty(hmUI.prop.MORE, { ...ARROW_PROPS, angle: Math.round(relativeAngle(b, s.heading)) });
  },

  setText(widget, style, text, color) {
    widget.setProperty(hmUI.prop.MORE, { ...style, text, color });
  },

  vibrate() {
    try {
      const v = new Vibrator();
      // krótka, mocna - tryby "reminder/call" potrafią wibrować do odwołania
      v.setMode(VIBRATOR_SCENE_SHORT_STRONG);
      v.start();
    } catch (e) {}
  },

  // Własne miejsce usuwamy (także u osób, którym je udostępniono); cudze tylko u siebie
  remove() {
    const s = this.state;
    const own = isOwn(s.point);
    const dialog = createModal({
      content: own
        ? (s.point.s > 1 ? "Usunąć „" + s.point.name + "” u wszystkich?" : "Usunąć „" + s.point.name + "”?")
        : "Usunąć „" + s.point.name + "” u siebie?",
      autoHide: true,
      onClick: (key) => {
        if (key && key.type === MODAL_CONFIRM) {
          addOps([removeOp(s.point, Date.now())]);
          sync(this, () => {});
          back();
        }
      },
    });
    try {
      dialog.show(true);
    } catch (e) {}
  },
  })
);
