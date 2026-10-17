// Przepisuje konfigurację Firebase z google-services.json do aplikacji na telefon i na zegarek.
// Użycie (w folderze lista-zakupow):  node tools/configure.mjs
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SOURCE = join(ROOT, "phone", "android", "app", "google-services.json");
const PACKAGE = "pl.grekot.zakupy";

if (!existsSync(SOURCE)) {
  console.error("Brak pliku " + SOURCE);
  console.error("Pobierz go z konsoli Firebase (Ustawienia projektu → Twoje aplikacje → Android).");
  process.exit(1);
}

const gs = JSON.parse(readFileSync(SOURCE, "utf8"));
const projectId = gs.project_info.project_id;
const messagingSenderId = gs.project_info.project_number;
const storageBucket = gs.project_info.storage_bucket || "";
const client =
  gs.client.find((c) => c.client_info.android_client_info.package_name === PACKAGE) || gs.client[0];
if (client.client_info.android_client_info.package_name !== PACKAGE) {
  console.error(
    "Uwaga: w google-services.json nie ma aplikacji " + PACKAGE +
      " (jest " + client.client_info.android_client_info.package_name + ")."
  );
  process.exit(1);
}
const appId = client.client_info.mobilesdk_app_id;
const apiKey = client.api_key[0].current_key;

const dart = `// WYGENEROWANE przez tools/configure.mjs z google-services.json - nie edytuj ręcznie.
import 'package:firebase_core/firebase_core.dart';

const bool firebaseConfigured = true;

const FirebaseOptions firebaseOptions = FirebaseOptions(
  apiKey: '${apiKey}',
  appId: '${appId}',
  messagingSenderId: '${messagingSenderId}',
  projectId: '${projectId}',
  storageBucket: '${storageBucket}',
);
`;
writeFileSync(join(ROOT, "phone", "lib", "firebase_options.dart"), dart);

const js = `// WYGENEROWANE przez tools/configure.mjs z google-services.json - nie edytuj ręcznie.
export const FIREBASE_CONFIGURED = true;
export const FIREBASE_API_KEY = "${apiKey}";
export const FIREBASE_PROJECT_ID = "${projectId}";
`;
writeFileSync(join(ROOT, "watch", "utils", "firebase-config.js"), js);

console.log("Projekt Firebase: " + projectId);
console.log("Zapisano phone/lib/firebase_options.dart i watch/utils/firebase-config.js");
