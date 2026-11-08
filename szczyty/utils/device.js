// Ekran, pamięć i plik bazy na zegarku. Każdy błąd jest łapany (brak API = brak funkcji,
// nie czarny ekran).
import { setPageBrightTime, setWakeUpRelaunch } from "@zos/display";
import { LocalStorage } from "@zos/storage";
import { openAssetsSync, readSync, closeSync, O_RDONLY } from "@zos/fs";
import { openVerified } from "./assetfile.js";

export const PEAKS_FILE = "peaks.bin";

// Ekran świeci minutę; po wygaszeniu i podniesieniu ręki wraca ta sama strona
export function setupScreen() {
  try {
    setWakeUpRelaunch({ relaunch: true });
  } catch (e) {}
  try {
    setPageBrightTime({ brightTime: 60000 });
  } catch (e) {}
}

// Wynik readSync / hmFS.read: liczba bajtów (albo nic na starszych firmware'ach)
function took(buffer, n, length) {
  const got = typeof n === "number" ? Math.min(Math.max(n, 0), length) : length;
  return new Uint8Array(buffer, 0, got);
}

// Uchwyt bywa nie-liczbą (T-Rex 3 zwraca np. 82 jako inny typ) - sprawdzamy wartość, a do
// readSync/closeSync przekazujemy to, co przyszło
function checkFd(fd) {
  const n = Number(fd);
  if (fd === null || fd === undefined || !isFinite(n) || n < 0) throw new Error("fd " + fd + " (" + typeof fd + ")");
  return fd;
}

// Nowe API @zos/fs (API 3.0)
const zosFs = (path) => ({
  name: "zos",
  open() {
    const fd = checkFd(openAssetsSync({ path, flag: O_RDONLY }));
    return {
      readAt(position, length) {
        const buffer = new ArrayBuffer(length);
        return took(buffer, readSync({ fd, buffer, options: { offset: 0, length, position } }), length);
      },
      readNext(length) {
        const buffer = new ArrayBuffer(length);
        return took(buffer, readSync({ fd, buffer, options: { offset: 0, length } }), length);
      },
      close: () => closeSync({ fd }),
    };
  },
});

// Stare globalne hmFS (API 1.0), jeśli firmware je jeszcze ma
const legacyFs = (path) => ({
  name: "hmFS",
  open() {
    if (typeof hmFS === "undefined") throw new Error("brak");
    const fs = hmFS;
    // hmFS.read zwraca 0 przy sukcesie, nie liczbę bajtów - długość z rozmiaru pliku
    const st = fs.stat_asset(path);
    const size = st && st[0] && st[0].size;
    if (!(size > 0)) throw new Error("stat " + JSON.stringify(st && st[1]));
    const fd = checkFd(fs.open_asset(path, fs.O_RDONLY));
    let at = 0;
    return {
      readAt(position, length) {
        fs.seek(fd, position, fs.SEEK_SET);
        at = position;
        return this.readNext(length);
      },
      readNext(length) {
        const n = Math.max(0, Math.min(length, size - at));
        const buffer = new ArrayBuffer(n);
        if (n) fs.read(fd, buffer, 0, n);
        at += n;
        return new Uint8Array(buffer);
      },
      close: () => fs.close(fd),
    };
  },
});

// Plik z assets: { read(pozycja, długość) -> Uint8Array, close(), how } albo { error }
export function openAsset(path, magic) {
  return openVerified([zosFs(path), legacyFs(path)], magic);
}

const storage = new LocalStorage();
const POS_KEY = "szczyty_pos";
const CFG_KEY = "szczyty_cfg";

function readJson(key) {
  try {
    const raw = storage.getItem(key);
    return raw ? JSON.parse(raw) : null;
  } catch (e) {
    return null;
  }
}

function writeJson(key, value) {
  try {
    storage.setItem(key, JSON.stringify(value));
  } catch (e) {}
}

// Ostatnia pozycja { lat, lon, t, ele? } - żeby od razu coś pokazać, zanim GPS złapie fix
export function loadLastPos() {
  const p = readJson(POS_KEY);
  return p && isFinite(p.lat) && isFinite(p.lon) && isFinite(p.t) ? p : null;
}

export function saveLastPos(p) {
  writeJson(POS_KEY, p);
}

export function cfgStamp() {
  try {
    return storage.getItem(CFG_KEY) || "";
  } catch (e) {
    return "";
  }
}

// Ustawienia: decl = dodawać deklinację magnetyczną do odczytu kompasu (domyślnie nie - na T-Rex 3
// bez korekty wskazania się zgadzały, 2026-10-21), rangeKm = zasięg
// wykrywania (10-100 km), target = szczyt, na który naprowadzamy { name, lat, lon, ele } | null
function validTarget(t) {
  return t && typeof t.name === "string" && isFinite(t.lat) && isFinite(t.lon) && isFinite(t.ele) ? t : null;
}

export function loadCfg() {
  const c = readJson(CFG_KEY) || {};
  const km = Number(c.rangeKm);
  return {
    decl: c.decl === true,
    rangeKm: km >= 10 && km <= 100 ? Math.round(km / 10) * 10 : 100,
    target: validTarget(c.target),
  };
}

export function saveCfg(c) {
  const t = validTarget(c.target);
  writeJson(CFG_KEY, {
    decl: !!c.decl,
    rangeKm: c.rangeKm,
    target: t ? { name: t.name, lat: t.lat, lon: t.lon, ele: t.ele } : null,
  });
}
