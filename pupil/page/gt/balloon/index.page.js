// Pompowanie balonu: ruchy ręką jak pompką pompują balon; puść go (przycisk "Puść"
// albo przycisk wyboru), gdy rozmiar jest w zielonym przedziale. Za dużo - pęka.
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { onKey, offKey, KEY_SELECT, KEY_EVENT_CLICK } from "@zos/interaction";
import { VIBRATOR_SCENE_DURATION, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { newBalloon, pump, releaseBalloon } from "../../../utils/moves";
import { newSeed } from "../../../utils/store";
import { COLOR, label, rect, image, button } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, startMotion, stopMotion, buzz } from "../../../utils/gamekit";
import { BALLOON_C, METER, TARGET, RELEASE_BTN } from "zosLoader:./index.page.[pf].layout.js";

// balon z Gemini w 11 rozmiarach (ui/balloon0..10.png, średnica 28-176 px)
const BALLOON_STEPS = 10;
const balloonPx = (i) => 28 + Math.round((148 * i) / BALLOON_STEPS);

Page({
  state: {},

  build() {
    const s = this.state;
    s.game = newBalloon(newSeed());
    const g = s.game;
    s.hint = header("Balon", "Pompuj ruchem ręki w górę i w dół");
    s.balloon = image("ui/balloon0.png", BALLOON_C.x - balloonPx(0) / 2, BALLOON_C.y - balloonPx(0) / 2);
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
      pump(g, now); // bez wibracji: drgania same "pompowałyby" dalej
      this.render();
      if (g.popped) this.end();
    }
  },

  render() {
    const s = this.state;
    const g = s.game;
    const i = Math.max(0, Math.min(BALLOON_STEPS, Math.round((g.size * BALLOON_STEPS) / 100)));
    const d = balloonPx(i);
    s.balloon.set("ui/balloon" + i + ".png", BALLOON_C.x - d / 2, BALLOON_C.y - d / 2);
    s.balloon.show(!g.popped);
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
    finishGame(s, g.win, g.win ? "Wygrana!" : g.popped ? "Pękł!" : "Za mały", "balloon");
  },
});
