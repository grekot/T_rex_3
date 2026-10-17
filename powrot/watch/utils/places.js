// Miejsca na zegarku: dane z telefonu (Firebase) + lokalna kolejka operacji (działa offline).
// Czyste funkcje, testy w test/places.test.mjs.
//
// Miejsce: { id, name, lat, lon, at: zapisano (ms), o: 1 moje | 0 udostępnione mi, s: liczba osób, by: e-mail właściciela }
// Operacje w kolejce:
//   { id, t: "addPlace",   p: { id, name, lat, lon, at }, at }
//   { id, t: "delPlace",   pid, at }   - usunięcie własnego miejsca
//   { id, t: "leavePlace", pid, at }   - usunięcie u siebie miejsca udostępnionego przez kogoś
import { newId, cleanName, defaultName } from "./points.js";

export function compactPlace(doc, uid) {
  const members = Array.isArray(doc.members) ? doc.members : [];
  const emails = doc.memberEmails && typeof doc.memberEmails === "object" ? doc.memberEmails : {};
  return {
    id: doc.id,
    name: doc.name || "",
    lat: Number(doc.lat),
    lon: Number(doc.lon),
    at: doc.savedAt || doc.createdAt || 0,
    o: !doc.ownerId || doc.ownerId === uid ? 1 : 0,
    s: members.length || 1,
    by: emails[doc.ownerId] || "",
  };
}

export function isOwn(place) {
  return place.o !== 0;
}

// Najnowsze na górze
export function sortPlaces(places) {
  return places.slice().sort((a, b) => (b.at || 0) - (a.at || 0));
}

export function applyOps(places, ops) {
  let out = places.slice();
  ops.forEach((op) => {
    if (op.t === "addPlace") {
      out = out.filter((p) => p.id !== op.p.id);
      out.push({ ...op.p, o: 1, s: 1, by: "" });
    } else if (op.t === "delPlace" || op.t === "leavePlace") {
      out = out.filter((p) => p.id !== op.pid);
    }
  });
  return sortPlaces(out);
}

export function removeApplied(pending, appliedIds) {
  const done = {};
  (appliedIds || []).forEach((id) => {
    done[id] = true;
  });
  return pending.filter((p) => !done[p.id]);
}

export function removeOp(place, at, rnd) {
  return { id: newId(rnd), t: isOwn(place) ? "delPlace" : "leavePlace", pid: place.id, at };
}

// Zapisanie miejsca. Własne miejsce o tej samej nazwie (np. kolejne "Auto") jest zastępowane -
// zwykle chodzi o nowe miejsce parkowania. Zwraca operacje do dodania do kolejki.
export function savePlaceOps(view, name, lat, lon, at, rnd) {
  const n = cleanName(name) || defaultName(view);
  const key = n.toLowerCase();
  const ops = view
    .filter((p) => isOwn(p) && p.name.toLowerCase() === key)
    .map((p) => ({ id: newId(rnd), t: "delPlace", pid: p.id, at }));
  ops.push({ id: newId(rnd), t: "addPlace", p: { id: newId(rnd), name: n, lat, lon, at }, at });
  return ops;
}

// Miejsca z wersji 1.0 (tylko na zegarku) -> operacje dodania, żeby trafiły do Firebase
export function migrateOldPoints(points, at, rnd) {
  return (points || [])
    .filter((p) => p && isFinite(p.lat) && isFinite(p.lon))
    .map((p) => ({
      id: newId(rnd),
      t: "addPlace",
      p: { id: p.id || newId(rnd), name: cleanName(p.name) || "Punkt", lat: p.lat, lon: p.lon, at: p.at || at },
      at,
    }));
}

export function findPlace(places, id) {
  for (let i = 0; i < places.length; i++) if (places[i].id === id) return places[i];
  return null;
}
