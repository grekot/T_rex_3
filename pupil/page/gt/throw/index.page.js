// Rzut piłką: machnięcie nadgarstkiem rzuca piłkę, siła = odległość. Dinozaur stoi
// w losowej odległości i łapie piłkę, jeśli spadnie blisko niego. 2 złapane z 3 = wygrana.
import { VIBRATOR_SCENE_SHORT_MIDDLE, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { THROW, createThrowDetector, newThrowGame, throwBall } from "../../../utils/games";
import { load, newSeed } from "../../../utils/store";
import { startAccel, readAccel, stopAccel, keepScreenOn, releaseScreen, createBuzzer } from "../../../utils/device";
import { COLOR, label, image, rect } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { THUMB } from "../../../utils/geometry";
import { TITLE, HINT, ROUND, FIELD, MARKS, LAST, FLIGHT } from "zosLoader:./index.page.[pf].layout.js";

const POLL_MS = 40;
const BALL = 32;

function fieldX(dist) {
  return FIELD.x0 + ((FIELD.x1 - FIELD.x0) * dist) / THROW.maxDist;
}

Page({
  state: {},

  build() {
    const s = this.state;
    keepScreenOn();
    s.buzzer = createBuzzer();
    s.form = load().state.form;
    s.game = newThrowGame(newSeed());
    s.detector = createThrowDetector();

    label({ ...TITLE, text: "Rzut piłką" });
    s.hint = label({ ...HINT, text: "Machnij ręką jak przy rzucie", color: COLOR.grey });
    s.round = label({ ...ROUND });
    rect(FIELD.x0 - 10, FIELD.y, FIELD.x1 - FIELD.x0 + 20, 4, 0x3f7a46, 2);
    [0, 50, 100].forEach((m) =>
      label({ x: fieldX(m) - 40, y: MARKS.y, w: 80, h: MARKS.h, size: MARKS.size, text: m + (m === 100 ? " m" : ""), color: COLOR.grey }),
    );
    s.dino = image("thumb/" + s.form + ".png", fieldX(s.game.targets[0]) - THUMB / 2, FIELD.y - THUMB);
    s.ball = image("ui/ball.png", FLIGHT.startX, FIELD.y - BALL);
    s.last = label({ ...LAST });
    this.renderRound();

    s.accel = startAccel();
    if (!s.accel.sensor) s.hint.set("Brak akcelerometru", COLOR.bad);
    s.poll = setInterval(() => this.poll(), POLL_MS);
  },

  onDestroy() {
    const s = this.state;
    if (s.poll) clearInterval(s.poll);
    if (s.flight) clearInterval(s.flight);
    stopAccel(s.accel);
    s.buzzer.stop();
    releaseScreen();
  },

  renderRound() {
    const g = this.state.game;
    this.state.round.set("Rzut " + Math.min(g.round + 1, THROW.rounds) + "/" + THROW.rounds + " · złapane " + g.caught);
  },

  poll() {
    const s = this.state;
    if (s.flight || s.game.done) return;
    const now = Date.now();
    if (now < (s.waitUntil || 0)) return;
    const dist = s.detector.feed(readAccel(s.accel), now);
    if (dist !== null) this.throwTo(dist);
  },

  throwTo(dist) {
    const s = this.state;
    s.last.set("");
    const x1 = fieldX(dist) - BALL / 2;
    const start = Date.now();
    s.flight = setInterval(() => {
      const f = Math.min(1, (Date.now() - start) / FLIGHT.ms);
      const x = FLIGHT.startX + (x1 - FLIGHT.startX) * f;
      const y = FIELD.y - BALL - FLIGHT.peak * 4 * f * (1 - f);
      s.ball.set("ui/ball.png", Math.round(x), Math.round(y));
      if (f < 1) return;
      clearInterval(s.flight);
      s.flight = null;
      this.landed(dist);
    }, 40);
  },

  landed(dist) {
    const s = this.state;
    s.game = throwBall(s.game, dist);
    const l = s.game.last;
    const how = l.ok ? "złapał!" : dist < l.target ? "za blisko" : "za daleko";
    s.last.set(dist + " m - " + how, l.ok ? COLOR.good : COLOR.accent);
    if (l.ok) s.buzzer.buzz(VIBRATOR_SCENE_SHORT_MIDDLE);
    this.renderRound();
    s.detector.quiet(Date.now());
    s.waitUntil = Date.now() + 1300;
    if (s.game.done) {
      setTimeout(() => {
        s.last.set("");
        s.hint.set("");
        if (s.game.win) s.buzzer.buzz(VIBRATOR_SCENE_NOTIFICATION);
        finishGame(s, s.game.win, s.game.win ? "Wygrana!" : "Tym razem nie", "throw");
      }, 1200);
      return;
    }
    // następna runda: dinozaur przechodzi, piłka wraca
    setTimeout(() => {
      if (!s.ball) return;
      s.ball.set("ui/ball.png", FLIGHT.startX, FIELD.y - BALL);
      s.dino.set("thumb/" + s.form + ".png", fieldX(s.game.targets[s.game.round]) - THUMB / 2, FIELD.y - THUMB);
    }, 1200);
  },
});
