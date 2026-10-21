// Przypomnienie wibracją (niesprawdzone na zegarku): przy wyjściu z ekranu głównego
// ustawiamy systemowy alarm @zos/alarm, który o wyliczonej porze otwiera aplikację;
// strona główna rozpoznaje to po zapisanej godzinie i wibruje.
import { set, cancel } from "@zos/alarm";
import { LocalStorage } from "@zos/storage";
import { nextReminder } from "./pet.js";

const storage = new LocalStorage();
const KEY = "pupil_alarm";
const HOME = "page/gt/home/index.page";
const MATCH_MS = 3 * 60000; // otwarcie tyle od pory alarmu = obudził nas alarm

function readAlarm() {
  try {
    return JSON.parse(storage.getItem(KEY) || "null");
  } catch (e) {
    return null;
  }
}

function writeAlarm(a) {
  try {
    storage.setItem(KEY, JSON.stringify(a));
  } catch (e) {}
}

function cancelPending() {
  const a = readAlarm();
  if (a && a.id) {
    try {
      cancel(a.id);
    } catch (e) {}
  }
  writeAlarm(null);
  return a;
}

// Przy otwarciu: kasuje zaplanowany alarm; true, jeśli to on właśnie otworzył aplikację
export function openedByAlarm(now) {
  const a = cancelPending();
  return !!(a && a.time && Math.abs(now - a.time) <= MATCH_MS);
}

// Przy wyjściu: ustawia alarm na najbliższą potrzebę pupila (albo żaden)
export function scheduleReminder(state, now, tz) {
  cancelPending();
  const t = nextReminder(state, now, tz);
  if (!t) return 0;
  try {
    const id = set({ url: HOME, time: Math.floor(t / 1000), param: "alarm", store: true });
    if (id) writeAlarm({ id, time: t });
    return id ? t : 0;
  } catch (e) {
    return 0;
  }
}
