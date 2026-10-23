// Labirynt jajka: przechylaniem toczysz jajko do gniazda, omijając płotki (40 s).
import * as hmUI from "@zos/ui";
import { VIBRATOR_SCENE_NOTIFICATION, VIBRATOR_SCENE_DURATION } from "@zos/sensor";
import { EGGROLL, newEggRoll, stepEggRoll } from "../../../utils/moves";
import { newSeed } from "../../../utils/store";
import { COLOR, label, image, rect } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, startMotion, stopMotion, buzz, HINT } from "../../../utils/gamekit";
import { ITEM } from "../../../utils/geometry";
import { FIELD, EGG } from "zosLoader:./index.page.[pf].layout.js";

Page({
  state: {},

  build() {
    const s = this.state;
    s.game = newEggRoll(newSeed());
    const L = s.game.level;
    s.hint = header("Pilotaż Milano", "Trzymaj zegarek poziomo…");
    s.field = [rect(FIELD.x, FIELD.y, EGGROLL.size, EGGROLL.size, 0x2a1f14, 18)];
    L.walls.forEach(([x, y, w, h]) => s.field.push(rect(FIELD.x + x, FIELD.y + y, w, h, 0xc89a5a, 6)));
    s.nest = image("ui/nest.png", FIELD.x + L.nest[0] - ITEM / 2, FIELD.y + L.nest[1] - ITEM / 2);
    s.egg = image("ui/egg_small.png", FIELD.x + s.game.x - EGG / 2, FIELD.y + s.game.y - EGG / 2);
    s.time = label({ ...HINT, y: HINT.y + 32, size: 20 });
    const ok = startMotion(s, {
      calibrate: true,
      ready: () => s.hint.set("Przechylaj, leć do lądowiska", COLOR.grey),
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
    // krok fizyki co 20 ms (pętla jest co 40 ms)
    stepEggRoll(g, tilt.x, tilt.y, dt / 2);
    stepEggRoll(g, tilt.x, tilt.y, dt / 2);
    s.egg.set("ui/egg_small.png", Math.round(FIELD.x + g.x - EGG / 2), Math.round(FIELD.y + g.y - EGG / 2));
    s.time.set(Math.max(0, Math.ceil((EGGROLL.time - g.elapsed) / 1000)) + " s");
    if (g.done) {
      stopMotion(s);
      s.time.set("");
      s.field.forEach((w) => w.setProperty(hmUI.prop.VISIBLE, false));
      s.egg.show(false);
      s.nest.show(false);
      buzz(s, g.win ? VIBRATOR_SCENE_NOTIFICATION : VIBRATOR_SCENE_DURATION);
      finishGame(s, g.win, g.win ? "Wylądował!" : "Zabrakło czasu", "eggroll");
    }
  },
});
