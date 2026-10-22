// Refleks: kółko zmienia kolor na zielony (i zegarek wibruje) w losowej chwili -
// wtedy jak najszybciej machnij ręką. Machnięcie za wcześnie = falstart. 3 rundy.
import { REFLEX } from "../../../utils/moves";
import { buildSignalPage } from "../../../utils/signalpage";
import { stopMotion } from "../../../utils/gamekit";
import { LAMP, LAMP_TEXT, RESULTS } from "zosLoader:./index.page.[pf].layout.js";

Page({
  state: {},

  build() {
    buildSignalPage(this, REFLEX, { LAMP, LAMP_TEXT, RESULTS }, {
      id: "reflex",
      title: "Refleks",
      hint: "Machnij ręką, gdy kółko zzielenieje",
      wait: "Czekaj…",
      go: "TERAZ!",
      early: "Falstart!",
      late: "Za późno",
      win: "Szybki jak raptor!",
      lose: "Tym razem nie",
    });
  },

  onDestroy() {
    stopMotion(this.state);
  },
});
