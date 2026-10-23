// Wykopywanie kości: rytmiczne ruchy ręką w górę i w dół jak łopatą. Co 5 "kopnięć"
// znika warstwa ziemi, po 15 Groot znajduje skamielinę.
import * as hmUI from "@zos/ui";
import { VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { DIG, newDig, feedDig } from "../../../utils/moves";
import { COLOR, label, image, rect } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, petForm, startMotion, stopMotion, buzz, STATUS } from "../../../utils/gamekit";
import { LAYERS, BONE, PET } from "zosLoader:./index.page.[pf].layout.js";

Page({
  state: {},

  build() {
    const s = this.state;
    s.game = newDig();
    s.hint = header("Wykopywanie żołędzi", "Kop: ręka w górę i w dół");
    image("ui/bone_big.png", BONE.x, BONE.y);
    s.layers = LAYERS.map((l) => rect(l.x, l.y, l.w, l.h, l.color, 6));
    s.gone = 0;
    image("thumb/" + petForm() + ".png", PET.x, PET.y);
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
    feedDig(g, a, now, dt); // bez wibracji przy kopnięciu (drgania liczyłyby się jako ruch)
    const gone = Math.floor((g.digs * DIG.layers) / DIG.need);
    if (gone !== s.gone) {
      s.gone = gone;
      s.layers.forEach((w, i) => w.setProperty(hmUI.prop.VISIBLE, i >= gone));
    }
    s.status.set("Kopnięcia " + g.digs + "/" + DIG.need + " · " + Math.max(0, Math.ceil((DIG.time - g.elapsed) / 1000)) + " s");
    if (g.done) {
      stopMotion(s);
      s.status.set("");
      if (g.win) buzz(s, VIBRATOR_SCENE_NOTIFICATION);
      finishGame(s, g.win, g.win ? "Skamielina!" : "Nic nie znalazł", "dig");
    }
  },
});
