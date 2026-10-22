// Skoki przez przeszkody: krótki podrzut nadgarstka w górę (albo stuknięcie ekranu) = skok.
// Przeszkody nadjeżdżają coraz szybciej; wytrzymaj 25 s.
import { VIBRATOR_SCENE_DURATION, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { RUNNER, newRunner, jump, jumpHeight, stepRunner, createFlick } from "../../../utils/moves";
import { newSeed } from "../../../utils/store";
import { COLOR, label, image, rect, onTap } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, petForm, startMotion, stopMotion, buzz, STATUS } from "../../../utils/gamekit";
import { THUMB, ITEM } from "../../../utils/geometry";
import { TRACK, POOL } from "zosLoader:./index.page.[pf].layout.js";

Page({
  state: {},

  build() {
    const s = this.state;
    const tapZone = rect(0, 0, 480, 480, 0x000000);
    onTap([tapZone], () => jump(s.game));
    s.game = newRunner(newSeed());
    s.flick = createFlick(RUNNER.flick, 450);
    s.hint = header("Skoki", "Podrzuć nadgarstek albo stuknij");
    rect(TRACK.x - 10, TRACK.y, RUNNER.w + 20, 4, 0x8a6a3e, 2);
    s.rocks = [];
    for (let i = 0; i < POOL; i++) {
      const w = image("ui/rock.png", 0, TRACK.y - ITEM + 4);
      w.show(false);
      s.rocks.push(w);
    }
    s.dinoSrc = "thumb/" + petForm() + ".png";
    s.dino = image(s.dinoSrc, TRACK.x + RUNNER.dinoX - THUMB / 2, TRACK.y - THUMB);
    s.status = label({ ...STATUS });
    const ok = startMotion(s, { tick: (a, now, dt) => this.tick(a, now, dt) });
    if (!ok) s.hint.set("Bez czujnika - skacz stuknięciem", COLOR.accent);
  },

  onDestroy() {
    stopMotion(this.state);
  },

  tick(a, now, dt) {
    const s = this.state;
    const g = s.game;
    if (s.flick.feed(a, now)) jump(g);
    stepRunner(g, dt);
    s.rocks.forEach((w, i) => {
      const o = g.obstacles[i];
      if (!o) return w.show(false);
      w.set("ui/rock.png", Math.round(TRACK.x + o.x - (ITEM - RUNNER.obstW) / 2), TRACK.y - ITEM + 4);
      w.show(true);
    });
    s.dino.set(s.dinoSrc, TRACK.x + RUNNER.dinoX - THUMB / 2, Math.round(TRACK.y - THUMB - jumpHeight(g)));
    s.status.set("Przeskoczone " + g.jumped + " · " + Math.max(0, Math.ceil((RUNNER.time - g.elapsed) / 1000)) + " s");
    if (g.done) {
      stopMotion(s);
      s.status.set("");
      buzz(s, g.win ? VIBRATOR_SCENE_NOTIFICATION : VIBRATOR_SCENE_DURATION);
      finishGame(s, g.win, g.win ? "Wygrana!" : "Potknął się", "runner");
    }
  },
});
