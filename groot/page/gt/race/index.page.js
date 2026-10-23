// Wyścig z Grootem: przez 15 s biegnij w miejscu albo machaj rękami jak przy biegu -
// twój Groot biegnie w tempie ruchów. Rywal (Rocket) biegnie równo; wyprzedź go.
import { VIBRATOR_SCENE_NOTIFICATION, VIBRATOR_SCENE_DURATION } from "@zos/sensor";
import { RACE, newRace, feedRace } from "../../../utils/moves";
import { COLOR, label, image, rect } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, petForm, startMotion, stopMotion, buzz, STATUS } from "../../../utils/gamekit";
import { THUMB } from "../../../utils/geometry";
import { TRACK, FINISH } from "zosLoader:./index.page.[pf].layout.js";

const TOTAL = (RACE.rival * RACE.time) / 1000; // tyle "kroków" rywal robi do końca

function xFor(steps) {
  return Math.round(TRACK.x0 + ((TRACK.x1 - TRACK.x0) * Math.min(1.15, steps / TOTAL)) - THUMB / 2);
}

Page({
  state: {},

  build() {
    const s = this.state;
    s.game = newRace();
    const form = petForm();
    s.hint = header("Wyścig z Rocketem", "Biegnij w miejscu, machaj rękami!");
    rect(FINISH.x, FINISH.y, 6, FINISH.h, 0xffffff, 3);
    rect(TRACK.x0 - 40, TRACK.you + THUMB, TRACK.x1 - TRACK.x0 + 120, 3, 0x3f7a46, 1);
    rect(TRACK.x0 - 40, TRACK.rival + THUMB, TRACK.x1 - TRACK.x0 + 120, 3, 0x3f7a46, 1);
    s.youSrc = "thumb/" + form + ".png";
    s.you = image(s.youSrc, xFor(0), TRACK.you);
    s.rivalSrc = "ui/rocket.png";
    s.rival = image(s.rivalSrc, xFor(0), TRACK.rival);
    s.status = label({ ...STATUS });
    const ok = startMotion(s, { tick: (a, now, dt) => this.tick(a, now, dt) });
    if (!ok) s.hint.set("Brak akcelerometru", COLOR.bad);
  },

  onDestroy() {
    stopMotion(this.state);
  },

  tick(a, now, dt) {
    const s = this.state;
    const g = s.game;
    feedRace(g, a, now, dt);
    s.you.set(s.youSrc, xFor(g.you), TRACK.you);
    s.rival.set(s.rivalSrc, xFor(g.rival), TRACK.rival);
    s.status.set((g.you >= g.rival ? "Prowadzisz" : "Goń go!") + " · " + Math.max(0, Math.ceil((RACE.time - g.elapsed) / 1000)) + " s", g.you >= g.rival ? COLOR.good : COLOR.accent);
    if (g.done) {
      stopMotion(s);
      s.status.set("");
      buzz(s, g.win ? VIBRATOR_SCENE_NOTIFICATION : VIBRATOR_SCENE_DURATION);
      finishGame(s, g.win, g.win ? "Pierwszy na mecie!" : "Drugie miejsce", "race");
    }
  },
});
