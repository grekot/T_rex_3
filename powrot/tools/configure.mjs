// Przepisuje konfigurację Firebase z google-services.json do aplikacji Powrót na telefon i na zegarek.
// Projekt Firebase jest ten sam co dla Zakupów; w konsoli trzeba dodać aplikację Android pl.grekot.powrot.
// Użycie (w folderze powrot):  node tools/configure.mjs
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SOURCE = join(ROOT, "phone", "android", "app", "google-services.json");
const PACKAGE = "pl.grekot.powrot";

if (!existsSync(SOURCE)) {
  console.error("Brak pliku " + SOURCE);
  console.error("Pobierz go z konsoli Firebase (Ustawienia projektu → Twoje aplikacje → Android pl.grekot.powrot).");
  process.exit(1);
}

const gs = JSON.parse(readFileSync(SOURCE, "utf8"));
const client = gs.client.find((c) => c.client_info.android_client_info.package_name === PACKAGE);
if (!client) {
  console.error("W google-services.json nie ma aplikacji " + PACKAGE + " - dodaj ją w konsoli Firebase i pobierz plik ponownie.");
  process.exit(1);
}
const projectId = gs.project_info.project_id;
const apiKey = client.api_key[0].current_key;

writeFileSync(
  join(ROOT, "phone", "lib", "firebase_options.dart"),
  `// WYGENEROWANE przez tools/configure.mjs z google-services.json - nie edytuj ręcznie.
import 'package:firebase_core/firebase_core.dart';

const bool firebaseConfigured = true;

const FirebaseOptions firebaseOptions = FirebaseOptions(
  apiKey: '${apiKey}',
  appId: '${client.client_info.mobilesdk_app_id}',
  messagingSenderId: '${gs.project_info.project_number}',
  projectId: '${projectId}',
  storageBucket: '${gs.project_info.storage_bucket || ""}',
);
`
);

writeFileSync(
  join(ROOT, "watch", "utils", "firebase-config.js"),
  `// WYGENEROWANE przez tools/configure.mjs z google-services.json - nie edytuj ręcznie.
export const FIREBASE_CONFIGURED = true;
export const FIREBASE_API_KEY = "${apiKey}";
export const FIREBASE_PROJECT_ID = "${projectId}";
`
);

console.log("Projekt Firebase: " + projectId);
console.log("Zapisano phone/lib/firebase_options.dart i watch/utils/firebase-config.js");
