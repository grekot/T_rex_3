// Potrząśnij drzewem: potrząsaj ręką, z drzewa spadają owoce (12 w 15 s).
// Za mocne szarpnięcie strąca ul - dwa razy i pszczoły przeganiają dinozaura.
import { VIBRATOR_SCENE_SHORT_LIGHT, VIBRATOR_SCENE_DURATION, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { TREE, newTree, feedTree } from "../../../utils/moves";
import { COLOR, label, image } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, startMotion, stopMotion, buzz, STATUS } from "../../../utils/gamekit";
import { TREE_POS, DROP, HIVE } from "zosLoader:./index.page.[pf].layout.js";

Page({
  state: {},

  build() {
    const s = this.state;
    s.game = newTree();
    s.hint = header("Potrząśnij drzewem", "Potrząsaj ręką, ale nie za mocno!");
    image("ui/forest.png", TREE_POS.x, TREE_POS.y);
    s.apple = image("ui/apple.png", DROP.x0, DROP.y0);
    s.apple.show(false);
    s.hive = image("ui/hive.png", HIVE.x, HIVE.y);
    s.hive.show(false);
    s.status = label({ ...STATUS });
    s.drop = null;
    const ok = startMotion(s, { tick: (a, now, dt) => this.tick(a, now, dt) });
    if (!ok) s.hint.set("Brak akcelerometru", COLOR.bad);
  },

  onDestroy() {
    stopMotion(this.state);
  },

  tick(a, now, dt) {
    const s = this.state;
    const g = s.game;
    const ev = feedTree(g, a, now, dt);
    if (ev === "fruit") {
      buzz(s, VIBRATOR_SCENE_SHORT_LIGHT);
      s.drop = { x: DROP.x0 + ((g.fruits * 37) % (DROP.x1 - DROP.x0)), t: now };
    } else if (ev === "bees") {
      buzz(s, VIBRATOR_SCENE_DURATION);
      s.hive.show(true);
      s.hint.set("Uwaga, pszczoły! Delikatniej", COLOR.bad);
    }
    if (s.drop) {
      const f = Math.min(1, (now - s.drop.t) / 350);
      s.apple.set("ui/apple.png", s.drop.x, Math.round(DROP.y0 + (DROP.y1 - DROP.y0) * f));
      s.apple.show(true);
      if (f >= 1) s.drop = null;
    } else s.apple.show(false);
    s.status.set("Owoce " + g.fruits + "/" + TREE.need + " · " + Math.max(0, Math.ceil((TREE.time - g.elapsed) / 1000)) + " s");
    if (g.done) {
      stopMotion(s);
      s.status.set("");
      if (g.win) buzz(s, VIBRATOR_SCENE_NOTIFICATION);
      finishGame(s, g.win, g.win ? "Wygrana!" : g.bees >= TREE.hardMax ? "Pszczoły przegoniły" : "Za mało owoców");
    }
  },
});
