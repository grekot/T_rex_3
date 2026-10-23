// Pliki tekstowe w folderze /data aplikacji (@zos/fs). Używane zamiast LocalStorage:
// na zegarku zapis z jednej instancji LocalStorage potrafił nadpisać świeży stan starą
// kopią z innej (lekcja z Pupila).
import { readFileSync, writeFileSync } from "@zos/fs";

function bytesToString(buf) {
  const b = new Uint8Array(buf);
  let s = "";
  for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
  // zapisujemy tylko JSON z ASCII, ale na wszelki wypadek odkoduj UTF-8
  try {
    return decodeURIComponent(escape(s));
  } catch (e) {
    return s;
  }
}

export function readText(name) {
  try {
    const r = readFileSync({ path: name, options: { encoding: "utf8" } });
    if (typeof r === "string") return r;
    if (r && typeof r.byteLength === "number") return bytesToString(r);
  } catch (e) {}
  return "";
}

export function writeText(name, text) {
  try {
    writeFileSync({ path: name, data: text, options: { encoding: "utf8" } });
    return true;
  } catch (e) {
    return false;
  }
}
