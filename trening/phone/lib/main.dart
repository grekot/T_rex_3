import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'dane/aplikacja.dart';
import 'ui/ekran_glowny.dart';
import 'ui/ekran_powitania.dart';

void main() => runApp(const TreningApp());

class TreningApp extends StatefulWidget {
  const TreningApp({super.key, this.dane});

  /// Gotowe dane (testy); bez nich aplikacja wczytuje plan, atlas i stan sama.
  final Future<DaneAplikacji>? dane;

  @override
  State<TreningApp> createState() => _TreningAppState();
}

class _TreningAppState extends State<TreningApp> {
  late final Future<DaneAplikacji> _dane = widget.dane ?? DaneAplikacji.wczytaj();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trening',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E88A8), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: FutureBuilder<DaneAplikacji>(
        future: _dane,
        builder: (context, s) {
          if (s.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Nie udało się wczytać planu:\n${s.error}', textAlign: TextAlign.center),
                ),
              ),
            );
          }
          if (!s.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          final dane = s.data!;
          return ListenableBuilder(
            listenable: dane,
            builder: (context, _) =>
                dane.stan.powitanieZrobione ? EkranGlowny(dane: dane) : EkranPowitania(dane: dane),
          );
        },
      ),
    );
  }
}
