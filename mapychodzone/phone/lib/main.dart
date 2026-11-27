import 'package:flutter/material.dart';

import 'ui/ekran_startowy.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
