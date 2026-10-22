// Wybór minigry: przewijana lista w grupach. Zadania spacerowe w toku są oznaczone.
import { push } from "@zos/router";
import { getWalk } from "../../../utils/pet";
import { load } from "../../../utils/store";
import { COLOR, label, button, rect } from "../../../utils/ui";
import { TITLE, HINT, LIST_TOP, GROUP, BUTTON, GROUP_GAP, BUTTON_STEP, BOTTOM_PAD } from "zosLoader:./index.page.[pf].layout.js";

const GROUPS = [
  {
    name: "Ruch ręką",
    games: [
      ["Powtórz ruch", "simon"],
      ["Łapanie owoców", "catch"],
      ["Labirynt jajka", "eggroll"],
      ["Celowanie", "aim"],
      ["Balans na kłodzie", "balance"],
      ["Refleks", "reflex"],
      ["Wędkowanie", "fishing"],
      ["Rzut piłką", "throw"],
      ["Skoki", "runner"],
      ["Potrząśnij drzewem", "tree"],
      ["Wykopywanie kości", "dig"],
      ["Balon", "balloon"],
    ],
  },
  {
    name: "Spokój i ćwiczenia",
    games: [
      ["Kołysanie do snu", "rock"],
      ["Medytacja", "calm"],
      ["Wyścig", "race"],
      ["Rozgrzewka", "warmup"],
    ],
  },
  {
    name: "Kompas i barometr",
    games: [
      ["Szukanie jedzenia", "forage"],
      ["Wspinaczka", "climb", "climb"],
      ["Nurkowanie (próba)", "dive"],
    ],
  },
  {
    name: "Na spacer (GPS)",
    games: [
      ["Wyprawa", "trip", "trip"],
      ["Znaczenie terenu", "marks", "marks"],
    ],
  },
  { name: "Bez ruchu", games: [["Lewo czy prawo?", "guess"]] },
];

Page({
  build() {
    const p = load().state;
    label({ ...TITLE, text: "Zabawa" });
    label({ ...HINT, text: "Wygrana: humor +1, zabawa odchudza. Spacer: humor +2", color: COLOR.grey });
    let y = LIST_TOP;
    GROUPS.forEach((g) => {
      label({ ...GROUP, y, text: g.name, color: COLOR.accent });
      y += GROUP.h + GROUP_GAP;
      g.games.forEach(([text, page, walk]) => {
        const busy = walk && getWalk(p, walk);
        button({ ...BUTTON, y, text: busy ? text + " · trwa" : text, color: busy ? COLOR.pillOn : COLOR.pill }, () => push({ url: "page/gt/" + page + "/index.page" }));
        y += BUTTON_STEP;
      });
      y += GROUP_GAP;
    });
    // pusty pas na dole - ostatni przycisk da się podnieść wyżej (okrągły ekran)
    rect(0, y, 480, BOTTOM_PAD, 0x000000);
  },
});
