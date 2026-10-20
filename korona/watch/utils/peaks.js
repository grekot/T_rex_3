// Listy szczytów: Korona Gór Polski + pasma (Wyspowy, Sądecki, Gorce, Tatry) z data/peaks.json
// (wygenerowane do peaks-data.js) oraz „Moje szczyty” dodane ręcznie na zegarku.
import { GROUPS as DATA_GROUPS, RANGES, EXTRA, ROWS } from "./peaks-data.js";

export const MY_GROUP = "moje";

export const GROUPS = DATA_GROUPS.concat([{ id: MY_GROUP, name: "Moje szczyty", short: "Moje", counted: 0 }]);

export const PEAKS = ROWS.map((row) => {
  const [id, name, h, lat, lon, mask, range, r] = row;
  const groups = [];
  for (let i = 0; i < DATA_GROUPS.length; i++) if (mask & (1 << i)) groups.push(DATA_GROUPS[i].id);
  const p = { id, name, h, lat, lon, groups, range: RANGES[range] || "", r: r || 0 };
  const extra = EXTRA[id];
  if (extra) Object.keys(extra).forEach((k) => (p[k] = extra[k]));
  return p;
});

const BY_ID = {};
PEAKS.forEach((p) => (BY_ID[p.id] = p));

export function findGroup(id) {
  for (let i = 0; i < GROUPS.length; i++) if (GROUPS[i].id === id) return GROUPS[i];
  return null;
}

// Szczyt z list albo własny (custom = { id: { name, lat, lon, d, gps } } z pamięci zegarka)
export function findPeak(id, custom) {
  if (BY_ID[id]) return BY_ID[id];
  const c = custom && custom[id];
  return c ? customPeak(id, c) : null;
}

export function customPeak(id, c) {
  return { id, name: c.name, h: c.h || 0, lat: c.lat, lon: c.lon, groups: [MY_GROUP], range: "własny szczyt", r: 0, custom: true };
}

export function customPeaks(custom) {
  return Object.keys(custom || {}).map((id) => customPeak(id, custom[id]));
}

// Wszystkie szczyty do rozpoznawania (z listami i własne)
export function allPeaks(custom) {
  const mine = customPeaks(custom);
  return mine.length ? PEAKS.concat(mine) : PEAKS;
}

// Szczyty jednej listy; counted = bez wariantów KGP
export function groupPeaks(groupId, custom, counted) {
  if (groupId === MY_GROUP) return customPeaks(custom);
  return PEAKS.filter((p) => p.groups.indexOf(groupId) >= 0 && !(counted && p.variantOf));
}
