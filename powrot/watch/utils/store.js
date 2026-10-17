// Pamięć zegarka: miejsca z telefonu + kolejka operacji czekających na wysłanie.
// Bez telefonu i bez konta wszystko działa lokalnie - kolejka wyśle się po zalogowaniu.
import { LocalStorage } from "@zos/storage";
import { applyOps, removeApplied, migrateOldPoints } from "./places";

const storage = new LocalStorage();
const DATA_KEY = "pw_data";
const PENDING_KEY = "pw_pending";
const OLD_POINTS_KEY = "pt_points"; // wersja 1.0 trzymała tu miejsca tylko lokalnie

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
  return readJson(DATA_KEY, { places: [], fetchedAt: 0, email: "" });
}

export function loadPending() {
  let pending = readJson(PENDING_KEY, []);
  // Jednorazowo: miejsca z wersji 1.0 trafiają do kolejki, żeby zsynchronizować je z telefonem
  const old = readJson(OLD_POINTS_KEY, null);
  if (old) {
    pending = migrateOldPoints(old, Date.now()).concat(pending);
    writeJson(PENDING_KEY, pending);
    try {
      storage.removeItem(OLD_POINTS_KEY);
    } catch (e) {
      writeJson(OLD_POINTS_KEY, null);
    }
  }
  return Array.isArray(pending) ? pending : [];
}

export function viewPlaces() {
  return applyOps(loadData().places || [], loadPending());
}

export function addOps(ops) {
  writeJson(PENDING_KEY, loadPending().concat(ops));
}

let syncing = false;

// Wysyła kolejkę do telefonu i zapisuje świeże miejsca. done({ ok, offline, needsLogin })
export function sync(page, done) {
  if (syncing) return;
  syncing = true;
  const sent = loadPending();
  page
    .request({ method: "SYNC", params: { ops: sent }, timeout: 30000 })
    .then((result) => {
      syncing = false;
      if (result && result.ok) {
        writeJson(DATA_KEY, { places: result.places || [], fetchedAt: result.fetchedAt || Date.now(), email: result.email || "" });
        writeJson(PENDING_KEY, removeApplied(loadPending(), result.applied));
        done({ ok: true });
      } else {
        done({ ok: false, needsLogin: !!(result && result.needsLogin) });
      }
    })
    .catch(() => {
      syncing = false;
      done({ ok: false, offline: true });
    });
}

export function saveIncoming(result) {
  if (result && result.ok) {
    writeJson(DATA_KEY, { places: result.places || [], fetchedAt: result.fetchedAt || Date.now(), email: result.email || "" });
  }
}
