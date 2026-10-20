// Zdjęcia: telefon wybiera najciekawsze zdjęcia z galerii (bez internetu), kadruje je pod okrągły
// ekran i udostępnia zegarkowi pod 127.0.0.1.
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'ui/home_screen.dart';

// Wersję ustawia CI z tagu (--dart-define=APP_VERSION), lokalny build pokazuje „dev”
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

void main() {
  // Kanał wiadomości z usługą w tle (most dla zegarka, odświeżanie puli)
  FlutterForegroundTask.initCommunicationPort();
  runApp(const ZdjeciaApp());
}

class ZdjeciaApp extends StatelessWidget {
  const ZdjeciaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zdjęcia',
      theme: ThemeData(colorSchemeSeed: Colors.orange, brightness: Brightness.dark),
      home: const HomeScreen(version: appVersion),
    );
  }
}
