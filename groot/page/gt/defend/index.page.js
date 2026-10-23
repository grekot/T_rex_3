// Obrona Milano (dotyk): statki Ravagerów lecą z brzegów tarczy do Milano na środku -
// stuknij je, zanim dolecą. 12 zestrzelonych = wygrana, 3 trafienia w Milano = przegrana.
// Bez ruchu ręką: zegarek cały czas patrzy na ciebie.
import { VIBRATOR_SCENE_DURATION } from "@zos/sensor";
import { DEFEND, newDefend, defendStep, defendTap, shipPos } from "../../../utils/space";
import { newSeed } from "../../../utils/store";
import { COLOR, label, image, onTap } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { header, STATUS } from "../../../utils/gamekit";
import { keepScreenOn, releaseScreen, createBuzzer } from "../../../utils/device";
import { MILANO, SHIP, TICK_MS } from "zosLoader:./index.page.[pf].layout.js";

Page({
  state: {},

  build() {
    const s = this.state;
    s.game = newDefend(newSeed());
    image("ui/bg_kokpit_n.png", 0, 0);
    s.hint = header("Obrona Milano", "Stukaj statki Ravagerów");
    s.milano = image("ui/milano_big.png", DEFEND.cx - MILANO / 2, DEFEND.cy - MILANO / 2);
    // pula widżetów statków: widżet i pokazany w nim statek (id)
    s.pool = [];
    for (let i = 0; i < DEFEND.max; i++) {
      const w = image("ui/ravager.png", -SHIP, -SHIP);
      w.show(false);
      const slot = { w, id: 0 };
      onTap([w.widget], () => this.shoot(slot));
      s.pool.push(slot);
    }
    s.status = label({ ...STATUS });
    s.buzzer = createBuzzer();
    keepScreenOn();
    s.last = Date.now();
    s.timer = setInterval(() => this.tick(), TICK_MS);
    this.render();
  },

  onDestroy() {
    const s = this.state;
    if (s.timer) clearInterval(s.timer);
    s.buzzer.stop();
    releaseScreen();
  },

  shoot(slot) {
    const s = this.state;
    if (!slot.id || s.game.done) return;
    if (defendTap(s.game, 0, 0, slot.id)) {
      slot.id = 0;
      slot.w.show(false);
      this.render();
      if (s.game.done) this.end();
    }
  },

  tick() {
    const s = this.state;
    const now = Date.now();
    const dt = Math.min(200, now - s.last);
    s.last = now;
    const ev = defendStep(s.game, dt);
    // wibracja tylko przy trafieniu w Milano - gra nie czyta ruchu, więc drgania nie szkodzą
    if (ev.indexOf("hit") >= 0) s.buzzer.buzz(VIBRATOR_SCENE_DURATION);
    this.render();
    if (s.game.done) this.end();
  },

  render() {
    const s = this.state;
    const g = s.game;
    const ids = g.ships.map((sh) => sh.id);
    s.pool.forEach((slot) => {
      if (slot.id && ids.indexOf(slot.id) < 0) {
        slot.id = 0;
        slot.w.show(false);
      }
    });
    g.ships.forEach((sh) => {
      let slot = s.pool.find((x) => x.id === sh.id);
      if (!slot) slot = s.pool.find((x) => !x.id);
      if (!slot) return;
      slot.id = sh.id;
      const p = shipPos(sh);
      slot.w.set("ui/ravager.png", Math.round(p.x - SHIP / 2), Math.round(p.y - SHIP / 2));
      slot.w.show(true);
    });
    const left = Math.max(0, Math.ceil((DEFEND.time - g.elapsed) / 1000));
    s.status.set("Zestrzelone " + g.killed + "/" + DEFEND.need + " · Milano " + g.lives + " · " + left + " s");
  },

  end() {
    const s = this.state;
    if (s.timer) clearInterval(s.timer);
    s.timer = null;
    s.pool.forEach((slot) => slot.w.show(false));
    s.status.set("");
    s.hint.set(s.game.win ? "Milano ocalało!" : "Ravagerzy wygrali", s.game.win ? COLOR.good : COLOR.bad);
    finishGame(s, s.game.win, s.game.win ? "Wygrana!" : "Tym razem nie", "defend");
  },
});
