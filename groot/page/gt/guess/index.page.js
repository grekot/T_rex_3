// Lewo czy prawo? - wersja bez ruchu. Zgadnij, w którą stronę spojrzy Groot:
// stuknij strzałkę albo przycisk (góra = lewo, dół = prawo). 3 trafienia z 5 = wygrana.
import * as hmUI from "@zos/ui";
import { onKey, offKey, KEY_UP, KEY_DOWN, KEY_EVENT_CLICK } from "@zos/interaction";
import { GUESS, newGuess, guess } from "../../../utils/games";
import { load, newSeed } from "../../../utils/store";
import { COLOR, label, image, rect, onTap, spriteSrc } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { TITLE, ROUND, PET, FEEDBACK, LEFT_BTN, RIGHT_BTN, ARROW_SIZE } from "zosLoader:./index.page.[pf].layout.js";

const SHOW_MS = 1100;

Page({
  state: {},

  build() {
    const s = this.state;
    s.form = load().state.form;
    s.game = newGuess(newSeed());
    s.busy = false;

    label({ ...TITLE, text: "Lewo czy prawo?" });
    s.round = label({ ...ROUND });
    s.pet = image(spriteSrc(s.form, "idle0"), PET.x, PET.y);
    s.feedback = label({ ...FEEDBACK, text: "Gdzie spojrzy?", color: COLOR.grey });
    s.buttons = [
      [LEFT_BTN, "ui/arrow_l.png", "left"],
      [RIGHT_BTN, "ui/arrow_r.png", "right"],
    ].map(([b, src, side]) => {
      const bg = rect(b.x, b.y, b.w, b.h, COLOR.pill, b.h / 2);
      const arrow = image(src, b.x + (b.w - ARROW_SIZE) / 2, b.y + (b.h - ARROW_SIZE) / 2);
      onTap([bg, arrow.widget], () => this.pick(side));
      return { bg, arrow };
    });
    this.renderRound();

    try {
      onKey({
        callback: (key, event) => {
          if (key !== KEY_UP && key !== KEY_DOWN) return false;
          if (event === KEY_EVENT_CLICK) this.pick(key === KEY_UP ? "left" : "right");
          return true;
        },
      });
      s.keyHooked = true;
    } catch (e) {}
  },

  onDestroy() {
    const s = this.state;
    if (s.timer) clearTimeout(s.timer);
    if (s.keyHooked) {
      try {
        offKey();
      } catch (e) {}
    }
  },

  renderRound() {
    const g = this.state.game;
    this.state.round.set("Runda " + Math.min(g.round + 1, GUESS.rounds) + "/" + GUESS.rounds + " · trafione " + g.hits);
  },

  pick(side) {
    const s = this.state;
    if (s.busy || s.game.done) return;
    s.busy = true;
    s.game = guess(s.game, side);
    const l = s.game.last;
    // sprite domyślnie patrzy w prawo, "left" to odbicie
    s.pet.set(spriteSrc(s.form, l.ok ? (l.dir === "left" ? "left" : "happy0") : l.dir === "left" ? "left" : "idle0"));
    s.feedback.set(l.ok ? "Trafione!" : "Pudło - patrzy w " + (l.dir === "left" ? "lewo" : "prawo"), l.ok ? COLOR.good : COLOR.accent);
    this.renderRound();
    s.timer = setTimeout(() => {
      s.timer = null;
      if (s.game.done) {
        s.buttons.forEach((b) => {
          b.bg.setProperty(hmUI.prop.VISIBLE, false);
          b.arrow.show(false);
        });
        s.feedback.set("");
        s.pet.set(spriteSrc(s.form, s.game.win ? "happy0" : "sad0"));
        finishGame(s, s.game.win, s.game.win ? "Wygrana!" : "Tym razem nie", "guess");
        return;
      }
      s.busy = false;
      s.pet.set(spriteSrc(s.form, "idle0"));
      s.feedback.set("Gdzie spojrzy?", COLOR.grey);
    }, SHOW_MS);
  },
});
