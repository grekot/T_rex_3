import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'konto/konto.dart';
import 'ui/ekran_startowy.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // przeglądarka: web/index.html sam ładuje MapLibre GL JS i rejestruje protokół pmtiles://
  if (kIsWeb) MapLibreMap.webLibrarySource = const MapLibreJsSource.preloaded();
  // konto do zapisywania tras (dobrowolne; bez konfiguracji albo bez sieci mapa działa bez niego)
  await Konto.inicjuj();
  runApp(const MapyChodzone());
}

/// Kolor przewodni: zieleń lasu.
const zielenLasu = Color(0xFF2E6B3A);

class MapyChodzone extends StatelessWidget {
  const MapyChodzone({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MapyChodzone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: zielenLasu, useMaterial3: true),
      home: const EkranStartowy(),
    );
  }
}
