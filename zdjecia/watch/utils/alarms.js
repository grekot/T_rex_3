// Budziki systemowe sposobu D: przy każdym starcie aplikacji i ekranu zdjęcia uzgadniamy plan z systemem
// (przeterminowane i obce do kosza, brakujące od nowa, plan zawsze na kilka dni naprzód).
// Budzik ma store: true, więc przetrwa restart zegarka. Każdy błąd API jest łapany (brak = czarny ekran).
import { set, cancel, getAllAlarms } from "@zos/alarm";
import { getPackageInfo } from "@zos/app";
import { Time } from "@zos/sensor";
import { loadSettings, loadPlan, savePlan } from "./store.js";
import { topUp, alarmParam, tzFromClock, PHOTO_PAGE, TEST_DELAY_S } from "./schedule.js";

// Przesunięcie strefy czasowej w minutach: z zegara systemowego (czas lokalny), a gdyby go zabrakło - z Date
export function localOffsetMin() {
  try {
    const t = new Time();
    return tzFromClock(t.getFullYear(), t.getMonth(), t.getDate(), t.getHours(), t.getMinutes(), t.getTime());
  } catch (e) {
    return -new Date().getTimezoneOffset();
  }
}

function systemAlarms() {
  try {
    const list = getAllAlarms();
    return Array.isArray(list) ? list : null;
  } catch (e) {
    return null;
  }
}

// Budzik otwiera wprost ekran zdjęcia; delay (sekundy od teraz) sprawdzony na zegarku w próbie D.
// Wynik: id budzika albo 0, gdy system go nie ustawił (następne uzgodnienie spróbuje jeszcze raz).
function setAlarm(at) {
  try {
    const option = {
      url: PHOTO_PAGE,
      delay: Math.max(1, Math.round((at - Date.now()) / 1000)),
      param: alarmParam(at),
      store: true,
    };
    try {
      option.appid = getPackageInfo().appId;
    } catch (e) {}
    return set(option) || 0;
  } catch (e) {
    return 0;
  }
}

function sortByTime(items) {
  return items.sort((a, b) => a.at - b.at);
}

// Uzgodnienie planu z systemem; wynik: zapisany plan { key, until, items, checked }
export function refreshPlan() {
  const now = Date.now();
  const r = topUp(loadPlan(), systemAlarms(), loadSettings(), now, localOffsetMin(), Math.random);
  // Najpierw anulować, potem ustawiać - nowy budzik może dostać numer anulowanego
  r.cancel.forEach((id) => {
    try {
      cancel(id);
    } catch (e) {}
  });
  const items = sortByTime(r.keep.concat(r.add.map((at) => ({ alarm: setAlarm(at), at }))));
  const plan = { key: r.key, until: r.until, items, checked: now };
  savePlan(plan);
  return plan;
}

// Próba z ekranu ustawień: zdjęcie za TEST_DELAY_S sekund, także przy wyłączonym losowaniu
// (dopisane do planu, żeby uzgadnianie go nie usunęło)
export function scheduleTest() {
  const plan = refreshPlan();
  const at = Date.now() + TEST_DELAY_S * 1000;
  const item = { alarm: setAlarm(at), at, test: true };
  if (item.alarm) {
    plan.items = sortByTime(plan.items.concat([item]));
    savePlan(plan);
  }
  return item;
}
