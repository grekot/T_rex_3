// Wybór minigry: przewijana lista w grupach. Gra, o którą prosi dinozaur, i zadania
// spacerowe w toku są wyróżnione.
import { push } from "@zos/router";
import { getWalk, activeRequest } from "../../../utils/pet";
import { GAME_GROUPS, GAME_NAMES, WALK_GAMES, gamePage } from "../../../utils/gamelist";
import { load } from "../../../utils/store";
import { COLOR, label, button, rect } from "../../../utils/ui";
import { TITLE, HINT, LIST_TOP, GROUP, BUTTON, GROUP_GAP, BUTTON_STEP, BOTTOM_PAD } from "zosLoader:./index.page.[pf].layout.js";

Page({
  build() {
    const p = load().state;
    const req = activeRequest(p);
    label({ ...TITLE, text: "Zabawa" });
    label({ ...HINT, text: "Wygrana: humor +1, zabawa odchudza. Prośba i spacer: więcej", color: COLOR.grey });
    let y = LIST_TOP;
    GAME_GROUPS.forEach((g) => {
      label({ ...GROUP, y, text: g.name, color: COLOR.accent });
      y += GROUP.h + GROUP_GAP;
      g.games.forEach((id) => {
        const walk = WALK_GAMES[id];
        const busy = walk && getWalk(p, walk);
        const asked = req && req.game === id;
        const text = GAME_NAMES[id] + (asked ? " · prosi!" : busy ? " · trwa" : "");
        button({ ...BUTTON, y, text, color: asked || busy ? COLOR.pillOn : COLOR.pill }, () => push({ url: gamePage(id) }));
        y += BUTTON_STEP;
      });
      y += GROUP_GAP;
    });
    // pusty pas na dole - ostatni przycisk da się podnieść wyżej (okrągły ekran)
    rect(0, y, 480, BOTTOM_PAD, 0x000000);
  },
});
