// Wspólna strona dla Refleksu i Wędkowania: czekasz na sygnał (kółko zmienia kolor,
// zegarek wibruje), potem jak najszybciej machasz / podrywasz rękę.
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { VIBRATOR_SCENE_SHORT_STRONG, VIBRATOR_SCENE_DURATION, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { newSignalGame, stepSignal, resumeSignal, createFlick, FISH } from "./moves.js";
import { newSeed } from "./store.js";
import { COLOR, label, rect, image } from "./ui.js";
import { finishGame } from "./gameui.js";
import { header, startMotion, stopMotion, buzz } from "./gamekit.js";

const WAIT_COLOR = 0x2e3440;
const GO_COLOR = 0x3fae5a;
const EARLY_COLOR = 0xb8483e;

// cfg: REFLEX albo FISH; ui: { LAMP, LAMP_TEXT, RESULTS } z layoutu; texts: napisy gry
export function buildSignalPage(page, cfg, ui, texts) {
  const s = page.state;
  const now = Date.now();
  s.game = newSignalGame(newSeed(), cfg, now);
  s.flick = createFlick(cfg.flick, 300);
  s.hint = header(texts.title, texts.hint);
  const L = ui.LAMP;
  s.lamp = rect(L.cx - L.r, L.cy - L.r, L.r * 2, L.r * 2, WAIT_COLOR, L.r);
  s.lampText = label({ ...ui.LAMP_TEXT, text: texts.wait });
  s.fish = cfg === FISH ? image("ui/fish.png", L.cx - 18, L.cy + 26) : null;
  if (s.fish) s.fish.show(false);
  s.results = label({ ...ui.RESULTS, color: COLOR.grey });
  const setLamp = (color, text) => {
    s.lamp.setProperty(hmUI.prop.MORE, { x: px(L.cx - L.r), y: px(L.cy - L.r), w: px(L.r * 2), h: px(L.r * 2), radius: px(L.r), color });
    s.lampText.set(text);
  };
  const resultsText = () =>
    s.game.results
      .map((r) => (r.ok ? (cfg === FISH ? "ryba" : r.ms + " ms") : r.early ? "falstart" : "za późno"))
      .join(" · ");
  const ok = startMotion(s, {
    tick: (a, t) => {
      const g = s.game;
      if (g.done) return;
      if (resumeSignal(g, t)) {
        setLamp(WAIT_COLOR, texts.wait);
        if (s.fish) s.fish.show(false);
      }
      const ev = stepSignal(g, t, s.flick.feed(a, t));
      if (ev === "go") {
        setLamp(GO_COLOR, texts.go);
        if (s.fish) s.fish.show(true);
        buzz(s, VIBRATOR_SCENE_SHORT_STRONG);
      } else if (ev === "ok") {
        setLamp(WAIT_COLOR, cfg === FISH ? "Złowiona!" : g.results[g.results.length - 1].ms + " ms");
      } else if (ev === "early") {
        setLamp(EARLY_COLOR, texts.early);
        buzz(s, VIBRATOR_SCENE_DURATION);
      } else if (ev === "late") {
        setLamp(EARLY_COLOR, texts.late);
        if (s.fish) s.fish.show(false);
      }
      if (ev) s.results.set(resultsText());
      if (g.done) {
        stopMotion(s);
        s.results.set("");
        if (g.win) buzz(s, VIBRATOR_SCENE_NOTIFICATION);
        finishGame(s, g.win, g.win ? texts.win : texts.lose);
      }
    },
  });
  if (!ok) s.hint.set("Brak akcelerometru", COLOR.bad);
}
