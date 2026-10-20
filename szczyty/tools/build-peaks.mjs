#!/usr/bin/env node
// Buduje bazę szczytów dla zegarka z OpenStreetMap (Overpass API).
//
//   node tools/build-peaks.mjs                       # Polska + pasma przygraniczne -> assets/gt.r/peaks.bin
//   node tools/build-peaks.mjs --json peaks.json     # dodatkowo lista w JSON (np. dla innej aplikacji)
//
// Opcje:
//   --bbox s,w,n,e       obszar pobierania (domyślnie 48.2,13,55.4,25.2)
//   --step 2             wielkość kawałka zapytania Overpass w stopniach
//   --cache DIR          surowe odpowiedzi Overpass (domyślnie %TEMP%/szczyty-osm-cache, poza projektem!)
//   --refresh            pobierz od nowa mimo pamięci podręcznej
//   --region none        bez ograniczenia do okolic Polski
//   --max-km 100         jak daleko od granicy Polski
//   --min-ele 200        minimalna wysokość
//   --lang pl            nazwa z name:pl, gdy jest (pusty = tylko name)
//   --out PATH           plik dla zegarka (domyślnie assets/gt.r/peaks.bin)
//   --json PATH          lista wybranych szczytów w JSON
//   --tile 0.5           wielkość kafla w pliku zegarka (stopnie)
//
// Dane: © OpenStreetMap contributors, licencja ODbL 1.0 (https://www.openstreetmap.org/copyright).
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { fetchPeaks, DEFAULT_CACHE } from "./overpass.mjs";
import { selectPeaks } from "./peaks-lib.mjs";
import { encodeDb } from "./encode.mjs";

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");

function args(argv) {
  const o = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) continue;
    const k = a.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith("--")) o[k] = true;
    else o[k] = argv[++i];
  }
  return o;
}

const a = args(process.argv.slice(2));
const bbox = (a.bbox || "48.2,13,55.4,25.2").split(",").map(Number);
const tile = Number(a.tile || 0.5);
const out = a.out || path.join(ROOT, "assets", "gt.r", "peaks.bin");

console.log("Pobieranie z Overpass", bbox.join(","));
const elements = await fetchPeaks(bbox, { step: Number(a.step || 2), cache: a.cache || DEFAULT_CACHE, refresh: !!a.refresh });
console.log("szczytów z wysokością:", elements.length);

const peaks = selectPeaks(elements, {
  region: a.region === "none" ? null : undefined,
  maxKmFromPoland: Number(a["max-km"] || 100),
  minEle: Number(a["min-ele"] || 200),
  lang: a.lang === true ? "" : a.lang ?? "pl",
});
console.log("po filtrze:", peaks.length);

const lat0 = Math.floor(bbox[0] / tile) * tile;
const lon0 = Math.floor(bbox[1] / tile) * tile;
const grid = {
  lat0,
  lon0,
  size: tile,
  rows: Math.ceil((bbox[2] - lat0) / tile),
  cols: Math.ceil((bbox[3] - lon0) / tile),
};
const now = new Date();
const date = now.getFullYear() * 10000 + (now.getMonth() + 1) * 100 + now.getDate();
const bin = encodeDb(peaks, grid, date);
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, bin);
console.log(`zapisano ${out}: ${bin.length} B, kafle ${grid.rows}x${grid.cols} po ${tile}°`);

if (a.json) {
  const list = peaks.map(({ id, name, lat, lon, ele, iso, wiki, rank }) => ({
    id, name, lat: +lat.toFixed(5), lon: +lon.toFixed(5), ele, iso: +iso.toFixed(2), wiki, rank,
  }));
  fs.writeFileSync(a.json, JSON.stringify({ source: "© OpenStreetMap contributors, ODbL", date, peaks: list }));
  console.log("zapisano", a.json);
}

// Krótkie statystyki: najgęstsze kafle (pamięć zegarka)
const counts = {};
for (const p of peaks) {
  const k = Math.floor((p.lat - lat0) / tile) + "/" + Math.floor((p.lon - lon0) / tile);
  counts[k] = (counts[k] || 0) + 1;
}
const top = Object.entries(counts).sort((x, y) => y[1] - x[1]).slice(0, 5);
console.log("najgęstsze kafle:", top.map(([k, n]) => k + "=" + n).join(", "));
