// Tworzy watch/utils/firebase-config.js (klucz API Firebase - plik poza gitem).
// Projekt Firebase jest wspólny z Zakupami, Powrotem i Na szczycie (zakupy-8ec54), więc konfigurację bierzemy:
//   1) z phone/android/app/google-services.json (aplikacja Waga na telefon, pakiet pl.grekot.waga), albo
//   2) z gotowej konfiguracji zegarka Na szczycie lub Powrotu (../korona/watch/..., ../powrot/watch/...).
// Użycie (w folderze waga):  node tools/configure_watch.mjs
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(ROOT, "watch", "utils", "firebase-config.js");
const GOOGLE = join(ROOT, "phone", "android", "app", "google-services.json");
const OTHER_WATCH_CONFIGS = [
  join(ROOT, "..", "korona", "watch", "utils", "firebase-config.js"),
  join(ROOT, "..", "powrot", "watch", "utils", "firebase-config.js"),
];

let apiKey = "";
let projectId = "";
if (existsSync(GOOGLE)) {
  const gs = JSON.parse(readFileSync(GOOGLE, "utf8"));
  projectId = gs.project_info.project_id;
  const client = gs.client.find((c) => c.client_info.android_client_info.package_name === "pl.grekot.waga") || gs.client[0];
  apiKey = client.api_key[0].current_key;
  console.log("Konfiguracja z " + GOOGLE);
} else {
  const other = OTHER_WATCH_CONFIGS.find((p) => existsSync(p));
  if (other) {
    const text = readFileSync(other, "utf8");
    apiKey = (/FIREBASE_API_KEY = "([^"]*)"/.exec(text) || [])[1] || "";
    projectId = (/FIREBASE_PROJECT_ID = "([^"]*)"/.exec(text) || [])[1] || "";
    console.log("Konfiguracja z " + other);
  }
}

if (!apiKey || !projectId) {
  console.error("Brak konfiguracji Firebase: potrzebny phone/android/app/google-services.json albo konfiguracja");
  console.error("zegarka Na szczycie / Powrotu. Zapisuję wersję bez Firebase (synchronizacja wyłączona).");
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
