// Balans: Groot stoi na kłodzie i sam ucieka od środka, do tego wieje wiatr.
// Przechylaj zegarek w bok, żeby go utrzymać przez 15 s. Na początku krótka kalibracja.
import { VIBRATOR_SCENE_DURATION, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { BALANCE, newBalance, stepBalance, calibrate, sideTilt } from "../../../utils/games";
import { load, newSeed } from "../../../utils/store";
import { startAccel, readAccel, stopAccel, keepScreenOn, releaseScreen, createBuzzer } from "../../../utils/device";
import { COLOR, label, image, gameSprite } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { TITLE, HINT, LOG_POS, PET, TIME } from "zosLoader:./index.page.[pf].layout.js";

const POLL_MS = 40;
const CALIB_MS = 600;

Page({
  state: {},

  build() {
    const s = this.state;
    keepScreenOn();
    s.buzzer = createBuzzer();
    s.form = load().state.form;
    s.ball = newBalance(newSeed());
    s.samples = [];
    s.t0 = Date.now();
    s.last = s.t0;

    label({ ...TITLE, text: "Balans na belce" });
    s.hint = label({ ...HINT, text: "Trzymaj zegarek poziomo…", color: COLOR.grey });
    image("ui/log.png", LOG_POS.x, LOG_POS.y);
    s.pet = image(gameSprite(s.form, "idle0"), PET.x, PET.y);
    s.time = label({ ...TIME });

    s.accel = startAccel();
    if (!s.accel.sensor) s.hint.set("Brak akcelerometru", COLOR.bad);
    s.poll = setInterval(() => this.poll(), POLL_MS);
  },

  onDestroy() {
    const s = this.state;
    if (s.poll) clearInterval(s.poll);
    stopAccel(s.accel);
    s.buzzer.stop();
    releaseScreen();
  },

  poll() {
    const s = this.state;
    const now = Date.now();
    const a = readAccel(s.accel);
    if (!s.zero) {
      s.samples.push(a);
      if (now - s.t0 < CALIB_MS) return;
      s.zero = calibrate(s.samples);
      s.hint.set("Przechylaj, żeby nie spadł", COLOR.grey);
      s.last = now;
      return;
    }
    const b = stepBalance(s.ball, sideTilt(a, s.zero), now - s.last);
    s.last = now;
    const slow = Math.floor((now - s.t0) / 600) % 2;
    const scared = Math.abs(b.pos) > 0.6;
    const left = b.pos < -0.15;
    let frame = scared ? "sad" + slow : left ? "left" : "idle" + slow;
    s.pet.set(gameSprite(s.form, frame), Math.round(PET.x + b.pos * PET.range), PET.y);
    s.time.set(Math.max(0, Math.ceil((BALANCE.time - b.elapsed) / 1000)) + " s", scared ? COLOR.accent : COLOR.text);

    if (b.done) {
      clearInterval(s.poll);
      s.poll = null;
      s.time.set("");
      if (b.win) {
        s.pet.set(gameSprite(s.form, "happy0"), Math.round(PET.x + b.pos * PET.range), PET.y);
        s.hint.set("Utrzymał się!", COLOR.good);
        s.buzzer.buzz(VIBRATOR_SCENE_NOTIFICATION);
      } else {
        s.pet.set(gameSprite(s.form, "sad0"), Math.round(PET.x + b.pos * PET.range * 1.3), PET.y + 40);
        s.hint.set("Spadł z belki", COLOR.bad);
        s.buzzer.buzz(VIBRATOR_SCENE_DURATION);
      }
      finishGame(s, b.win, b.win ? "Wygrana!" : "Tym razem nie", "balance");
    }
  },
});
