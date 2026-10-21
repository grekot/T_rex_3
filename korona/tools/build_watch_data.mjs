// data/peaks.json -> watch/utils/peaks-data.js (zwarta postać dla zegarka).
// Użycie (w folderze korona):  node tools/build_watch_data.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const data = JSON.parse(fs.readFileSync(path.join(ROOT, "data", "peaks.json"), "utf8"));

const groups = data.groups.map(({ id, name, short, counted }) => ({ id, name, short, counted }));
const ranges = [...new Set(data.peaks.map((p) => p.range || ""))];
const round5 = (x) => Math.round(x * 1e5) / 1e5;
const extra = {};
const rows = data.peaks.map((p) => {
  let mask = 0;
  p.groups.forEach((g) => (mask |= 1 << groups.findIndex((x) => x.id === g)));
  const e = {};
  if (p.variantOf) e.variantOf = p.variantOf;
  if (p.note) e.note = p.note;
  if (p.border) e.border = true;
  if (Object.keys(e).length) extra[p.id] = e;
  const row = [p.id, p.name, p.h || 0, round5(p.lat), round5(p.lon), mask, ranges.indexOf(p.range || "")];
  if (p.r) row.push(p.r);
  return row;
});

const js =
  "// WYGENEROWANE przez tools/build_watch_data.mjs z data/peaks.json - nie edytuj ręcznie.\n" +
  "// Źródła: " + data.sources.join("; ") + "\n" +
  "// Wiersz: [id, nazwa, wysokość, lat, lon, maska grup, indeks pasma, promień rozpoznania (opcjonalnie)]\n" +
  "export const GROUPS = " + JSON.stringify(groups) + ";\n" +
  "export const RANGES = " + JSON.stringify(ranges) + ";\n" +
  "export const EXTRA = " + JSON.stringify(extra) + ";\n" +
  "export const ROWS = [\n" + rows.map((r) => JSON.stringify(r)).join(",\n") + "\n];\n";
const out = path.join(ROOT, "watch", "utils", "peaks-data.js");
fs.writeFileSync(out, js);
console.log("zapisano", out, rows.length, "szczytów,", Math.round(js.length / 1024), "KB");
