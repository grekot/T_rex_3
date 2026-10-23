// Szukanie jedzenia (kompas): jedzenie leży w nieznanym kierunku. Obracaj się z zegarkiem
// (godzina 12 przed siebie): napis i coraz szybsze wibracje mówią "ciepło - gorąco".
// Utrzymaj kierunek chwilę, a Groot znajdzie jedzenie. 3 razy w 90 s.
import { VIBRATOR_SCENE_SHORT_LIGHT, VIBRATOR_SCENE_NOTIFICATION, VIBRATOR_SCENE_SHORT_MIDDLE } from "@zos/sensor";
import { FORAGE, newForage, forageStep, pulseEvery } from "../../../utils/walks";
import { newSeed } from "../../../utils/store";
import { startCompass } from "../../../utils/sensors";
import { keepScreenOn, releaseScreen, createBuzzer } from "../../../utils/device";
import { COLOR, label, image } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, petForm } from "../../../utils/gamekit";
import { PET, TEMP, FOUND, FOOD } from "zosLoader:./index.page.[pf].layout.js";

const TICK_MS = 100;

function warmth(diff) {
  if (diff === null) return ["?", COLOR.grey];
  const d = Math.abs(diff);
  if (d <= FORAGE.tol) return ["Gorąco!", 0xff5a3c];
  if (d <= 45) return ["Ciepło", 0xffaa28];
  if (d <= 100) return ["Chłodno", 0x9ab8e8];
  return ["Zimno", 0x5a8ae8];
}

Page({
  state: {},

  build() {
    const s = this.state;
    keepScreenOn();
    s.buzzer = createBuzzer();
    s.game = newForage(newSeed());
    s.hint = header("Łapanie sygnału", "Obracaj się z zegarkiem przed sobą");
    image("thumb/" + petForm() + ".png", PET.x, PET.y);
    s.temp = label({ ...TEMP });
    s.found = label({ ...FOUND, color: COLOR.grey });
    s.foods = [];
    for (let i = 0; i < FORAGE.foods; i++) {
      const w = image("ui/beacon.png", FOOD.x + i * FOOD.step, FOOD.y);
      w.show(false);
      s.foods.push(w);
    }
    s.compass = startCompass();
    s.nextPulse = 0;
    s.timer = setInterval(() => this.tick(), TICK_MS);
  },

  onDestroy() {
    const s = this.state;
    if (s.timer) clearInterval(s.timer);
    s.compass.stop();
    s.buzzer.stop();
    releaseScreen();
  },

  tick() {
    const s = this.state;
    const g = s.game;
    const now = Date.now();
    const heading = s.compass.read();
    const ev = forageStep(g, heading, TICK_MS);
    if (heading === null) s.hint.set("Skalibruj kompas: zakreśl ręką ósemkę", COLOR.accent);
    else s.hint.set("Obracaj się z zegarkiem przed sobą", COLOR.grey);
    const [txt, color] = warmth(g.diff);
    s.temp.set(txt, color);
    s.found.set("Sygnały " + g.found + "/" + FORAGE.foods + " · " + Math.max(0, Math.ceil((FORAGE.time - g.elapsed) / 1000)) + " s");
    s.foods.forEach((w, i) => w.show(i < g.found));
    if (ev === "found") s.buzzer.buzz(VIBRATOR_SCENE_SHORT_MIDDLE);
    else {
      const every = pulseEvery(g.diff);
      if (every && now >= s.nextPulse) {
        s.buzzer.buzz(VIBRATOR_SCENE_SHORT_LIGHT);
        s.nextPulse = now + every;
      }
    }
    if (g.done) {
      clearInterval(s.timer);
      s.timer = null;
      s.temp.set("");
      s.found.set("");
      if (g.win) s.buzzer.buzz(VIBRATOR_SCENE_NOTIFICATION);
      finishGame(s, g.win, g.win ? "Sygnał złapany!" : "Brak sygnału", "forage");
    }
  },
});
