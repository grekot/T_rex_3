// Ekran podczas przesyłania: nie gaśnie po opuszczeniu nadgarstka, a po wybudzeniu wraca do aplikacji.
// Każdy błąd jest łapany, żeby brak funkcji w systemie nie dał czarnego ekranu.
import {
  setWakeUpRelaunch,
  setPageBrightTime,
  resetPageBrightTime,
  pauseDropWristScreenOff,
  resetDropWristScreenOff,
} from "@zos/display";

export function stayInApp() {
  try {
    setWakeUpRelaunch({ relaunch: true });
  } catch (e) {}
}

export function keepScreenOn() {
  try {
    setPageBrightTime({ brightTime: 600000 });
  } catch (e) {}
  try {
    pauseDropWristScreenOff({ duration: 0 });
  } catch (e) {}
}

// Koniecznie przy wyjściu: wyłączenie gaszenia po opuszczeniu nadgarstka trwa do odwołania, także poza aplikacją
export function releaseScreen() {
  try {
    resetDropWristScreenOff();
  } catch (e) {}
  try {
    resetPageBrightTime();
  } catch (e) {}
}
