// Nurkowanie (akcelerometr): opuść rękę luźno wzdłuż ciała - dinozaur nurkuje. Gdy zegarek
// drgnie, ma perłę: podnieś rękę ekranem do góry, żeby się wynurzył. 3 perły w minutę.
// (Wcześniej barometr - ale nie czuł opuszczenia ręki na T-Rex 3.)
import { VIBRATOR_SCENE_SHORT_MIDDLE, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { DIVE, newDive, feedDive } from "../../../utils/moves";
import { COLOR, label, image, rect } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, petForm, startMotion, stopMotion, buzz } from "../../../utils/gamekit";
import { WATER, PET, DELTA, COUNT, PEARLS } from "zosLoader:./index.page.[pf].layout.js";

Page({
  state: {},

  build() {
    const s = this.state;
    s.game = newDive();
    s.hint = header("Nurkowanie", "Opuść rękę w dół, potem podnieś");
    rect(WATER.x, WATER.y, WATER.w, WATER.h, 0x123a5a, 20);
    s.pearls = PEARLS.map((p) => image("ui/pearl.png", p.x, p.y)); // perły na dnie znikają po wyłowieniu
    s.petSrc = "thumb/" + petForm() + ".png";
    s.pet = image(s.petSrc, PET.x, PET.y);
    s.status = label({ ...DELTA, text: "Ręka w dół = nurkuj" });
    s.count = label({ ...COUNT, color: COLOR.grey });
    const ok = startMotion(s, { tick: (a, now, dt) => this.tick(a, now, dt) });
    if (!ok) s.hint.set("Brak akcelerometru", COLOR.bad);
  },

  onDestroy() {
    stopMotion(this.state);
  },

  tick(a, now, dt) {
    const s = this.state;
    const g = s.game;
    if (g.done) return;
    const ev = feedDive(g, a, now, dt);
    if (ev === "pearl") buzz(s, VIBRATOR_SCENE_SHORT_MIDDLE); // ręka w dół, ekranu nie widać - czuć
    s.pet.set(s.petSrc, PET.x, g.under ? PET.y + 96 : PET.y);
    s.pearls.forEach((w, i) => w.show(i >= g.dives));
    if (g.under) s.status.set(g.got ? "Perła! Do góry!" : "Szuka perły…", g.got ? COLOR.good : COLOR.text);
    else if (ev === "empty") s.status.set("Za krótko pod wodą", COLOR.bad);
    else if (ev === "dive") s.status.set("Mamy perłę!", COLOR.good);
    s.count.set("Perły " + g.dives + "/" + DIVE.need + " · " + Math.max(0, Math.ceil((DIVE.time - g.elapsed) / 1000)) + " s");
    if (g.done) {
      stopMotion(s);
      s.status.set("");
      s.count.set("");
      if (g.win) buzz(s, VIBRATOR_SCENE_NOTIFICATION);
      finishGame(s, g.win, g.win ? "Trzy perły!" : "Koniec czasu", "dive");
    }
  },
});
