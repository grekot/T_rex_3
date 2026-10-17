// Zachowanie ekranu w sklepie: powrót do aplikacji po wybudzeniu, dłuższe podświetlenie,
// opcjonalnie brak wygaszania po opuszczeniu nadgarstka. Błędy ignorujemy - to dodatki.
import {
  setWakeUpRelaunch,
  setPageBrightTime,
  pauseDropWristScreenOff,
  resetDropWristScreenOff,
} from "@zos/display";

// Po wygaszeniu ekranu i podniesieniu ręki wraca ta sama strona aplikacji zamiast tarczy
export function stayInApp() {
  try {
    setWakeUpRelaunch({ relaunch: true });
  } catch (e) {}
}

export function keepBright(ms) {
  try {
    setPageBrightTime({ brightTime: ms });
  } catch (e) {}
}

// duration 0 = do odwołania (resetDropWristScreenOff)
export function holdOnWristDrop(on) {
  try {
    if (on) pauseDropWristScreenOff({ duration: 0 });
    else resetDropWristScreenOff();
  } catch (e) {}
}
