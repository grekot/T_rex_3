// Powtórz ruch: Groot pokazuje strzałki, a ty powtarzasz je przechyłami zegarka
// (lewo, prawo, od siebie = góra, do siebie = dół). Co rundę sekwencja dłuższa.
// Zegarek jest na ręce: po każdej rundzie gwiazdka (albo pomyłka) i czekanie, aż ręka
// wróci do poziomu i chwilę tak zostanie - dopiero wtedy pokaz kolejnej sekwencji.
import { VIBRATOR_SCENE_DURATION, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { SIMON, newSimon, simonInput, createTiltReader } from "../../../utils/moves";
import { newSeed } from "../../../utils/store";
import { COLOR, label, image } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, petForm, startMotion, stopMotion, buzz, STATUS } from "../../../utils/gamekit";
import { ARROW_POS, ROUND, PET } from "zosLoader:./index.page.[pf].layout.js";

const SHOW_MS = 900; // tyle widać każdą strzałkę
const GAP_MS = 350;
const RESULT_MS = 1200; // gwiazdka / pomyłka co najmniej tyle
const LEVEL = 0.15; // g - przechył uznany za poziom
const LEVEL_MS = 700; // tyle trzeba trzymać poziomo przed pokazem
const LEVEL_MAX_MS = 6000; // potem pokaz i tak rusza
const LEAD_MS = 800; // od "Patrz" do pierwszej strzałki
const ARROWS = { left: "ui/arrow_l.png", right: "ui/arrow_r.png", up: "ui/arrow_u.png", down: "ui/arrow_d.png" };

Page({
  state: {},

  build() {
    const s = this.state;
    s.game = newSimon(newSeed());
    s.reader = createTiltReader();
    s.hint = header("Powtórz ruch", "Trzymaj zegarek poziomo…");
    s.arrow = image(ARROWS.left, ARROW_POS.x, ARROW_POS.y);
    s.arrow.show(false);
    s.round = label({ ...ROUND });
    image("thumb/" + petForm() + ".png", PET.x, PET.y);
    s.status = label({ ...STATUS, color: COLOR.grey });
    s.phase = "calib";
    const ok = startMotion(s, {
      calibrate: true,
      ready: () => this.waitLevel(0, ""),
      tick: (a, now, dt, tilt) => this.tick(tilt),
    });
    if (!ok) s.hint.set("Brak akcelerometru", COLOR.bad);
    this.renderRound();
  },

  onDestroy() {
    if (this.state.timer) clearTimeout(this.state.timer);
    stopMotion(this.state);
  },

  renderRound() {
    const g = this.state.game;
    this.state.round.set("Długość " + g.level + "/" + SIMON.win + " · życia " + g.lives);
  },

  // Pauza po rundzie: wynik na ekranie, potem pokaz, gdy ręka wróci do poziomu
  waitLevel(minMs, icon) {
    const s = this.state;
    s.phase = "wait";
    s.waitFrom = Date.now();
    s.waitMin = minMs;
    s.levelSince = 0;
    if (icon) {
      s.arrow.set(icon);
      s.arrow.show(true);
    } else s.arrow.show(false);
    s.hint.set("Wróć zegarkiem do poziomu", COLOR.grey);
  },

  showSequence() {
    const s = this.state;
    s.phase = "show";
    s.hint.set("Patrz i zapamiętaj", COLOR.grey);
    s.arrow.show(false);
    s.status.set("");
    let i = 0;
    const step = () => {
      if (i >= s.game.level) {
        s.arrow.show(false);
        s.phase = "input";
        s.reader = createTiltReader();
        s.hint.set("Teraz ty: przechylaj!", COLOR.accent);
        return;
      }
      s.arrow.set(ARROWS[s.game.seq[i]]);
      s.arrow.show(true);
      s.timer = setTimeout(() => {
        s.arrow.show(false);
        i++;
        s.timer = setTimeout(step, GAP_MS);
      }, SHOW_MS);
    };
    s.timer = setTimeout(step, LEAD_MS);
  },

  tick(tilt) {
    const s = this.state;
    if (s.phase === "wait") {
      const now = Date.now();
      const level = Math.abs(tilt.x) < LEVEL && Math.abs(tilt.y) < LEVEL;
      if (!level) s.levelSince = 0;
      else if (!s.levelSince) s.levelSince = now;
      const waited = now - s.waitFrom;
      if (waited < s.waitMin) return;
      if ((s.levelSince && now - s.levelSince >= LEVEL_MS) || waited >= LEVEL_MAX_MS) this.showSequence();
      return;
    }
    if (s.phase !== "input") return;
    const dir = s.reader.feed(tilt.x, tilt.y);
    if (!dir) return;
    s.arrow.set(ARROWS[dir]);
    s.arrow.show(true);
    const r = simonInput(s.game, dir);
    s.game = r.game;
    this.renderRound();
    if (r.event === "round") {
      s.status.set("Dobrze! Dłuższa sekwencja", COLOR.good);
      this.waitLevel(RESULT_MS, "ui/star_ok.png");
    } else if (r.event === "wrong") {
      buzz(s, VIBRATOR_SCENE_DURATION);
      s.status.set("Pomyłka - jeszcze raz", COLOR.bad);
      this.waitLevel(RESULT_MS, "");
    } else if (r.event === "win" || r.event === "lose") {
      s.phase = "done";
      s.status.set("");
      stopMotion(s);
      if (r.event === "win") buzz(s, VIBRATOR_SCENE_NOTIFICATION);
      finishGame(s, r.event === "win", r.event === "win" ? "Wygrana!" : "Tym razem nie", "simon");
    }
  },
});
