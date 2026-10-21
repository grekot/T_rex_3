// Kopiuje wspólną listę szczytów korona/data/peaks.json do assetów aplikacji na telefon
// (phone/assets/peaks.json) i sprawdza, czy pasuje do kontraktu z korona/SYNC.md.
// Uruchom po każdej zmianie listy (np. nowe grupy), potem zbuduj APK ponownie.
// Użycie (w folderze korona/phone):  node tools/copy_peaks.mjs [inny/plik/peaks.json]
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const PHONE = join(dirname(fileURLToPath(import.meta.url)), "..");
const SOURCE = process.argv[2] ? resolve(process.argv[2]) : join(PHONE, "..", "data", "peaks.json");
const TARGET = join(PHONE, "assets", "peaks.json");

const text = readFileSync(SOURCE, "utf8");
const data = JSON.parse(text);
const errors = [];

const groups = Array.isArray(data.groups) ? data.groups : [];
const peaks = Array.isArray(data.peaks) ? data.peaks : [];
if (!groups.length) errors.push("brak grup");
if (!peaks.length) errors.push("brak szczytów");

const groupIds = new Set();
for (const g of groups) {
  if (!g.id || !g.name) errors.push("grupa bez id albo nazwy: " + JSON.stringify(g));
  if (groupIds.has(g.id)) errors.push("powtórzona grupa " + g.id);
  groupIds.add(g.id);
}

const peakIds = new Set();
for (const p of peaks) {
  if (!p.id || !p.name) errors.push("szczyt bez id albo nazwy: " + JSON.stringify(p));
  if (peakIds.has(p.id)) errors.push("powtórzony szczyt " + p.id);
  peakIds.add(p.id);
  if (typeof p.lat !== "number" || typeof p.lon !== "number") errors.push(p.id + ": brak lat/lon");
  if (p.h != null && typeof p.h !== "number") errors.push(p.id + ": h nie jest liczbą");
  if (!Array.isArray(p.groups) || !p.groups.length) errors.push(p.id + ": brak grup");
  for (const g of p.groups || []) if (!groupIds.has(g)) errors.push(p.id + ": nieznana grupa " + g);
}
for (const p of peaks) {
  if (p.variantOf && !peakIds.has(p.variantOf)) errors.push(p.id + ": variantOf " + p.variantOf + " nie istnieje");
}

if (errors.length) {
  console.error("peaks.json nie pasuje do kontraktu (korona/SYNC.md):");
  for (const e of errors.slice(0, 30)) console.error("  - " + e);
  process.exit(1);
}

mkdirSync(dirname(TARGET), { recursive: true });
writeFileSync(TARGET, text);

console.log(`Skopiowano ${peaks.length} szczytów (wersja ${data.version}, ${data.generated}) do assets/peaks.json`);
for (const g of groups) {
  const inGroup = peaks.filter((p) => (p.groups || []).includes(g.id));
  const main = inGroup.filter((p) => !p.variantOf).length;
  const counted = g.counted ?? main;
  console.log(`  ${g.id.padEnd(10)} ${g.name}: ${counted} do zdobycia, ${inGroup.length} w grupie`);
}
