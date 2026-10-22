// Łapanie owoców: przechylaj zegarek w bok, dinozaur biega po dole i łapie owoce,
// kamieni trzeba unikać (3 życia). 10 owoców w 30 s = wygrana.
import { VIBRATOR_SCENE_SHORT_LIGHT, VIBRATOR_SCENE_DURATION, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { CATCH, newCatch, stepCatch } from "../../../utils/moves";
import { newSeed } from "../../../utils/store";
import { COLOR, label, image, rect } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, petForm, startMotion, stopMotion, buzz, STATUS } from "../../../utils/gamekit";
import { THUMB, ITEM } from "../../../utils/geometry";
import { FIELD, POOL } from "zosLoader:./index.page.[pf].layout.js";

Page({
  state: {},

  build() {
    const s = this.state;
    s.game = newCatch(newSeed());
    s.hint = header("Łapanie owoców", "Trzymaj zegarek poziomo…");
    rect(FIELD.x - 10, FIELD.y + CATCH.h + 2, CATCH.w + 20, 4, 0x3f7a46, 2);
    s.items = [];
    for (let i = 0; i < POOL; i++) {
      const w = image("ui/apple.png", FIELD.x, FIELD.y);
      w.show(false);
      s.items.push(w);
    }
    s.dinoSrc = "thumb/" + petForm() + ".png";
    s.dino = image(s.dinoSrc, FIELD.x + CATCH.w / 2 - THUMB / 2, FIELD.y + CATCH.h - THUMB);
    s.status = label({ ...STATUS });
    const ok = startMotion(s, {
      calibrate: true,
      ready: () => s.hint.set("Przechylaj w lewo i w prawo", COLOR.grey),
      tick: (a, now, dt, tilt) => this.tick(tilt, dt),
    });
    if (!ok) s.hint.set("Brak akcelerometru", COLOR.bad);
  },

  onDestroy() {
    stopMotion(this.state);
  },

  tick(tilt, dt) {
    const s = this.state;
    const g = s.game;
    const ev = stepCatch(g, tilt.x, dt);
    if (ev.indexOf("fruit") >= 0) buzz(s, VIBRATOR_SCENE_SHORT_LIGHT);
    if (ev.indexOf("rock") >= 0) buzz(s, VIBRATOR_SCENE_DURATION);
    this.render();
    if (g.done) {
      stopMotion(s);
      s.items.forEach((w) => w.show(false));
      s.status.set("");
      if (g.win) buzz(s, VIBRATOR_SCENE_NOTIFICATION);
      finishGame(s, g.win, g.win ? "Wygrana!" : "Tym razem nie");
    }
  },

  render() {
    const s = this.state;
    const g = s.game;
    s.items.forEach((w, i) => {
      const it = g.items[i];
      if (!it) return w.show(false);
      w.set(it.kind === "rock" ? "ui/rock.png" : "ui/apple.png", Math.round(FIELD.x + it.x - ITEM / 2), Math.round(FIELD.y + it.y - ITEM / 2));
      w.show(true);
    });
    s.dino.set(s.dinoSrc, Math.round(FIELD.x + g.x - THUMB / 2), FIELD.y + CATCH.h - THUMB);
    s.status.set("Owoce " + g.caught + "/" + CATCH.need + " · życia " + g.lives + " · " + Math.max(0, Math.ceil((CATCH.time - g.elapsed) / 1000)) + " s");
  },
});
