/// Propozycja wyniku testu kierunkowego z ocen przed i po (tabela z planu).
/// Ostateczny wynik wybierasz sam; aplikacja tylko podpowiada, ostrożnie.
library;

import '../silnik/flagi.dart';

WynikTestu proponujWynik({
  required int bolPrzed,
  required Zasieg zasiegPrzed,
  required int bolPo,
  required Zasieg zasiegPo,
  bool mrowienie = false,
}) {
  // „ból w krzyżu wyraźnie się nasila, schodzi do pośladka albo pojawia się mrowienie”
  if (mrowienie || zasiegPo.index > zasiegPrzed.index || bolPo >= bolPrzed + 2) return WynikTestu.gorzej;
  // „palenie w krzyżu zmalało (albo ból z pośladka cofnął się do krzyża)”
  if (zasiegPo.index < zasiegPrzed.index || bolPo < bolPrzed) return WynikTestu.lepiej;
  return WynikTestu.bezZmian;
}

String nazwaZasiegu(Zasieg z) => switch (z) {
      Zasieg.brak => 'Tylko krzyż',
      Zasieg.posladek => 'Pośladek',
      Zasieg.udo => 'Udo',
      Zasieg.ponizejKolana => 'Poniżej kolana',
    };

String nazwaWyniku(WynikTestu w) => switch (w) {
      WynikTestu.lepiej => 'Lepiej',
      WynikTestu.bezZmian => 'Bez zmian',
      WynikTestu.gorzej => 'Gorzej',
    };
