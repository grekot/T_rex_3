// Pompowanie balonu: ruchy ręką jak pompką pompują balon; puść go (przycisk "Puść"
// albo przycisk wyboru), gdy rozmiar jest w zielonym przedziale. Za dużo - pęka.
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { onKey, offKey, KEY_SELECT, KEY_EVENT_CLICK } from "@zos/interaction";
import { VIBRATOR_SCENE_SHORT_LIGHT, VIBRATOR_SCENE_DURATION, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { newBalloon, pump, releaseBalloon } from "../../../utils/moves";
import { newSeed } from "../../../utils/store";
import { COLOR, label, rect, button } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, startMotion, stopMotion, buzz } from "../../../utils/gamekit";
import { BALLOON_C, METER, TARGET, RELEASE_BTN } from "zosLoader:./index.page.[pf].layout.js";

const BALLOON_COLOR = 0xe8484a;

Page({
  state: {},

  build() {
    const s = this.state;
    s.game = newBalloon(newSeed());
    const g = s.game;
    s.hint = header("Balon", "Pompuj ruchem ręki w górę i w dół");
    s.balloon = rect(BALLOON_C.x - BALLOON_C.rMin, BALLOON_C.y - BALLOON_C.rMin, BALLOON_C.rMin * 2, BALLOON_C.rMin * 2, BALLOON_COLOR, BALLOON_C.rMin);
    rect(METER.x, METER.y, METER.w, METER.h, 0x26262e, 6);
    rect(METER.x, METER.y + (METER.h * (100 - g.hi)) / 100, METER.w, (METER.h * (g.hi - g.lo)) / 100, 0x3f9a56, 4);
    s.marker = rect(METER.x - 6, METER.y + METER.h - 3, METER.w + 12, 6, 0xffffff, 3);
    s.target = label({ ...TARGET, text: "Cel: " + g.lo + "-" + g.hi + "%", color: COLOR.grey });
    s.btn = button(RELEASE_BTN, () => this.release());
    try {
      onKey({
        callback: (key, event) => {
          if (key !== KEY_SELECT) return false;
          if (event === KEY_EVENT_CLICK) this.release();
          return true;
        },
      });
      s.keyHooked = true;
    } catch (e) {}
    const ok = startMotion(s, { tick: (a, now) => this.tick(a, now) });
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

  tick(a, now) {
    const s = this.state;
    const g = s.game;
    if (g.done) return;
    if (g.reps.feed(a, now)) {
      pump(g, now);
      buzz(s, VIBRATOR_SCENE_SHORT_LIGHT);
      this.render();
      if (g.popped) this.end();
    }
  },

  render() {
    const s = this.state;
    const g = s.game;
    const r = Math.round(BALLOON_C.rMin + ((BALLOON_C.rMax - BALLOON_C.rMin) * g.size) / 100);
    s.balloon.setProperty(hmUI.prop.MORE, {
      x: px(BALLOON_C.x - r),
      y: px(BALLOON_C.y - r),
      w: px(r * 2),
      h: px(r * 2),
      radius: px(r),
      color: g.popped ? 0x555555 : BALLOON_COLOR,
    });
    s.marker.setProperty(hmUI.prop.MORE, {
      x: px(METER.x - 6),
      y: px(Math.round(METER.y + (METER.h * (100 - g.size)) / 100 - 3)),
      w: px(METER.w + 12),
      h: px(6),
      radius: px(3),
      color: 0xffffff,
    });
    s.target.set("Cel: " + g.lo + "-" + g.hi + "% · teraz " + Math.round(g.size) + "%");
  },

  release() {
    const s = this.state;
    if (s.game.done) return;
    releaseBalloon(s.game);
    this.end();
  },

  end() {
    const s = this.state;
    const g = s.game;
    stopMotion(s);
    s.btn.bg.setProperty(hmUI.prop.VISIBLE, false);
    s.btn.txt.widget.setProperty(hmUI.prop.VISIBLE, false);
    s.target.set("");
    buzz(s, g.win ? VIBRATOR_SCENE_NOTIFICATION : VIBRATOR_SCENE_DURATION);
    finishGame(s, g.win, g.win ? "Wygrana!" : g.popped ? "Pękł!" : "Za mały");
  },
});
