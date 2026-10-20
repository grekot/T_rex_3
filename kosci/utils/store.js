// Pamięć zegarka: ustawienia (ile kości, jaki rodzaj, potrząsanie) i ostatni rzut,
// żeby po wygaszeniu ekranu i podniesieniu ręki był widoczny ten sam wynik.
import { LocalStorage } from "@zos/storage";
import { normalizeConfig, restoreHand, newHand } from "./dice.js";

const storage = new LocalStorage();
const CONFIG_KEY = "kosci_cfg";
const HAND_KEY = "kosci_hand";

function read(key) {
  try {
    return storage.getItem(key) || "";
  } catch (e) {
    return "";
  }
}

function write(key, value) {
  try {
    storage.setItem(key, JSON.stringify(value));
  } catch (e) {}
}

// Surowy zapis ustawień - strona kości porównuje go, żeby zauważyć zmianę
export function configStamp() {
  return read(CONFIG_KEY);
}

export function loadConfig() {
  try {
    return normalizeConfig(JSON.parse(read(CONFIG_KEY) || "{}"));
  } catch (e) {
    return normalizeConfig(null);
  }
}

export function saveConfig(cfg) {
  write(CONFIG_KEY, normalizeConfig(cfg));
}

export function loadHand(cfg) {
  const raw = read(HAND_KEY);
  return (raw && restoreHand(raw, cfg)) || newHand(cfg);
}

export function saveHand(hand) {
  write(HAND_KEY, hand);
}
