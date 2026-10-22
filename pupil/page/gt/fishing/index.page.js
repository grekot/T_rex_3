// Wędkowanie: czekasz, aż zegarek zawibruje (branie!), wtedy szybko poderwij rękę.
// Za wcześnie - ryba ucieka, za późno - zjada przynętę. 2 ryby z 3 = wygrana.
import { FISH } from "../../../utils/moves";
import { buildSignalPage } from "../../../utils/signalpage";
import { stopMotion } from "../../../utils/gamekit";
import { LAMP, LAMP_TEXT, RESULTS } from "zosLoader:./index.page.[pf].layout.js";

Page({
  state: {},

  build() {
    buildSignalPage(this, FISH, { LAMP, LAMP_TEXT, RESULTS }, {
      title: "Wędkowanie",
      hint: "Poderwij rękę, gdy zawibruje",
      wait: "Czekamy…",
      go: "Bierze!",
      early: "Spłoszona!",
      late: "Uciekła",
      win: "Dobry połów!",
      lose: "Ryby górą",
    });
  },

  onDestroy() {
    stopMotion(this.state);
  },
});
