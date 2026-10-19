// Komunikaty z Side Service (this.call) zamienione na linie statusu na zegarku.
import { formatBytes, formatMs } from "./format.js";

const STEP_NAMES = {
  download: "pobieranie",
  convert: "konwersja",
  send: "przesyłanie",
  manifest: "lista zdjęć",
};

export function stepName(step) {
  return STEP_NAMES[step] || step;
}

// Wynik: { current?, log?, photo?, done? } - current to bieżąca linia (nadpisywana), log dopisuje się na stałe
export function describeEvent(ev) {
  const n = ev.index + 1 + "/" + ev.count;
  switch (ev.type) {
    case "STEP":
      return { current: "Zdjęcie " + n + ": " + stepName(ev.step) + "..." };
    case "PROGRESS":
      return { current: "Przesyłanie " + ev.pct + "% z " + formatBytes(ev.total) };
    case "SENT":
      return {
        current: "",
        log: "OK " + n + ": zeg. " + formatBytes(ev.conv) + ", konw. " + formatMs(ev.cvMs) + ", BT " + formatMs(ev.txMs),
        photo: { id: ev.id, conv: ev.conv, dlMs: ev.dlMs, cvMs: ev.cvMs, txMs: ev.txMs },
      };
    case "FAIL":
      return { current: "", log: "Błąd " + n + " (" + stepName(ev.step) + "): " + ev.error };
    case "DONE":
      return { current: "", log: "Koniec: " + ev.sent + "/" + ev.count + " w " + formatMs(ev.ms), done: true };
    default:
      return {};
  }
}

export function describeStart(res) {
  if (!res) return "Brak odpowiedzi z telefonu";
  if (res.ok) {
    if (!res.todo) return "Telefon OK, brak nowych zdjęć (" + res.total + " już jest)";
    return "Telefon OK (" + formatMs(res.manifestMs) + "), nowe: " + res.todo + " z " + res.total;
  }
  if (res.step === "manifest") {
    return "Most niedostępny (" + res.error + "). Czy aplikacja Zdjęcia na telefonie udostępnia zdjęcia?";
  }
  return "Błąd: " + res.error;
}

export function errText(e) {
  if (!e) return "nieznany błąd";
  if (typeof e === "string") return e;
  return e.message || JSON.stringify(e);
}
