// Wspinaczka (barometr, zadanie spacerowe): "Start" zapamiętuje wysokość, potem wejdź
// 3 m wyżej (schody, góra) w ciągu 6 godzin. Aplikacja nie musi być włączona - po
// powrocie do tej gry zegarek sprawdzi, czy już jesteś wyżej.
import * as hmUI from "@zos/ui";
import { VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { CLIMB, newClimb, climbStatus } from "../../../utils/walks";
import { getWalk, setWalk } from "../../../utils/pet";
import { load, apply } from "../../../utils/store";
import { startAltimeter } from "../../../utils/sensors";
import { createBuzzer } from "../../../utils/device";
import { COLOR, label, image, button } from "../../../utils/ui";
import { finishWalk } from "../../../utils/gameui";
import { header, petForm } from "../../../utils/gamekit";
import { PET, BIG, INFO, START_BTN } from "zosLoader:./index.page.[pf].layout.js";

const TICK_MS = 1000;
const KEY = "climb";

Page({
  state: {},

  build() {
    const s = this.state;
    s.buzzer = createBuzzer();
    s.hint = header("Wspinaczka", "Wejdź " + CLIMB.need + " m wyżej (schody, góra)");
    image("thumb/" + petForm() + ".png", PET.x, PET.y);
    s.big = label({ ...BIG, color: COLOR.accent });
    s.info = label({ ...INFO, color: COLOR.grey });
    s.btn = button(START_BTN, () => this.start());
    s.alt = startAltimeter();
    this.tick();
    s.timer = setInterval(() => this.tick(), TICK_MS);
  },

  onDestroy() {
    const s = this.state;
    if (s.timer) clearInterval(s.timer);
    s.alt.stop();
    s.buzzer.stop();
  },

  showButton(v) {
    const b = this.state.btn;
    b.bg.setProperty(hmUI.prop.VISIBLE, v);
    b.txt.widget.setProperty(hmUI.prop.VISIBLE, v);
  },

  start() {
    const s = this.state;
    const alt = s.alt.read();
    if (alt === null) {
      s.info.set("Barometr jeszcze nie podał wysokości - chwilę", COLOR.bad);
      return;
    }
    apply((p) => ({ state: setWalk(p, KEY, newClimb(alt, Date.now())) }));
    this.tick();
  },

  tick() {
    const s = this.state;
    if (s.finished) return;
    const task = getWalk(load().state, KEY);
    const st = climbStatus(task, s.alt.read(), Date.now());
    if (st.state === "none" || st.state === "expired") {
      if (st.state === "expired") apply((p) => ({ state: setWalk(p, KEY, null) }));
      s.big.set(st.state === "expired" ? "Czas minął" : "");
      s.info.set("Stuknij Start, potem idź po schodach albo pod górę. Masz " + CLIMB.ttl / 3600000 + " h.");
      this.showButton(true);
      return;
    }
    this.showButton(false);
    if (st.state === "wait") {
      s.big.set("…");
      s.info.set("Czekam na barometr");
      return;
    }
    if (st.state === "done") {
      clearInterval(s.timer);
      s.timer = null;
      s.big.set("");
      s.info.set("");
      s.buzzer.buzz(VIBRATOR_SCENE_NOTIFICATION);
      finishWalk(s, KEY, "Na szczycie!");
      return;
    }
    const left = Math.max(0, CLIMB.need - st.gain);
    s.big.set((st.gain >= 0 ? "+" : "") + st.gain.toFixed(1) + " m");
    s.info.set("Jeszcze " + left.toFixed(1) + " m w górę. Możesz zamknąć grę i wrócić tu później.");
  },
});
