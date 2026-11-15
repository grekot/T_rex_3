// Zdjęcia na zegarach w tle: osobne zadanie WorkManager co ~15 min przy połączeniu z siecią - niezależne od
// powiadomień (te działają tylko z kontem i włączonymi alarmami). Zadanie jest zarejestrowane, dopóki telefon ma
// zegar z tokenem ≥ `control`, który może mieć ekran `photo` w pokazie (lib/data/photo_sync.dart).
// Do tego synchronizacja przy otwarciu i powrocie do aplikacji (najwyżej co 2 min) i przy otwarciu ekranu zegara.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/device_store.dart';
import '../data/photo_sync.dart';

const photoSyncTaskName = 'homeautomation-photos';

/// WorkManager tylko na Androidzie (most aplikacji Zdjęcia też jest tylko tam).
bool get backgroundSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Przebieg zadania w tle (wołany z dyspozytora WorkManager).
Future<void> runPhotoSyncInBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PhotoSync(store: SecureDeviceStore()).run();
}

class PhotoSyncScheduler {
  static AppLifecycleListener? _lifecycle;

  /// Rejestruje albo odwołuje zadanie w tle według zegarów w telefonie. WorkManager musi być już zainicjowany.
  static Future<void> update({DeviceStore? store, PhotoSyncLog? log}) async {
    if (!backgroundSupported) return;
    try {
      if (await photoSyncWanted(store ?? SecureDeviceStore(), log ?? PrefsPhotoSyncLog())) {
        await Workmanager().registerPeriodicTask(
          photoSyncTaskName,
          photoSyncTaskName,
          frequency: const Duration(minutes: 15),
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
      } else {
        await Workmanager().cancelByUniqueName(photoSyncTaskName);
      }
    } on Object {
      // Brak wtyczki WorkManager (testy, podgląd) - bez zadania w tle; przebiegi przy otwarciu nadal działają.
    }
  }

  /// Start aplikacji: zadanie w tle, przebieg teraz i po każdym powrocie do aplikacji.
  static void onAppStart() {
    if (!backgroundSupported) return;
    unawaited(_foreground());
    _lifecycle ??= AppLifecycleListener(onResume: () => unawaited(_foreground()));
  }

  static Future<void> _foreground() async {
    final store = SecureDeviceStore();
    final log = PrefsPhotoSyncLog();
    try {
      await PhotoSync(store: store, log: log).run(minInterval: const Duration(minutes: 2));
    } on Object catch (e) {
      debugPrint('Zdjęcia na zegarach: $e');
    }
    await update(store: store, log: log);
  }
}
