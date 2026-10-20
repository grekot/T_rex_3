// Ekran i wibracja. Każdy błąd jest łapany, żeby brak funkcji w systemie nie dał czarnego ekranu.
import { setWakeUpRelaunch, setPageBrightTime } from "@zos/display";
import { Vibrator, VIBRATOR_SCENE_SHORT_STRONG } from "@zos/sensor";

// Po wygaszeniu ekranu i podniesieniu ręki wraca ta sama strona (GPS nie zaczyna od zera)
export function setupScreen(brightMs) {
  try {
    setWakeUpRelaunch({ relaunch: true });
  } catch (e) {}
  try {
    setPageBrightTime({ brightTime: brightMs || 30000 });
  } catch (e) {}
}

// Krótka, mocna - tryby „reminder/call” potrafią wibrować do odwołania
export function vibrate() {
  try {
    const v = new Vibrator();
    v.setMode(VIBRATOR_SCENE_SHORT_STRONG);
    v.start();
  } catch (e) {}
}
