// Ekran podczas przesyłania: nie gaśnie po opuszczeniu nadgarstka, a po wybudzeniu wraca do aplikacji.
// Każdy błąd jest łapany, żeby brak funkcji w systemie nie dał czarnego ekranu.
import {
  setWakeUpRelaunch,
  setPageBrightTime,
  resetPageBrightTime,
  pauseDropWristScreenOff,
  resetDropWristScreenOff,
  getBrightness,
  setBrightness,
  getAutoBrightness,
  setAutoBrightness,
} from "@zos/display";
import { loadBrightRestore, saveBrightRestore } from "./store.js";

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

// Zdjęcie jaśniej (AMOLED przy niskiej jasności gasi kolory): jasność automatyczna na chwilę wyłączona,
// bo inaczej setBrightness nic nie zmienia. Ustawienia systemu zapamiętane do przywrócenia.
// level 0 = bez zmian.
export function boostBrightness(level) {
  if (!level) return;
  try {
    if (!loadBrightRestore()) {
      saveBrightRestore({ b: Number(getBrightness()) || 50, auto: !!getAutoBrightness() });
    }
    setAutoBrightness({ autoBright: false });
    setBrightness({ brightness: level });
  } catch (e) {}
}

// Przywrócenie jasności sprzed podbicia (bezpieczne do wołania zawsze, także na starcie)
export function restoreBrightness() {
  const saved = loadBrightRestore();
  if (!saved) return;
  try {
    setBrightness({ brightness: saved.b });
    if (saved.auto) setAutoBrightness({ autoBright: true });
  } catch (e) {}
  saveBrightRestore(null);
}
