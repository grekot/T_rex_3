// Wyprawa (GPS, zadanie spacerowe): Groot wyznacza skarb 200-500 m od ciebie.
// Idź tam ze strzałką (kompas) - po dotarciu na 25 m skarb jest twój. Aplikację można
// zamknąć; cel jest zapisany przez 3 godziny.
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { TRIP, newTrip, tripStatus, angleDiff, dirName } from "../../../utils/walks";
import { getWalk, setWalk } from "../../../utils/pet";
import { load, apply, newSeed } from "../../../utils/store";
import { startGps, startCompass } from "../../../utils/sensors";
import { createBuzzer } from "../../../utils/device";
import { COLOR, label, button } from "../../../utils/ui";
import { finishWalk } from "../../../utils/gameui";
import { header } from "../../../utils/gamekit";
import { ARROW, DIST, INFO, START_BTN } from "zosLoader:./index.page.[pf].layout.js";

const TICK_MS = 1000;
const KEY = "trip";

function arrowProps(angle) {
  return {
    x: px(ARROW.x),
    y: px(ARROW.y),
    w: px(ARROW.size),
    h: px(ARROW.size),
    center_x: px(ARROW.size / 2),
    center_y: px(ARROW.size / 2),
    src: "ui/pointer.png",
    angle: Math.round(angle),
  };
}

Page({
  state: {},

  build() {
    const s = this.state;
    s.buzzer = createBuzzer();
    s.hint = header("Wyprawa po Orb", "Orb " + TRIP.min + "-" + TRIP.max + " m stąd");
    s.arrow = hmUI.createWidget(hmUI.widget.IMG, arrowProps(0));
    s.arrow.setProperty(hmUI.prop.VISIBLE, false);
    s.dist = label({ ...DIST, color: COLOR.accent });
    s.info = label({ ...INFO, color: COLOR.grey });
    s.btn = button(START_BTN, () => this.start());
    s.gps = startGps();
    s.compass = startCompass();
    this.tick();
    s.timer = setInterval(() => this.tick(), TICK_MS);
  },

  onDestroy() {
    const s = this.state;
    if (s.timer) clearInterval(s.timer);
    s.gps.stop();
    s.compass.stop();
    s.buzzer.stop();
  },

  showButton(v) {
    const b = this.state.btn;
    b.bg.setProperty(hmUI.prop.VISIBLE, v);
    b.txt.widget.setProperty(hmUI.prop.VISIBLE, v);
  },

  start() {
    const s = this.state;
    const fix = s.gps.read();
    if (!fix) {
      s.info.set("Czekam na GPS - wyjdź pod gołe niebo", COLOR.bad);
      return;
    }
    apply((p) => ({ state: setWalk(p, KEY, newTrip(fix, Date.now(), newSeed())) }));
    this.tick();
  },

  tick() {
    const s = this.state;
    if (s.finished) return;
    const task = getWalk(load().state, KEY);
    const fix = s.gps.read();
    const st = tripStatus(task, fix, Date.now());
    if (st.state === "none" || st.state === "expired") {
      if (st.state === "expired") apply((p) => ({ state: setWalk(p, KEY, null) }));
      s.arrow.setProperty(hmUI.prop.VISIBLE, false);
      s.dist.set(st.state === "expired" ? "Orb przepadł" : "");
      s.info.set(fix ? "Gotowe do drogi" : "Szukam GPS…");
      this.showButton(true);
      return;
    }
    this.showButton(false);
    if (st.state === "wait") {
      s.arrow.setProperty(hmUI.prop.VISIBLE, false);
      s.dist.set("…");
      s.info.set("Szukam GPS… (cel zapamiętany)");
      return;
    }
    if (st.state === "done") {
      clearInterval(s.timer);
      s.timer = null;
      s.arrow.setProperty(hmUI.prop.VISIBLE, false);
      s.dist.set("");
      s.info.set("");
      s.buzzer.buzz(VIBRATOR_SCENE_NOTIFICATION);
      finishWalk(s, KEY, "Orb zdobyty!");
      return;
    }
    const heading = s.compass.read();
    s.dist.set(st.dist + " m");
    if (heading === null) {
      s.arrow.setProperty(hmUI.prop.VISIBLE, false);
      s.info.set("Kierunek: " + dirName(st.bearing) + " (skalibruj kompas)");
    } else {
      s.arrow.setProperty(hmUI.prop.MORE, arrowProps(angleDiff(st.bearing, heading)));
      s.arrow.setProperty(hmUI.prop.VISIBLE, true);
      s.info.set("Idź za strzałką · " + dirName(st.bearing));
    }
  },
});
