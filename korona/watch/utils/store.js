// Pamięć zegarka: zdobycia szczytów z list i własne szczyty. Strony porównują stamp(),
// żeby po powrocie z innego ekranu zauważyć zmianę. Każda zmiana ustawia „do wysłania”
// (synchronizacja z telefonem przez Side Service - utils/sync.js).
import { LocalStorage } from "@zos/storage";
import { normalizeClimbs, normalizeCustom, addClimb, removeClimb } from "./korona.js";

const storage = new LocalStorage();
const CLIMBS_KEY = "korona_climbs";
const CUSTOM_KEY = "korona_custom";
const DIRTY_KEY = "korona_dirty";

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

function parse(key, normalize) {
  try {
    return normalize(JSON.parse(read(key) || "{}"));
  } catch (e) {
    return {};
  }
}

export function stamp() {
  return read(CLIMBS_KEY) + "|" + read(CUSTOM_KEY);
}

export function loadClimbs() {
  return parse(CLIMBS_KEY, normalizeClimbs);
}

export function loadCustom() {
  return parse(CUSTOM_KEY, normalizeCustom);
}

function changed() {
  write(DIRTY_KEY, Date.now());
}

export function isDirty() {
  return !!read(DIRTY_KEY);
}

// Wywoływane po udanym wysłaniu; stan, który wysłano, porównujemy, żeby nie zgubić zmian w międzyczasie
export function markSynced(sentStamp) {
  if (sentStamp === stamp()) {
    try {
      storage.removeItem(DIRTY_KEY);
    } catch (e) {
      write(DIRTY_KEY, "");
    }
  }
}

// Zdobycie szczytu z listy albo zmiana daty własnego szczytu
export function saveClimb(id, dateKey, gps) {
  const custom = loadCustom();
  if (custom[id]) {
    custom[id] = { ...custom[id], d: dateKey, gps: !!gps };
    write(CUSTOM_KEY, custom);
  } else {
    write(CLIMBS_KEY, addClimb(loadClimbs(), id, dateKey, gps));
  }
  changed();
}

// Cofnięcie zdobycia; własny szczyt znika w całości
export function deleteClimb(id) {
  const custom = loadCustom();
  if (custom[id]) {
    delete custom[id];
    write(CUSTOM_KEY, custom);
  } else {
    write(CLIMBS_KEY, removeClimb(loadClimbs(), id));
  }
  changed();
}

export function saveCustomPeak(id, peak) {
  const custom = loadCustom();
  custom[id] = peak;
  write(CUSTOM_KEY, normalizeCustom(custom));
  changed();
}

export function renameCustom(id, name) {
  const custom = loadCustom();
  if (!custom[id] || !String(name).trim()) return;
  custom[id] = { ...custom[id], name: String(name).trim().slice(0, 40) };
  write(CUSTOM_KEY, custom);
  changed();
}

// --- synchronizacja ---
const SYNCED_KEY = "korona_synced";

// Czy ten zegarek kiedykolwiek zsynchronizował się z chmurą
export function wasSynced() {
  return !!read(SYNCED_KEY);
}

// Zapis z chmury (po ponownej instalacji aplikacji na zegarku) - bez oznaczania „do wysłania”
export function restore(remote) {
  write(CLIMBS_KEY, normalizeClimbs(remote && remote.climbs));
  write(CUSTOM_KEY, normalizeCustom(remote && remote.custom));
}

export function setSynced(sentStamp) {
  write(SYNCED_KEY, Date.now());
  markSynced(sentStamp);
}
