// Medytacja: trzymaj rękę zupełnie nieruchomo, aż pasek spokoju się zapełni (20 s).
// Każdy ruch cofa pasek. Odwrotność kołysania - dobre na uspokojenie.
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { CALM, newCalm, feedCalm } from "../../../utils/moves";
import { COLOR, label, image, rect, spriteSrc } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, petForm, startMotion, stopMotion, buzz, STATUS } from "../../../utils/gamekit";
import { PET, BAR } from "zosLoader:./index.page.[pf].layout.js";

const BAR_COLOR = 0x7ec8a0;

Page({
  state: {},

  build() {
    const s = this.state;
    s.game = newCalm();
    s.form = petForm();
    s.hint = header("Medytacja", "Trzymaj rękę zupełnie nieruchomo");
    s.pet = image(spriteSrc(s.form, "idle0"), PET.x, PET.y);
    rect(BAR.x, BAR.y, BAR.w, BAR.h, 0x26262e, BAR.h / 2);
    s.bar = rect(BAR.x, BAR.y, BAR.h, BAR.h, BAR_COLOR, BAR.h / 2);
    s.barW = 0;
    s.status = label({ ...STATUS });
    s.t0 = Date.now();
    const ok = startMotion(s, { tick: (a, now, dt) => this.tick(a, now, dt) });
    if (!ok) s.hint.set("Brak akcelerometru", COLOR.bad);
  },

  onDestroy() {
    stopMotion(this.state);
  },

  tick(a, now, dt) {
    const s = this.state;
    const g = s.game;
    feedCalm(g, a, now, dt);
    const calm = g.energy <= CALM.max;
    const slow = Math.floor((now - s.t0) / 900) % 2;
    s.pet.set(spriteSrc(s.form, calm ? "sleep" + slow : "sad" + slow));
    const w = Math.max(BAR.h, Math.round((BAR.w * g.progress) / CALM.need));
    if (w !== s.barW) {
      s.barW = w;
      s.bar.setProperty(hmUI.prop.MORE, { x: px(BAR.x), y: px(BAR.y), w: px(w), h: px(BAR.h), radius: px(BAR.h / 2), color: BAR_COLOR });
    }
    s.status.set(calm ? "Spokojnie… " + Math.ceil((CALM.need - g.progress) / 1000) + " s" : "Ręka się rusza", calm ? COLOR.good : COLOR.accent);
    if (g.done) {
      stopMotion(s);
      s.status.set("");
      if (g.win) buzz(s, VIBRATOR_SCENE_NOTIFICATION);
      finishGame(s, g.win, g.win ? "Pełen spokój" : "Za dużo ruchu");
    }
  },
});
