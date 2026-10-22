// Powtórz ruch: dinozaur pokazuje strzałki, a ty powtarzasz je przechyłami zegarka
// (lewo, prawo, od siebie = góra, do siebie = dół). Co rundę sekwencja dłuższa.
import { VIBRATOR_SCENE_SHORT_LIGHT, VIBRATOR_SCENE_DURATION, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { SIMON, newSimon, simonInput, createTiltReader } from "../../../utils/moves";
import { newSeed } from "../../../utils/store";
import { COLOR, label, image } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, petForm, startMotion, stopMotion, buzz, STATUS } from "../../../utils/gamekit";
import { ARROW_POS, ROUND, PET } from "zosLoader:./index.page.[pf].layout.js";

const SHOW_MS = 650;
const GAP_MS = 250;
const ARROWS = { left: "ui/arrow_l.png", right: "ui/arrow_r.png", up: "ui/arrow_u.png", down: "ui/arrow_d.png" };

Page({
  state: {},

  build() {
    const s = this.state;
    s.game = newSimon(newSeed());
    s.reader = createTiltReader();
    s.hint = header("Powtórz ruch", "Trzymaj zegarek poziomo…");
    s.arrow = image(ARROWS.left, ARROW_POS.x, ARROW_POS.y);
    s.arrow.show(false);
    s.round = label({ ...ROUND });
    image("thumb/" + petForm() + ".png", PET.x, PET.y);
    s.status = label({ ...STATUS, color: COLOR.grey });
    s.phase = "calib";
    const ok = startMotion(s, {
      calibrate: true,
      ready: () => this.showSequence(),
      tick: (a, now, dt, tilt) => this.tick(tilt),
    });
    if (!ok) s.hint.set("Brak akcelerometru", COLOR.bad);
    this.renderRound();
  },

  onDestroy() {
    if (this.state.timer) clearTimeout(this.state.timer);
    stopMotion(this.state);
  },

  renderRound() {
    const g = this.state.game;
    this.state.round.set("Długość " + g.level + "/" + SIMON.win + " · życia " + g.lives);
  },

  showSequence() {
    const s = this.state;
    s.phase = "show";
    s.hint.set("Patrz i zapamiętaj", COLOR.grey);
    s.status.set("");
    let i = 0;
    const step = () => {
      if (i >= s.game.level) {
        s.arrow.show(false);
        s.phase = "input";
        s.reader = createTiltReader();
        s.hint.set("Teraz ty: przechylaj!", COLOR.accent);
        return;
      }
      s.arrow.set(ARROWS[s.game.seq[i]]);
      s.arrow.show(true);
      s.timer = setTimeout(() => {
        s.arrow.show(false);
        i++;
        s.timer = setTimeout(step, GAP_MS);
      }, SHOW_MS);
    };
    s.timer = setTimeout(step, 600);
  },

  tick(tilt) {
    const s = this.state;
    if (s.phase !== "input") return;
    const dir = s.reader.feed(tilt.x, tilt.y);
    if (!dir) return;
    s.arrow.set(ARROWS[dir]);
    s.arrow.show(true);
    const r = simonInput(s.game, dir);
    s.game = r.game;
    this.renderRound();
    if (r.event === "ok") buzz(s, VIBRATOR_SCENE_SHORT_LIGHT);
    else if (r.event === "round") {
      s.phase = "wait";
      s.status.set("Dobrze! Dłuższa sekwencja", COLOR.good);
      s.timer = setTimeout(() => this.showSequence(), 900);
    } else if (r.event === "wrong") {
      buzz(s, VIBRATOR_SCENE_DURATION);
      s.phase = "wait";
      s.status.set("Pomyłka - jeszcze raz", COLOR.bad);
      s.timer = setTimeout(() => this.showSequence(), 1200);
    } else if (r.event === "win" || r.event === "lose") {
      s.phase = "done";
      s.status.set("");
      stopMotion(s);
      if (r.event === "win") buzz(s, VIBRATOR_SCENE_NOTIFICATION);
      finishGame(s, r.event === "win", r.event === "win" ? "Wygrana!" : "Tym razem nie", "simon");
    }
  },
});
