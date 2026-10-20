// Pamięć zegarka: lista odebranych zdjęć z pomiarami, wybrany zapis ścieżki dla IMG,
// ustawienia losowania, plan budzików i worek zdjęć.
import { LocalStorage } from "@zos/storage";
import { rmSync, readdirSync } from "@zos/fs";
import { mergePhoto } from "./photos.js";
import { normalizeSettings } from "./schedule.js";

const storage = new LocalStorage();
const PHOTOS_KEY = "zd_photos";
const VARIANT_KEY = "zd_src_variant";

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

export function loadPhotos() {
  return readJson(PHOTOS_KEY, []);
}

export function savePhoto(photo) {
  const list = mergePhoto(loadPhotos(), photo);
  writeJson(PHOTOS_KEY, list);
  return list;
}

export function loadVariant() {
  return readJson(VARIANT_KEY, 0);
}

export function saveVariant(n) {
  writeJson(VARIANT_KEY, n);
}

// Pliki w katalogu odbioru (diagnostyka: czy TransferFile w ogóle coś zapisał)
export function downloadedFiles() {
  try {
    return readdirSync({ path: "download" });
  } catch (e) {
    return undefined;
  }
}

// Kasuje wskazane zdjęcia: pliki i wpisy na liście
export function removePhotos(ids) {
  if (!ids || !ids.length) return 0;
  const drop = {};
  ids.forEach((id) => (drop[id] = true));
  const list = loadPhotos();
  list.forEach((p) => {
    if (!drop[p.id]) return;
    const name = p.fileName || p.name;
    if (!name) return;
    try {
      rmSync({ path: "download/" + name });
    } catch (e) {}
  });
  writeJson(PHOTOS_KEY, list.filter((p) => !drop[p.id]));
  return ids.length;
}

export function clearPhotos() {
  const files = downloadedFiles() || [];
  files.forEach((name) => {
    try {
      rmSync({ path: "download/" + name });
    } catch (e) {}
  });
  writeJson(PHOTOS_KEY, []);
}

// Jasność sprzed podbicia na czas zdjęcia: { b, auto } - przywracana przy wyjściu albo przy następnym
// starcie (gdyby aplikacja zamknęła się, zanim zdążyła przywrócić)
const BRIGHT_KEY = "zd_bright_restore";

export function loadBrightRestore() {
  return readJson(BRIGHT_KEY, null);
}

export function saveBrightRestore(value) {
  writeJson(BRIGHT_KEY, value);
}

// Losowe pokazywanie: ustawienia, plan budzików ({ key, until, items: [{ alarm, at }] }) i worek
const SETTINGS_KEY = "zd_settings";
const PLAN_KEY = "zd_plan";
const BAG_KEY = "zd_bag";
const SHOWN_KEY = "zd_shown";

export function loadSettings() {
  return normalizeSettings(readJson(SETTINGS_KEY, null));
}

export function saveSettings(settings) {
  writeJson(SETTINGS_KEY, normalizeSettings(settings));
}

export function loadPlan() {
  return readJson(PLAN_KEY, {});
}

export function savePlan(plan) {
  writeJson(PLAN_KEY, plan);
}

export function loadBag() {
  return readJson(BAG_KEY, {});
}

export function saveBag(bag) {
  writeJson(BAG_KEY, bag);
}

// Kiedy zegarek ostatnio sam pokazał zdjęcie (do sprawdzenia, czy budziki działają)
export function loadShown() {
  return readJson(SHOWN_KEY, []);
}

export function noteShown(entry) {
  writeJson(SHOWN_KEY, loadShown().concat([{ ...entry, at: Date.now() }]).slice(-10));
}
