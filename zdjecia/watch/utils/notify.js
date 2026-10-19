// Próba 0b: powiadomienie „Zobacz to” z budzika systemowego i trzy sposoby otwarcia ekranu zdjęcia.
//   A - przycisk powiadomienia wskazuje wprost ekran zdjęcia (dokumentacja mówi tylko o usługach),
//   B - przycisk uruchamia usługę, która otwiera ekran przez launchApp,
//   C - przycisk uruchamia usługę, która ustawia budzik za chwilę z adresem ekranu zdjęcia.
// Wynik 0b: działają wszystkie trzy. Użytkownik woli bez powiadomienia, więc:
//   D - budzik otwiera wprost ekran zdjęcia (krótka wibracja, sam wraca do tarczy po AUTO_CLOSE_S).
import { readParams } from "./photos.js";

export const PHOTO_PAGE = "page/gt/photo/index.page";
export const NOTIFY_SERVICE = "app-service/notify";
export const OPEN_B_SERVICE = "app-service/open_b";
export const OPEN_C_SERVICE = "app-service/open_c";

export const METHODS = ["A", "B", "C"];
export const DIRECT = "D";
export const TEST_DELAY_S = 30;
export const AUTO_CLOSE_S = 15;

// Parametry budzika i przycisków to tekst - trzymamy je krótkie
const MAX_IDS = 10;

export function actionFile(method) {
  if (method === "A") return PHOTO_PAGE;
  if (method === "B") return OPEN_B_SERVICE;
  return OPEN_C_SERVICE;
}

export function testAlarmParam(method, ids, random) {
  const pool = (ids || []).slice();
  // Losowa dziesiątka, żeby powiadomienie nie pokazywało zawsze tego samego
  for (let i = pool.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    const t = pool[i];
    pool[i] = pool[j];
    pool[j] = t;
  }
  return JSON.stringify({ m: method, ids: pool.slice(0, MAX_IDS) });
}

// Treść powiadomienia z parametru budzika; random() jak Math.random
export function notificationFor(param, random) {
  const p = readParams(param);
  const method = METHODS.indexOf(p.m) >= 0 ? p.m : "C";
  const ids = Array.isArray(p.ids) ? p.ids : [];
  const id = ids.length ? ids[Math.floor(random() * ids.length)] : "";
  return {
    title: "Zobacz to",
    content: "Ciekawe zdjęcie czeka na Ciebie (sposób " + method + ")",
    actions: [{ text: "Pokaż", file: actionFile(method), param: JSON.stringify({ id, m: method }) }],
    vibrate: 0,
  };
}

// Parametr budzika sposobu D: od razu wylosowane zdjęcie
export function directAlarmParam(ids, random) {
  const list = ids || [];
  const id = list.length ? list[Math.floor(random() * list.length)] : "";
  return JSON.stringify({ id, m: DIRECT });
}

// Parametr dla ekranu zdjęcia (launchApp / budzik) - tylko to, co potrzebne
export function openParam(param) {
  const p = readParams(param);
  return JSON.stringify({ id: p.id || "", m: p.m || "?" });
}

// Zdjęcie do pokazania: wskazane, a jak go nie ma - losowe
export function pickPhoto(photos, id, random) {
  if (!photos.length) return null;
  const found = photos.filter((p) => p.id === id)[0];
  return found || photos[Math.floor(random() * photos.length)];
}

function two(n) {
  return (n < 10 ? "0" : "") + n;
}

export function clock(ms) {
  const d = new Date(ms);
  return two(d.getHours()) + ":" + two(d.getMinutes()) + ":" + two(d.getSeconds());
}

export function takenText(ms) {
  if (!ms) return "";
  const d = new Date(ms);
  return two(d.getDate()) + "." + two(d.getMonth() + 1) + " " + two(d.getHours()) + ":" + two(d.getMinutes());
}

// Wyniki próby: kiedy który sposób ostatnio otworzył ekran zdjęcia
export function openLogLines(log) {
  return [DIRECT].concat(METHODS).map((m) => {
    const hits = (log || []).filter((e) => e.m === m);
    return m + ": " + (hits.length ? "otwarto " + clock(hits[hits.length - 1].at) : "jeszcze nie");
  });
}
