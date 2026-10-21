// Wybór minigry. Trzy ruchowe (akcelerometr) i jedna na dotyk.
import { push } from "@zos/router";
import { COLOR, label, button } from "../../../utils/ui";
import { TITLE, BUTTONS, HINT } from "zosLoader:./index.page.[pf].layout.js";

const GAMES = [
  { text: "Rzut piłką", page: "throw" },
  { text: "Kołysanie do snu", page: "rock" },
  { text: "Balans na kłodzie", page: "balance" },
  { text: "Lewo czy prawo?", page: "guess" },
];

Page({
  build() {
    label({ ...TITLE, text: "Zabawa" });
    GAMES.forEach((g, i) => button({ ...BUTTONS[i], text: g.text }, () => push({ url: "page/gt/" + g.page + "/index.page" })));
    label({ ...HINT, text: "Wygrana poprawia humor, każda zabawa odchudza", color: COLOR.grey });
  },
});
