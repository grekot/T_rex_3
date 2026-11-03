// Pamięć zegarka (pliki w /data aplikacji, @zos/fs - lekcja z Pupila: LocalStorage bywał nadpisywany starą kopią):
// konfiguracja Bluetooth (klucz, slot, lista punktów), ostatni węzeł, licznik ramek i ostatni pulpit -
// żeby po otwarciu bez telefonu było co pokazać i czym sterować przez btnode (API.md pkt 15).
import { readFileSync, writeFileSync } from "@zos/fs";

function readText(name) {
  try {
    const r = readFileSync({ path: name, options: { encoding: "utf8" } });
    if (typeof r === "string") return r;
    if (r && typeof r.byteLength === "number") {
      const b = new Uint8Array(r);
      let s = "";
      for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
      try {
        return decodeURIComponent(escape(s));
      } catch (e) {
        return s;
      }
    }
  } catch (e) {}
  return "";
}

function writeText(name, text) {
  try {
    writeFileSync({ path: name, data: text, options: { encoding: "utf8" } });
    return true;
  } catch (e) {
    return false;
  }
}

function readJson(name) {
  try {
    return JSON.parse(readText(name) || "null");
  } catch (e) {
    return null;
  }
}

export function loadBle() {
  return readJson("ble.json");
}

export function saveBle(cfg) {
  writeText("ble.json", JSON.stringify(cfg));
}

export function loadPulpit() {
  return readJson("pulpit.json");
}

// Ostatni pulpit z telefonu: strony, urządzenia (bez potwierdzeń), tytuł, dom
export function savePulpit(snapshot) {
  writeText("pulpit.json", JSON.stringify(snapshot));
}

// Dla utils/btlink.js
export const btStorage = {
  loadCounter() {
    const n = Number(readText("btlicznik.txt"));
    return isFinite(n) && n > 0 ? n : 0;
  },
  saveCounter(n) {
    writeText("btlicznik.txt", String(n >>> 0));
  },
  loadMac() {
    const s = readText("btwezel.txt").trim();
    return s || null;
  },
  saveMac(mac) {
    writeText("btwezel.txt", String(mac || ""));
  },
};
