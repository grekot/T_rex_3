// Ekran podczas szukania auta: dłuższe podświetlenie i powrót do aplikacji po wybudzeniu.
import { setWakeUpRelaunch, setPageBrightTime } from "@zos/display";

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
