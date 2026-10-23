// Celowanie: przechylaj zegarek, żeby najechać celownikiem na jabłko, i stuknij ekran
// (albo przycisk wyboru), żeby rzucić. Ręka musi być spokojna. 3 trafienia z 5.
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { onKey, offKey, KEY_SELECT, KEY_EVENT_CLICK } from "@zos/interaction";
import { VIBRATOR_SCENE_SHORT_MIDDLE, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { AIM, newAim, aimStep, shoot } from "../../../utils/moves";
import { newSeed } from "../../../utils/store";
import { COLOR, label, image, rect, onTap } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, startMotion, stopMotion, buzz, STATUS } from "../../../utils/gamekit";
import { ITEM } from "../../../utils/geometry";
import { CENTER, ARENA } from "zosLoader:./index.page.[pf].layout.js";

const CROSS = { len: 34, thick: 4, color: 0xffd25a };

Page({
  state: {},

  build() {
    const s = this.state;
    s.game = newAim(newSeed());
    const tapZone = rect(0, 0, 480, 480, 0x000000);
    onTap([tapZone], () => this.fire());
    s.hint = header("Strzała Yondu", "Trzymaj zegarek poziomo…");
    s.arena = rect(CENTER.x - ARENA, CENTER.y - ARENA * 0.75, ARENA * 2, ARENA * 1.5, 0x15201a, 24);
    onTap([s.arena], () => this.fire());
    s.target = image("ui/orb.png", CENTER.x - ITEM / 2, CENTER.y - ITEM / 2);
    s.h = rect(0, 0, CROSS.len, CROSS.thick, CROSS.color, 2);
    s.v = rect(0, 0, CROSS.thick, CROSS.len, CROSS.color, 2);
    [s.h, s.v].forEach((w) => onTap([w], () => this.fire()));
    s.status = label({ ...STATUS });
    try {
      onKey({
        callback: (key, event) => {
          if (key !== KEY_SELECT) return false;
          if (event === KEY_EVENT_CLICK) this.fire();
          return true;
        },
      });
      s.keyHooked = true;
    } catch (e) {}
    this.render();
    const ok = startMotion(s, {
      calibrate: true,
      ready: () => s.hint.set("Celuj przechyłem, stuknij = gwizd", COLOR.grey),
      tick: (a, now, dt, tilt) => {
        aimStep(s.game, tilt.x, tilt.y);
        this.render();
      },
    });
    if (!ok) s.hint.set("Brak akcelerometru", COLOR.bad);
  },

  onDestroy() {
    const s = this.state;
    stopMotion(s);
    if (s.keyHooked) {
      try {
        offKey();
      } catch (e) {}
    }
  },

  render() {
    const s = this.state;
    const g = s.game;
    const cx = Math.round(CENTER.x + Math.max(-ARENA, Math.min(ARENA, g.x)));
    const cy = Math.round(CENTER.y + Math.max(-ARENA * 0.75, Math.min(ARENA * 0.75, g.y)));
    s.h.setProperty(hmUI.prop.MORE, { x: px(cx - CROSS.len / 2), y: px(cy - CROSS.thick / 2), w: px(CROSS.len), h: px(CROSS.thick), radius: px(2), color: CROSS.color });
    s.v.setProperty(hmUI.prop.MORE, { x: px(cx - CROSS.thick / 2), y: px(cy - CROSS.len / 2), w: px(CROSS.thick), h: px(CROSS.len), radius: px(2), color: CROSS.color });
    s.target.set("ui/orb.png", Math.round(CENTER.x + g.tx - ITEM / 2), Math.round(CENTER.y + g.ty - ITEM / 2));
    s.status.set("Trafienia " + g.hits + "/" + AIM.need + " · strzały " + g.shots + "/" + AIM.shots);
  },

  fire() {
    const s = this.state;
    const g = s.game;
    if (g.done || !s.zero) return;
    const hit = shoot(g);
    buzz(s, VIBRATOR_SCENE_SHORT_MIDDLE);
    s.hint.set(hit ? "Trafione!" : "Pudło", hit ? COLOR.good : COLOR.accent);
    this.render();
    if (g.done) {
      stopMotion(s);
      s.status.set("");
      [s.arena, s.h, s.v].forEach((w) => w.setProperty(hmUI.prop.VISIBLE, false));
      s.target.show(false);
      if (g.win) buzz(s, VIBRATOR_SCENE_NOTIFICATION);
      finishGame(s, g.win, g.win ? "Jak Yondu!" : "Tym razem nie", "aim");
    }
  },
});
