// Pamięć zegarka: zdobyte szczyty z datami. Każda strona czyta świeży stan przy pokazaniu,
// więc po powrocie z innego ekranu wystarczy porównać „stamp”.
import { LocalStorage } from "@zos/storage";
import { normalizeClimbs, addClimb, removeClimb } from "./korona.js";

const storage = new LocalStorage();
const CLIMBS_KEY = "korona_climbs";

function read() {
  try {
    return storage.getItem(CLIMBS_KEY) || "";
  } catch (e) {
    return "";
  }
}

// Surowy zapis - strony porównują go, żeby zauważyć zmianę
export function climbsStamp() {
  return read();
}

export function loadClimbs() {
  try {
    return normalizeClimbs(JSON.parse(read() || "{}"));
  } catch (e) {
    return {};
  }
}

function save(climbs) {
  try {
    storage.setItem(CLIMBS_KEY, JSON.stringify(climbs));
  } catch (e) {}
}

export function saveClimb(id, dateKey, gps) {
  save(addClimb(loadClimbs(), id, dateKey, gps));
}

export function deleteClimb(id) {
  save(removeClimb(loadClimbs(), id));
}
