import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'background/alert_worker.dart';
import 'background/photo_worker.dart';
import 'data/cloud_access.dart';
import 'firebase_options.dart';
import 'home_widgets/widget_config.dart';
import 'home_widgets/widget_service.dart';
import 'services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bez google-services.json (zaślepka z tools/configure.mjs) aplikacja działa tylko w sieci domowej.
  if (firebaseConfigured) await Firebase.initializeApp(options: firebaseOptions);
  // WorkManager: powiadomienia (z kontem) i zdjęcia na zegarach (także bez konta).
  await AlertScheduler.init();
  final cloud = firebaseConfigured ? FirebaseCloudAccess(firebaseOptions) : NoCloudAccess();
  runApp(
    Services.production(
      cloud: cloud,
      child: const TermostatApp(useLogin: firebaseConfigured),
    ),
  );
  // Zdjęcia z aplikacji „Zdjęcia” na zegary: teraz, po powrocie do aplikacji i w tle co ~15 min.
  PhotoSyncScheduler.onAppStart();
}

/// Silnik usługi widżetów (LiveWidgetService.kt).
@pragma('vm:entry-point')
void homeWidgetServiceMain() => runHomeWidgetService();

/// Ekran konfiguracji widżetu (WidgetConfigActivity.kt).
@pragma('vm:entry-point')
void homeWidgetConfigMain() => runHomeWidgetConfig();
