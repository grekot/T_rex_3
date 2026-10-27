// Tworzy utils/firebase-config.js (klucz API i adres Realtime Database - plik poza gitem).
// Projekt Firebase jest wspólny z Zakupami, Powrotem i Na szczycie (zakupy-8ec54); konfigurację bierzemy
// z ../phone/android/app/google-services.json (aplikacja HomeAutomation na telefon, pakiet pl.grekot.homeautomation):
// api_key klienta i project_info.firebase_url. Bez pliku powstaje zaślepka - zegarek pokaże „Brak konfiguracji”.
// Użycie (w folderze homeautomation/watch):  node tools/configure_watch.mjs
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(ROOT, "utils", "firebase-config.js");
const GOOGLE = join(ROOT, "..", "phone", "android", "app", "google-services.json");

let apiKey = "";
let dbUrl = "";
if (existsSync(GOOGLE)) {
  const gs = JSON.parse(readFileSync(GOOGLE, "utf8"));
  dbUrl = String(gs.project_info.firebase_url || "").replace(/\/+$/, "");
  const client =
    gs.client.find((c) => c.client_info.android_client_info.package_name === "pl.grekot.homeautomation") || gs.client[0];
  apiKey = client.api_key[0].current_key;
  console.log("Konfiguracja z " + GOOGLE);
}

const configured = !!(apiKey && dbUrl);
if (!configured) {
  console.error("Brak konfiguracji Firebase: potrzebny ../phone/android/app/google-services.json z polem");
  console.error("project_info.firebase_url (włączona Realtime Database). Zapisuję zaślepkę - zegarek pokaże „Brak konfiguracji”.");
}

writeFileSync(
  OUT,
  `// WYGENEROWANE przez tools/configure_watch.mjs - nie edytuj ręcznie, nie publikuj (klucz API).
export const FIREBASE_CONFIGURED = ${configured ? "true" : "false"};
export const FIREBASE_API_KEY = "${configured ? apiKey : ""}";
export const FIREBASE_DB_URL = "${configured ? dbUrl : ""}";
`
);
console.log("Zapisano " + OUT + (configured ? " (" + dbUrl + ")" : " (zaślepka)"));
