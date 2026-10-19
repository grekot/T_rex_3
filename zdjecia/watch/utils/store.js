// Pamięć zegarka: lista odebranych zdjęć z pomiarami i wybrany zapis ścieżki dla IMG.
import { LocalStorage } from "@zos/storage";
import { rmSync, readdirSync } from "@zos/fs";
import { mergePhoto } from "./photos.js";

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

export function clearPhotos() {
  const files = downloadedFiles() || [];
  files.forEach((name) => {
    try {
      rmSync({ path: "download/" + name });
    } catch (e) {}
  });
  writeJson(PHOTOS_KEY, []);
}

// Próba 0b: kiedy i którym sposobem otwarto ekran zdjęcia z powiadomienia
const OPEN_LOG_KEY = "zd_open_log";

export function loadOpenLog() {
  return readJson(OPEN_LOG_KEY, []);
}

export function logOpen(method) {
  const log = loadOpenLog().concat([{ m: method, at: Date.now() }]).slice(-20);
  writeJson(OPEN_LOG_KEY, log);
}
