// Przepisuje konfigurację Firebase z google-services.json do lib/firebase_options.dart.
// Projekt Firebase jest ten sam co dla Zakupów i Powrotu; w konsoli trzeba dodać aplikację
// Android pl.grekot.korona i pobrać google-services.json do android/app/.
// Bez pliku zapisuje zaślepkę (aplikacja pokaże „Brak konfiguracji” i tryb przykładu).
// Użycie (w folderze korona/phone):  node tools/configure.mjs
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const PHONE = join(dirname(fileURLToPath(import.meta.url)), "..");
const SOURCE = join(PHONE, "android", "app", "google-services.json");
const TARGET = join(PHONE, "lib", "firebase_options.dart");
const PACKAGE = "pl.grekot.korona";

const PLACEHOLDER = `// ZAŚLEPKA z tools/configure.mjs - brak google-services.json, Firebase wyłączony.
import 'package:firebase_core/firebase_core.dart';

const bool firebaseConfigured = false;

const FirebaseOptions firebaseOptions = FirebaseOptions(
  apiKey: '',
  appId: '',
  messagingSenderId: '',
  projectId: '',
);
`;

function fail(lines) {
  for (const l of lines) console.error(l);
  if (!existsSync(TARGET)) {
    writeFileSync(TARGET, PLACEHOLDER);
    console.error("Zapisano zaślepkę lib/firebase_options.dart (aplikacja zbuduje się bez Firebase).");
  }
  process.exit(1);
}

if (!existsSync(SOURCE)) {
  fail([
    "Brak pliku " + SOURCE,
    "Pobierz go z konsoli Firebase (Ustawienia projektu → Twoje aplikacje → Android " + PACKAGE + ").",
  ]);
}

const gs = JSON.parse(readFileSync(SOURCE, "utf8"));
const client = gs.client.find((c) => c.client_info.android_client_info.package_name === PACKAGE);
if (!client) {
  fail(["W google-services.json nie ma aplikacji " + PACKAGE + " - dodaj ją w konsoli Firebase i pobierz plik ponownie."]);
}

writeFileSync(
  TARGET,
  `// WYGENEROWANE przez tools/configure.mjs z google-services.json - nie edytuj ręcznie.
import 'package:firebase_core/firebase_core.dart';

const bool firebaseConfigured = true;

const FirebaseOptions firebaseOptions = FirebaseOptions(
  apiKey: '${client.api_key[0].current_key}',
  appId: '${client.client_info.mobilesdk_app_id}',
  messagingSenderId: '${gs.project_info.project_number}',
  projectId: '${gs.project_info.project_id}',
  storageBucket: '${gs.project_info.storage_bucket || ""}',
);
`
);

console.log("Projekt Firebase: " + gs.project_info.project_id);
console.log("Zapisano lib/firebase_options.dart");
