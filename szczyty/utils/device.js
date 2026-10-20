// Ekran, pamięć i plik bazy na zegarku. Każdy błąd jest łapany (brak API = brak funkcji,
// nie czarny ekran).
import { setPageBrightTime, setWakeUpRelaunch } from "@zos/display";
import { LocalStorage } from "@zos/storage";
import { openAssetsSync, readSync, closeSync, O_RDONLY } from "@zos/fs";

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

// Plik z assets: { read(pozycja, długość) -> Uint8Array, close() } albo null
export function openAsset(path) {
  let fd;
  try {
    fd = openAssetsSync({ path, flag: O_RDONLY });
  } catch (e) {
    return null;
  }
  if (typeof fd !== "number" || fd < 0) return null;
  return {
    read(position, length) {
      const buffer = new ArrayBuffer(length);
      readSync({ fd, buffer, options: { offset: 0, length, position } });
      return new Uint8Array(buffer);
    },
    close() {
      try {
        closeSync({ fd });
      } catch (e) {}
    },
  };
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

// Ustawienia: decl = dodawać deklinację magnetyczną do odczytu kompasu
export function loadCfg() {
  const c = readJson(CFG_KEY) || {};
  return { decl: c.decl !== false };
}

export function saveCfg(c) {
  writeJson(CFG_KEY, { decl: !!c.decl });
}
