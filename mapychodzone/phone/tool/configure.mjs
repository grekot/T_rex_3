// Zapisuje lib/firebase_options.dart: konfigurację Firebase dla telefonu i dla przeglądarki.
//
// Projekt Firebase jest wspólny z Zakupami, Powrotem, Wagą i Sklepem (zakupy-8ec54), więc konto
// też jest wspólne. Potrzebne pliki (nie trafiają do repozytorium, patrz .gitignore):
//   android/app/google-services.json – z aplikacją Android pl.grekot.mapychodzone
//   tool/firebase-web.json           – konfiguracja aplikacji Web „MapyChodzone”, np.
//       npx firebase-tools apps:sdkconfig WEB <appId> --project zakupy-8ec54 > tool/firebase-web.json
//     (albo obiekt firebaseConfig skopiowany z konsoli Firebase, zapisany jako JSON)
// Bez plików zapisuje zaślepkę: mapa działa, tylko bez logowania i zapisywania tras.
//
// Użycie (w folderze mapychodzone/phone):  node tool/configure.mjs
// Dla CI (sekret FIREBASE_OPTIONS_MAPYCHODZONE_B64): base64 -w0 lib/firebase_options.dart
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const PHONE = join(dirname(fileURLToPath(import.meta.url)), '..');
const ANDROID = join(PHONE, 'android', 'app', 'google-services.json');
const WEB = join(PHONE, 'tool', 'firebase-web.json');
const TARGET = join(PHONE, 'lib', 'firebase_options.dart');
const PACKAGE = 'pl.grekot.mapychodzone';

const ZASLEPKA = `// ZAŚLEPKA z tool/configure.mjs - brak konfiguracji, Firebase wyłączony (mapa bez konta).
import 'package:firebase_core/firebase_core.dart';

const bool firebaseConfigured = false;

const FirebaseOptions firebaseOptions = FirebaseOptions(
  apiKey: '',
  appId: '',
  messagingSenderId: '',
  projectId: '',
);
`;

function opcje(o) {
  return `FirebaseOptions(
      apiKey: '${o.apiKey}',
      appId: '${o.appId}',
      messagingSenderId: '${o.messagingSenderId}',
      projectId: '${o.projectId}',
      storageBucket: '${o.storageBucket ?? ''}',${o.authDomain ? `\n      authDomain: '${o.authDomain}',` : ''}
    )`;
}

const bledy = [];
let android = null;
if (existsSync(ANDROID)) {
  const gs = JSON.parse(readFileSync(ANDROID, 'utf8'));
  const c = gs.client.find((k) => k.client_info.android_client_info.package_name === PACKAGE);
  if (c) {
    android = {
      apiKey: c.api_key[0].current_key,
      appId: c.client_info.mobilesdk_app_id,
      messagingSenderId: gs.project_info.project_number,
      projectId: gs.project_info.project_id,
      storageBucket: gs.project_info.storage_bucket,
    };
  } else {
    bledy.push(`W ${ANDROID} nie ma aplikacji ${PACKAGE} - dodaj ją w konsoli Firebase i pobierz plik ponownie.`);
  }
} else {
  bledy.push(`Brak ${ANDROID} (konsola Firebase → Ustawienia projektu → Twoje aplikacje → Android ${PACKAGE}).`);
}

let web = null;
if (existsSync(WEB)) {
  // apps:sdkconfig wypisuje czasem tekst przed JSON-em: bierzemy obiekt od pierwszej klamry
  const tekst = readFileSync(WEB, 'utf8');
  const j = JSON.parse(tekst.slice(tekst.indexOf('{'), tekst.lastIndexOf('}') + 1));
  web = j.sdkConfig ?? j.result?.sdkConfig ?? j;
  if (!web.apiKey || !web.appId) {
    bledy.push(`${WEB} nie wygląda na konfigurację aplikacji Web (brak apiKey/appId).`);
    web = null;
  }
} else {
  bledy.push(`Brak ${WEB} (konfiguracja aplikacji Web, patrz komentarz na początku skryptu).`);
}

if (!android && !web) {
  for (const b of bledy) console.error(b);
  writeFileSync(TARGET, ZASLEPKA);
  console.error('Zapisano zaślepkę lib/firebase_options.dart (aplikacja zbuduje się bez Firebase).');
  process.exit(1);
}
for (const b of bledy) console.warn('Uwaga: ' + b);

// Jedna stała firebaseOptions jak w pozostałych aplikacjach (wspólny workflow CI podmienia ten plik);
// wybór platformy przez kIsWeb, który jest stałą kompilacji.
const naTelefon = android ?? web;
const wPrzegladarce = web ?? android;
writeFileSync(
  TARGET,
  `// WYGENEROWANE przez tool/configure.mjs - nie edytuj ręcznie.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

const bool firebaseConfigured = true;

const FirebaseOptions firebaseOptions = kIsWeb
    ? ${opcje(wPrzegladarce)}
    : ${opcje(naTelefon)};
`,
);
console.log(`Projekt Firebase: ${naTelefon.projectId}; telefon: ${android ? 'tak' : 'BRAK'}, przeglądarka: ${web ? 'tak' : 'BRAK'}`);
console.log('Zapisano lib/firebase_options.dart');
