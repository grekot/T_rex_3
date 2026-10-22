// Wspólne zakończenie minigier: zapis wyniku (humor, waga) i przycisk powrotu.
import { play, treat, setWalk } from "./pet.js";
import { apply } from "./store.js";
import { COLOR, label, button, goBack } from "./ui.js";

export const RESULT = { x: 60, y: 330, w: 360, h: 44, size: 32 };
export const RESULT_MSG = { x: 80, y: 372, w: 320, h: 32, size: 22 };
export const BACK_BTN = { x: 150, y: 410, w: 180, h: 52, size: 26, text: "Wróć" };

// Zapisuje wynik i pokazuje go na dole ekranu (raz na grę)
export function finishGame(st, win, text) {
  if (st.finished) return;
  st.finished = true;
  let msg = "";
  try {
    const r = apply((p) => play(p, win));
    msg = win ? "Humor +1, waga -1 g" : "Waga -1 g";
    if (r.anim === "no") msg = r.msg;
  } catch (e) {}
  label({ ...RESULT, text, color: win ? COLOR.good : COLOR.bad });
  label({ ...RESULT_MSG, text: msg, color: COLOR.grey });
  button(BACK_BTN, goBack);
}

// Zadanie spacerowe ukończone: większa nagroda i usunięcie zadania ze stanu
export const WALK_REWARD = 2;

export function finishWalk(st, key, text) {
  if (st.finished) return;
  st.finished = true;
  let msg = "";
  try {
    const r = apply((p) => treat(setWalk(p, key, null), WALK_REWARD));
    msg = r.anim === "no" ? r.msg : "Humor +" + WALK_REWARD;
  } catch (e) {}
  label({ ...RESULT, text, color: COLOR.good });
  label({ ...RESULT_MSG, text: msg, color: COLOR.grey });
  button(BACK_BTN, goBack);
}
