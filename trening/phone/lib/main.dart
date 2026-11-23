import 'package:flutter/material.dart';

void main() => runApp(const TreningApp());

/// Wersja 0.0.1: tylko sprawdzenie ścieżki wydań (tag → CI → Sklep rodzinny).
/// Kalendarz, prowadzenie treningu i przypomnienia przychodzą w wersji 0.1.
class TreningApp extends StatelessWidget {
  const TreningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trening',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88A8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const StartScreen(),
    );
  }
}

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Trening')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Wersja testowa', style: text.headlineSmall),
          const SizedBox(height: 12),
          Text(
            'Ta wersja sprawdza tylko, czy aplikacja trafia do Sklepu '
            'rodzinnego i aktualizuje się z niego.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('W wersji 0.1', style: text.titleMedium),
                  const SizedBox(height: 8),
                  for (final item in _nextFeatures)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  '),
                          Expanded(child: Text(item, style: text.bodyMedium)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _nextFeatures = [
  'kalendarz z okienkiem na każdy dzień',
  'rutyna „Kręgosłup 15 min” z licznikami i timerami',
  'test kierunkowy',
  'ocena bólu po treningu i sygnalizacja świetlna',
  'przypomnienia o treningu i przerwach w siedzeniu',
];
