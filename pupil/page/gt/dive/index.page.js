// Nurkowanie (barometr, eksperyment): szybko opuść rękę z zegarkiem najniżej jak się da
// i podnieś z powrotem - barometr czuje różnicę wysokości, dinozaur nurkuje po perłę.
// 3 nurkowania w minutę. Na ekranie widać zmianę wysokości, żeby sprawdzić czujnik.
import { VIBRATOR_SCENE_SHORT_LIGHT, VIBRATOR_SCENE_SHORT_MIDDLE, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { DIVE, newDive, feedDive } from "../../../utils/walks";
import { startAltimeter } from "../../../utils/sensors";
import { keepScreenOn, releaseScreen, createBuzzer } from "../../../utils/device";
import { COLOR, label, image, rect } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, petForm } from "../../../utils/gamekit";
import { WATER, PET, DELTA, COUNT, PEARLS } from "zosLoader:./index.page.[pf].layout.js";

const TICK_MS = 100;

Page({
  state: {},

  build() {
    const s = this.state;
    keepScreenOn();
    s.buzzer = createBuzzer();
    s.game = newDive();
    s.hint = header("Nurkowanie", "Opuść szybko rękę i podnieś");
    rect(WATER.x, WATER.y, WATER.w, WATER.h, 0x123a5a, 20);
    s.pearls = PEARLS.map((p) => image("ui/pearl.png", p.x, p.y)); // perły na dnie znikają po wyłowieniu
    s.petSrc = "thumb/" + petForm() + ".png";
    s.pet = image(s.petSrc, PET.x, PET.y);
    s.delta = label({ ...DELTA });
    s.count = label({ ...COUNT, color: COLOR.grey });
    s.alt = startAltimeter();
    s.timer = setInterval(() => this.tick(), TICK_MS);
  },

  onDestroy() {
    const s = this.state;
    if (s.timer) clearInterval(s.timer);
    s.alt.stop();
    s.buzzer.stop();
    releaseScreen();
  },

  tick() {
    const s = this.state;
    const g = s.game;
    const alt = s.alt.read();
    const ev = feedDive(g, alt, Date.now(), TICK_MS);
    if (alt === null) s.hint.set("Brak odczytu barometru", COLOR.bad);
    if (ev === "down") s.buzzer.buzz(VIBRATOR_SCENE_SHORT_LIGHT);
    if (ev === "dive") s.buzzer.buzz(VIBRATOR_SCENE_SHORT_MIDDLE);
    s.pet.set(s.petSrc, PET.x, g.low ? PET.y + 96 : PET.y);
    s.delta.set((g.delta >= 0 ? "+" : "") + g.delta.toFixed(2) + " m", g.low ? COLOR.good : COLOR.text);
    s.pearls.forEach((w, i) => w.show(i >= g.dives));
    s.count.set("Perły " + g.dives + "/" + DIVE.need + " · " + Math.max(0, Math.ceil((DIVE.time - g.elapsed) / 1000)) + " s");
    if (g.done) {
      clearInterval(s.timer);
      s.timer = null;
      s.delta.set("");
      s.count.set("");
      if (g.win) s.buzzer.buzz(VIBRATOR_SCENE_NOTIFICATION);
      finishGame(s, g.win, g.win ? "Trzy perły!" : "Barometr nie poczuł", "dive");
    }
  },
});
