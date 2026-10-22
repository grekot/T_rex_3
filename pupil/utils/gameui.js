// Wspólne zakończenie minigier: zapis wyniku (humor, waga) i przycisk powrotu.
import { play, treat, setWalk } from "./pet.js";
import { apply } from "./store.js";
import { COLOR, label, image, button, goBack } from "./ui.js";

export const RESULT = { x: 60, y: 330, w: 360, h: 44, size: 32 };
export const RESULT_MSG = { x: 80, y: 372, w: 320, h: 32, size: 22 };
export const BACK_BTN = { x: 150, y: 410, w: 180, h: 52, size: 26, text: "Wróć" };
export const STARS = [
  { x: 62, y: 332 },
  { x: 378, y: 332 },
]; // gwiazdki z Gemini (40 px) po bokach napisu wygranej

function stars() {
  STARS.forEach((p) => image("ui/star.png", p.x, p.y));
}

// Zapisuje wynik i pokazuje go na dole ekranu (raz na grę)
export function finishGame(st, win, text, gameId) {
  if (st.finished) return;
  st.finished = true;
  let msg = "";
  try {
    const r = apply((p) => play(p, win, gameId));
    msg = win ? "Humor +1, waga -1 g" : "Waga -1 g";
    if (r.anim === "no") msg = r.msg;
    else if (win && r.msg !== "Wygrana!") msg = r.msg + " Waga -1 g";
  } catch (e) {}
  if (win) stars();
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
  stars();
  label({ ...RESULT, text, color: COLOR.good });
  label({ ...RESULT_MSG, text: msg, color: COLOR.grey });
  button(BACK_BTN, goBack);
}
