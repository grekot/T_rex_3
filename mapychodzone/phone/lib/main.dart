import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'ui/ekran_startowy.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // przeglądarka: web/index.html sam ładuje MapLibre GL JS i rejestruje protokół pmtiles://
  if (kIsWeb) MapLibreMap.webLibrarySource = const MapLibreJsSource.preloaded();
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
