// Tworzy watch/utils/firebase-config.js (klucz API Firebase - plik poza gitem).
// Projekt Firebase jest wspólny z Zakupami i Powrotem (zakupy-8ec54), więc konfigurację bierzemy:
//   1) z phone/android/app/google-services.json (aplikacja Na szczycie na telefon, pakiet pl.grekot.naszczycie), albo
//   2) z gotowej konfiguracji zegarka Powrotu (../powrot/watch/utils/firebase-config.js).
// Użycie (w folderze korona):  node tools/configure_watch.mjs
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(ROOT, "watch", "utils", "firebase-config.js");
const GOOGLE = join(ROOT, "phone", "android", "app", "google-services.json");
const POWROT = join(ROOT, "..", "powrot", "watch", "utils", "firebase-config.js");

let apiKey = "";
let projectId = "";
if (existsSync(GOOGLE)) {
  const gs = JSON.parse(readFileSync(GOOGLE, "utf8"));
  projectId = gs.project_info.project_id;
  const client =
    gs.client.find((c) => c.client_info.android_client_info.package_name === "pl.grekot.naszczycie") || gs.client[0];
  apiKey = client.api_key[0].current_key;
  console.log("Konfiguracja z " + GOOGLE);
} else if (existsSync(POWROT)) {
  const text = readFileSync(POWROT, "utf8");
  apiKey = (/FIREBASE_API_KEY = "([^"]*)"/.exec(text) || [])[1] || "";
  projectId = (/FIREBASE_PROJECT_ID = "([^"]*)"/.exec(text) || [])[1] || "";
  console.log("Konfiguracja z " + POWROT);
}

if (!apiKey || !projectId) {
  console.error("Brak konfiguracji Firebase: potrzebny phone/android/app/google-services.json albo");
  console.error("../powrot/watch/utils/firebase-config.js. Zapisuję wersję bez Firebase (synchronizacja wyłączona).");
}

writeFileSync(
  OUT,
  `// WYGENEROWANE przez tools/configure_watch.mjs - nie edytuj ręcznie, nie publikuj (klucz API).
export const FIREBASE_CONFIGURED = ${apiKey && projectId ? "true" : "false"};
export const FIREBASE_API_KEY = "${apiKey}";
export const FIREBASE_PROJECT_ID = "${projectId}";
`
);
console.log("Zapisano " + OUT + (projectId ? " (projekt " + projectId + ")" : ""));
