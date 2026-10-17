// Pamięć zegarka: ostatnie listy z telefonu, kolejka operacji czekających na wysłanie,
// historia wpisanych nazw i ustawienia. Dzięki temu wszystko działa także bez telefonu.
import { LocalStorage } from "@zos/storage";
import { applyOps, queueOp, removeApplied, rememberName } from "./shopping";

const storage = new LocalStorage();
const DATA_KEY = "zk_data";
const PENDING_KEY = "zk_pending";
const HISTORY_KEY = "zk_history";
const SETTINGS_KEY = "zk_settings";

const DEFAULT_SETTINGS = {
  // nie wygaszaj ekranu listy po opuszczeniu nadgarstka (więcej baterii)
  keepOnWristDrop: false,
};

function readJson(key, fallback) {
  try {
    const raw = storage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  } catch (e) {
    return fallback;
  }
}

function writeJson(key, value) {
  try {
    storage.setItem(key, JSON.stringify(value));
  } catch (e) {}
}

export function loadData() {
  return readJson(DATA_KEY, { lists: [], fetchedAt: 0, email: "" });
}

export function loadPending() {
  const p = readJson(PENDING_KEY, []);
  // stare wersje aplikacji trzymały same odhaczenia bez id - pomijamy je
  return Array.isArray(p) ? p.filter((op) => op && op.id && op.t) : [];
}

// Listy do wyświetlenia: dane z telefonu + lokalne, jeszcze niewysłane operacje
export function viewLists() {
  return applyOps(loadData().lists || [], loadPending());
}

export function addOp(op) {
  writeJson(PENDING_KEY, queueOp(loadPending(), op));
}

export function loadHistory() {
  return readJson(HISTORY_KEY, []);
}

export function remember(name) {
  writeJson(HISTORY_KEY, rememberName(loadHistory(), name));
}

export function loadSettings() {
  return { ...DEFAULT_SETTINGS, ...readJson(SETTINGS_KEY, {}) };
}

export function saveSettings(settings) {
  writeJson(SETTINGS_KEY, settings);
}

let syncing = false;

// Wysyła kolejkę do telefonu i zapisuje świeże listy.
// done({ ok, offline, needsLogin, error }) - wywoływane zawsze, także po błędzie.
export function sync(page, done) {
  if (syncing) return;
  syncing = true;
  const sent = loadPending();
  page
    .request({ method: "SYNC", params: { ops: sent }, timeout: 30000 })
    .then((result) => {
      syncing = false;
      if (result && result.ok) {
        writeJson(DATA_KEY, {
          lists: result.lists || [],
          fetchedAt: result.fetchedAt || Date.now(),
          email: result.email || "",
        });
        writeJson(PENDING_KEY, removeApplied(loadPending(), result.applied));
        done({ ok: true });
      } else {
        done({ ok: false, needsLogin: !!(result && result.needsLogin), error: (result && result.error) || "" });
      }
    })
    .catch(() => {
      syncing = false;
      done({ ok: false, offline: true });
    });
}

// Dane wysłane przez telefon z własnej inicjatywy (np. zaraz po zalogowaniu)
export function saveIncoming(result) {
  if (result && result.ok) {
    writeJson(DATA_KEY, {
      lists: result.lists || [],
      fetchedAt: result.fetchedAt || Date.now(),
      email: result.email || "",
    });
  }
}
