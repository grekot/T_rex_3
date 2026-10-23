// Pomiary w pliku waga.json (+ kopia .bak na wypadek przerwanego zapisu).
import { Time } from "@zos/sensor";
import { readText, writeText } from "./files.js";
import { dateKey, emptyData, normalize, upsert } from "./weight.js";

const FILE = "waga.json";
const BACKUP = "waga.bak";

function parse(text) {
  if (!text) return null;
  try {
    return normalize(JSON.parse(text));
  } catch (e) {
    return null;
  }
}

export function loadData() {
  return parse(readText(FILE)) || parse(readText(BACKUP)) || emptyData();
}

export function saveData(data) {
  const raw = JSON.stringify(data);
  const ok = writeText(FILE, raw);
  if (ok) writeText(BACKUP, raw);
  return ok;
}

// Zapisuje pomiar z dziś; zwraca nowe dane (null gdy zapis do pliku się nie udał)
export function saveToday(w) {
  const data = upsert(loadData(), todayKey(), w, Date.now());
  return saveData(data) ? data : null;
}

// Dzisiejszy dzień w czasie lokalnym. Systemowy zegar (Time) zna strefę -
// getTimezoneOffset() w silniku zegarka może zwracać 0.
export function todayKey() {
  try {
    const t = new Time();
    const y = t.getFullYear();
    const m = t.getMonth(); // 1-12
    const d = t.getDate();
    if (y > 2000 && m >= 1 && m <= 12 && d >= 1) return dateKey(y, m, d);
  } catch (e) {}
  const n = new Date();
  return dateKey(n.getFullYear(), n.getMonth() + 1, n.getDate());
}
