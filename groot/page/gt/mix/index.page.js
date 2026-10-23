// Awesome Mix (dotyk + wibracja): zegarek wystukuje rytm - krótka wibracja i zapalające się
// słoneczka - a ty powtarzasz go stuknięciami w ekran; Groot tańczy do twoich stuknięć.
// Liczą się proporcje odstępów (krótki / długi), nie tempo. 3 rundy (4, 5, 6 uderzeń),
// 2 trafione = wygrana. Ręka się nie rusza, więc wibracja niczego nie psuje.
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { VIBRATOR_SCENE_SHORT_STRONG } from "@zos/sensor";
import { MIX, newMix, mixPattern, beatTimes, mixRound } from "../../../utils/space";
import { newSeed } from "../../../utils/store";
import { COLOR, label, image, rect, onTap, gameSprite } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, petForm } from "../../../utils/gamekit";
import { keepScreenOn, releaseScreen, createBuzzer } from "../../../utils/device";
import { PET, DOTS, DOT, PAD, ROUND } from "zosLoader:./index.page.[pf].layout.js";

const INTRO_MS = 1300;
const RESULT_MS = 1600;

Page({
  state: {},

  build() {
    const s = this.state;
    s.game = newMix(newSeed());
    s.form = petForm();
    s.timers = [];
    s.hint = header("Awesome Mix", "Słuchaj rytmu, potem go wystukaj");
    s.round = label({ ...ROUND, color: COLOR.grey });
    s.pet = image(gameSprite(s.form, "idle0"), PET.x, PET.y);
    s.dots = [];
    for (let i = 0; i < MIX.first + MIX.rounds - 1; i++) {
      const w = image("ui/sunpt_empty.png", 0, DOTS.y);
      w.show(false);
      s.dots.push(w);
    }
    s.padBg = rect(PAD.x, PAD.y, PAD.w, PAD.h, COLOR.pill, PAD.h / 2);
    s.padTxt = label({ ...PAD, text: "", size: 26 });
    onTap([s.padBg, s.padTxt.widget], () => this.tap());
    s.buzzer = createBuzzer();
    keepScreenOn();
    this.nextRound();
  },

  onDestroy() {
    const s = this.state;
    s.timers.forEach((t) => clearTimeout(t));
    s.buzzer.stop();
    releaseScreen();
  },

  later(ms, fn) {
    const s = this.state;
    const t = setTimeout(() => {
      s.timers = s.timers.filter((x) => x !== t);
      fn();
    }, ms);
    s.timers.push(t);
  },

  showDots(n, lit) {
    const s = this.state;
    const x0 = 240 - (n * DOT + (n - 1) * DOTS.gap) / 2;
    s.dots.forEach((w, i) => {
      w.show(i < n);
      if (i < n) w.set(i < lit ? "ui/sunpt.png" : "ui/sunpt_empty.png", Math.round(x0 + i * (DOT + DOTS.gap)), DOTS.y);
    });
  },

  setPad(text, on) {
    const s = this.state;
    s.padTxt.set(text, on ? COLOR.accent : COLOR.grey);
    s.padBg.setProperty(hmUI.prop.MORE, { x: px(PAD.x), y: px(PAD.y), w: px(PAD.w), h: px(PAD.h), radius: px(PAD.h / 2), color: on ? COLOR.pillOn : COLOR.pill });
  },

  nextRound() {
    const s = this.state;
    const g = s.game;
    const p = mixPattern(g);
    const n = p.length + 1;
    s.phase = "intro";
    s.round.set("Runda " + (g.round + 1) + "/" + MIX.rounds + " · trafione " + g.wins);
    s.hint.set("Słuchaj rytmu…", COLOR.grey);
    this.setPad("", false);
    this.showDots(n, 0);
    s.pet.set(gameSprite(s.form, "idle0"));
    this.later(INTRO_MS, () => this.listen());
  },

  // Zegarek gra rytm: wibracja + zapalone słoneczko + krok Groota na każde uderzenie
  listen() {
    const s = this.state;
    const p = s.game.pattern;
    const times = beatTimes(p, MIX.unit);
    s.phase = "listen";
    times.forEach((t, i) =>
      this.later(t, () => {
        s.buzzer.buzz(VIBRATOR_SCENE_SHORT_STRONG);
        this.showDots(times.length, i + 1);
        s.pet.set(gameSprite(s.form, i % 2 ? "idle1" : "happy0"));
      }),
    );
    this.later(times[times.length - 1] + MIX.gapAfter, () => this.play());
  },

  play() {
    const s = this.state;
    s.phase = "play";
    s.taps = [];
    s.hint.set("Teraz ty: stukaj!", COLOR.accent);
    this.setPad("Stukaj tu", true);
    this.showDots(s.game.pattern.length + 1, 0);
    s.pet.set(gameSprite(s.form, "idle0"));
    this.armTimeout();
  },

  // brak kolejnego stuknięcia przez MIX.timeout = koniec próby
  armTimeout() {
    const s = this.state;
    if (s.waitTimer) clearTimeout(s.waitTimer);
    s.waitTimer = setTimeout(() => {
      s.waitTimer = null;
      if (s.phase === "play") this.judge();
    }, MIX.timeout);
    s.timers.push(s.waitTimer);
  },

  tap() {
    const s = this.state;
    if (s.phase !== "play") return;
    s.taps.push(Date.now());
    const n = s.game.pattern.length + 1;
    this.showDots(n, s.taps.length);
    s.pet.set(gameSprite(s.form, s.taps.length % 2 ? "happy1" : "happy0")); // Groot tańczy
    if (s.taps.length >= n) this.judge();
    else this.armTimeout();
  },

  judge() {
    const s = this.state;
    if (s.waitTimer) clearTimeout(s.waitTimer);
    s.waitTimer = null;
    s.phase = "result";
    const t0 = s.taps.length ? s.taps[0] : 0;
    const g = mixRound(s.game, s.taps.map((t) => t - t0));
    const ok = g.last.ok;
    this.setPad("", false);
    s.hint.set(ok ? "Dobrze! Groot tańczy" : g.last.why === "few" ? "Za mało stuknięć" : "To nie ten rytm", ok ? COLOR.good : COLOR.bad);
    s.pet.set(gameSprite(s.form, ok ? "happy1" : "sad0"));
    s.round.set("Runda " + Math.min(g.round + 1, MIX.rounds) + "/" + MIX.rounds + " · trafione " + g.wins);
    this.later(RESULT_MS, () => {
      if (!g.done) {
        this.nextRound();
        return;
      }
      s.dots.forEach((w) => w.show(false));
      s.padBg.setProperty(hmUI.prop.VISIBLE, false);
      s.padTxt.show(false);
      s.pet.set(gameSprite(s.form, g.win ? "happy0" : "sad0"));
      finishGame(s, g.win, g.win ? "Groot tańczy!" : "Tym razem nie", "mix");
    });
  },
});
