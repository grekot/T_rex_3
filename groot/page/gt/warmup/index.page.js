// Rozgrzewka poranna: trzy krótkie ćwiczenia razem z Grootem - krążenia ramion,
// wymachy rąk i skłony do ziemi. Akcelerometr liczy powtórzenia.
import { VIBRATOR_SCENE_SHORT_MIDDLE, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { WARMUP, newWarmup, feedWarmup } from "../../../utils/moves";
import { COLOR, label, image, spriteSrc } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, petForm, startMotion, stopMotion, buzz } from "../../../utils/gamekit";
import { PET, STEP, COUNT } from "zosLoader:./index.page.[pf].layout.js";

Page({
  state: {},

  build() {
    const s = this.state;
    s.game = newWarmup();
    s.form = petForm();
    s.hint = header("Rozgrzewka", "Ćwicz razem z Grootem");
    s.pet = image(spriteSrc(s.form, "idle0"), PET.x, PET.y);
    s.step = label({ ...STEP, color: COLOR.accent });
    s.count = label({ ...COUNT });
    s.cheer = 0;
    this.render(Date.now());
    const ok = startMotion(s, { tick: (a, now, dt) => this.tick(a, now, dt) });
    if (!ok) s.hint.set("Brak akcelerometru", COLOR.bad);
  },

  onDestroy() {
    stopMotion(this.state);
  },

  tick(a, now, dt) {
    const s = this.state;
    const g = s.game;
    const ev = feedWarmup(g, a, now, dt);
    if (ev === "rep") {
      s.cheer = now + 500; // bez wibracji przy powtórzeniu
    } else if (ev === "next" && !g.done) {
      buzz(s, VIBRATOR_SCENE_SHORT_MIDDLE);
      s.cheer = now + 1200;
    }
    this.render(now);
    if (g.done) {
      stopMotion(s);
      s.step.set("");
      s.count.set("");
      if (g.win) buzz(s, VIBRATOR_SCENE_NOTIFICATION);
      finishGame(s, g.win, g.win ? "Rozgrzany!" : "Może jutro", "warmup");
    }
  },

  render(now) {
    const s = this.state;
    const g = s.game;
    if (g.done) return;
    const st = WARMUP.steps[g.step];
    s.step.set(g.step + 1 + ". " + st.name);
    s.count.set(g.count + "/" + st.reps + " · " + Math.max(0, Math.ceil((WARMUP.limit - g.elapsed) / 1000)) + " s");
    const slow = Math.floor(now / 500) % 2;
    s.pet.set(spriteSrc(s.form, now < s.cheer ? "happy" + slow : "idle" + slow));
  },
});
