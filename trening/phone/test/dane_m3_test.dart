import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trening/dane/aplikacja.dart';
import 'package:trening/dane/okienka.dart';
import 'package:trening/dane/stan.dart';
import 'package:trening/przypomnienia/harmonogram.dart';
import 'package:trening/silnik/daty.dart';
import 'package:trening/silnik/flagi.dart';
import 'package:trening/silnik/sygnalizacja.dart';
import 'package:trening/trening/przebieg.dart';

import 'pomoc.dart';

void main() {
  Future<void> trening(DaneAplikacji dane, Zegar zegar) async {
    final r = dane.rozpiszDzis();
    final p = Przebieg(r, zegar: zegar.call);
    while (!p.koniec) {
      p.dalej();
    }
    await dane.zapiszTrening(r, p.wynik());
  }

  group('okienka kalendarza', () {
    test('przeszłe, dzisiejsze, przyszłe i zablokowane', () async {
      final zegar = Zegar(DateTime(2026, 11, 26, 20)); // czwartek, dzień 4
      final dane = daneTestowe(zegar.call);
      await trening(dane, zegar); // dziś zrobione
      await dane.zapiszOcene(dane.dzis, const OcenaBolu(bol: 3, zasieg: Zasieg.brak));
      await dane.ustawWolne(DateTime.utc(2026, 11, 24), true);
      dane.stan.treningi['2026-11-23'] = ZapisTreningu(
        data: DateTime.utc(2026, 11, 23),
        sesja: 'R',
        stan: StanDnia.skrocone,
      );

      Okienko o(int dzien) => dane.okienkoNa(dane.kalendarz.naDzien(DateTime.utc(2026, 11, dzien))!);
      expect(o(23).stan, StanOkienka.skrocone);
      expect(o(24).stan, StanOkienka.wolne);
      expect(o(25).stan, StanOkienka.pominiete);
      expect(o(26).stan, StanOkienka.wykonane);
      expect(o(26).dzis, isTrue);
      expect(o(26).strefa, Strefa.zolta);
      expect(o(27).stan, StanOkienka.przyszle);
      expect(o(27).sesja, 'R');
      // etap 2 najwcześniej po 21 dniach: od 14.12 okienka czekają na kryteria
      final d14 = dane.kalendarz.naDzien(DateTime.utc(2026, 12, 14))!;
      expect(dane.okienkoNa(d14).stan, StanOkienka.zablokowane);
      expect(dane.kalendarz.dlugosc, 84);
      expect(treningiWTygodniu(dane.stan, dane.dzis), 2);
    });

    test('znaczek testu kierunkowego: w 1. tygodniu do zrobienia, potem w dniu zrobienia', () async {
      final zegar = Zegar(DateTime(2026, 11, 24, 9));
      final dane = daneTestowe(zegar.call);
      Okienko o(int dzien) => dane.okienkoNa(dane.kalendarz.naDzien(DateTime.utc(2026, 11, dzien))!);
      expect(o(24).test, isTrue);
      expect(o(25).test, isFalse);
      expect(o(23).test, isFalse); // przeszłość bez testu
      dane.stan.testKierunkowy = WynikTestuKierunkowego(
        data: DateTime.utc(2026, 11, 24),
        wynik: WynikTestu.lepiej,
        bolPrzed: 3,
        zasiegPrzed: Zasieg.brak,
        bolPo: 1,
        zasiegPo: Zasieg.brak,
      );
      expect(o(24).test, isTrue);
    });
  });

  group('ocena i check-in', () {
    test('ból 3–4 po treningu: rano pytanie, „nie minął” → czerwona strefa wczorajszego treningu', () async {
      final zegar = Zegar(DateTime(2026, 11, 25, 20));
      final dane = daneTestowe(zegar.call);
      await trening(dane, zegar);
      final w = await dane.zapiszOcene(dane.dzis, const OcenaBolu(bol: 4, zasieg: Zasieg.brak));
      expect(w.strefa, Strefa.zolta);

      zegar.teraz = DateTime(2026, 11, 26, 4, 30);
      expect(dane.potrzebnyCheckin, isFalse, reason: 'przed 5:00');
      zegar.teraz = DateTime(2026, 11, 26, 7);
      expect(dane.potrzebnyCheckin, isTrue);
      expect(dane.pytajCzyMinelo, isNotNull);

      await dane.zapiszCheckin(2, Zasieg.brak, minelo: false);
      final wczoraj = dane.stan.treningi['2026-11-25']!.ocena!;
      expect(wczoraj.minelo, isFalse);
      expect(wczoraj.strefa, Strefa.czerwona);
      expect(dane.potrzebnyCheckin, isFalse);
      expect(dane.pytajCzyMinelo, isNull);
    });

    test('ból ≤ 2 po treningu: rano bez pytania „czy minął”', () async {
      final zegar = Zegar(DateTime(2026, 11, 25, 20));
      final dane = daneTestowe(zegar.call);
      await trening(dane, zegar);
      await dane.zapiszOcene(dane.dzis, const OcenaBolu(bol: 2, zasieg: Zasieg.brak));
      zegar.teraz = DateTime(2026, 11, 26, 7);
      expect(dane.pytajCzyMinelo, isNull);
    });

    test('zasięg z check-inu i ocen trafia do flag (wyprosty wypadają, gdy ból schodzi niżej)', () async {
      final zegar = Zegar(DateTime(2026, 11, 26, 7));
      final dane = daneTestowe(zegar.call);
      dane.stan.testKierunkowy = WynikTestuKierunkowego(
        data: DateTime.utc(2026, 11, 24),
        wynik: WynikTestu.lepiej,
        bolPrzed: 3,
        zasiegPrzed: Zasieg.brak,
        bolPo: 1,
        zasiegPo: Zasieg.brak,
      );
      dane.stan.checkiny['2026-11-25'] = Checkin(data: DateTime.utc(2026, 11, 25), bol: 1, zasieg: Zasieg.brak);
      expect(dane.flagi, contains('wyprostNieSzkodzi'));
      expect(dane.rozpiszDzis().pominiete.map((p) => p.cwiczenie.id), isNot(contains('wyprosty-w-lezeniu')));

      final w = await dane.zapiszCheckin(2, Zasieg.posladek);
      expect(w.schodziNizej, isTrue);
      expect(dane.flagi, contains('zasiegSchodziNizej'));
      final pominiete = dane.rozpiszDzis().pominiete;
      expect(pominiete.map((p) => p.powod), contains('Ból schodzi dziś niżej niż w ostatnich dniach.'));
    });

    test('ból poniżej kolana w 2 dni w tygodniu: zalecenie fizjoterapeuty do „umówione”', () async {
      final zegar = Zegar(DateTime(2026, 11, 25, 7));
      final dane = daneTestowe(zegar.call);
      await dane.zapiszCheckin(3, Zasieg.ponizejKolana);
      expect(dane.zalecenieFizjo, isFalse, reason: 'jeden dzień to jeszcze nie „utrzymuje się”');
      zegar.teraz = DateTime(2026, 11, 27, 7);
      await dane.zapiszCheckin(3, Zasieg.ponizejKolana);
      expect(dane.zalecenieFizjo, isTrue);
      expect(dane.stan.fizjoOd, DateTime.utc(2026, 11, 27));
      await dane.fizjoUmowione();
      expect(dane.zalecenieFizjo, isFalse);
    });

    test('ćwiczenie, które nasiliło ból, można wstrzymać na 7 dni i przywrócić', () async {
      final zegar = Zegar(DateTime(2026, 11, 25, 20));
      final dane = daneTestowe(zegar.call);
      await dane.wstrzymaj('bird-dog');
      expect(dane.stan.wstrzymane['bird-dog'], DateTime.utc(2026, 12, 2));
      final p = dane.rozpiszDzis().pominiete.singleWhere((p) => p.cwiczenie.id == 'bird-dog');
      expect(p.powod, 'Wstrzymane do 2.12: bolało.');
      expect(dane.rozpiszDzis().cwiczenia.map((c) => c.id), isNot(contains('bird-dog')));

      zegar.teraz = DateTime(2026, 12, 3, 20); // po 7 dniach wraca samo
      expect(dane.rozpiszDzis().cwiczenia.map((c) => c.id), contains('bird-dog'));

      zegar.teraz = DateTime(2026, 11, 26, 20);
      await dane.przywroc('bird-dog');
      expect(dane.rozpiszDzis().cwiczenia.map((c) => c.id), contains('bird-dog'));
    });
  });

  group('odznaczanie ręczne', () {
    test('do 7 dni wstecz, a dni sprzed pierwszego uruchomienia zawsze', () async {
      final zegar = Zegar(DateTime(2026, 12, 10, 12));
      final dane = daneTestowe(zegar.call);
      expect(dane.moznaOdznaczyc(DateTime.utc(2026, 12, 3)), isTrue);
      expect(dane.moznaOdznaczyc(DateTime.utc(2026, 12, 2)), isFalse);
      expect(dane.moznaOdznaczyc(DateTime.utc(2026, 12, 11)), isFalse, reason: 'przyszłość');
      expect(dane.moznaOdznaczyc(DateTime.utc(2026, 11, 22)), isFalse, reason: 'przed startem');

      dane.stan.pierwszeUruchomienie = DateTime.utc(2026, 11, 30);
      expect(dane.moznaOdznaczyc(DateTime.utc(2026, 11, 23)), isTrue);
      expect(dane.moznaOdznaczyc(DateTime.utc(2026, 12, 1)), isFalse);
    });

    test('„zrobiłem bez aplikacji”, cofnięcie i dzień wolny', () async {
      final zegar = Zegar(DateTime(2026, 11, 26, 12));
      final dane = daneTestowe(zegar.call);
      final d = dane.kalendarz.naDzien(DateTime.utc(2026, 11, 24))!;
      await dane.ustawWolne(d.data, true);
      expect(dane.okienkoNa(d).stan, StanOkienka.wolne);
      await dane.oznaczRecznie(d);
      expect(dane.okienkoNa(d).stan, StanOkienka.wykonane);
      expect(dane.stan.treningi['2026-11-24']!.recznie, isTrue);
      expect(dane.stan.wolne, isEmpty);
      await dane.cofnijOdznaczenie(d.data);
      expect(dane.okienkoNa(d).stan, StanOkienka.pominiete);
    });

    test('powitanie ustawia datę startu i pierwszy dzień z aplikacją', () async {
      final zegar = Zegar(DateTime(2026, 11, 30, 18));
      final dane = daneTestowe(zegar.call, stan: Stan(start: DateTime.utc(2026, 11, 30)));
      expect(dane.stan.powitanieZrobione, isFalse);
      await dane.zakonczPowitanie(DateTime(2026, 11, 23));
      expect(dane.stan.start, DateTime.utc(2026, 11, 23));
      expect(dane.stan.etapy.single.od, DateTime.utc(2026, 11, 23));
      expect(dane.stan.pierwszeUruchomienie, DateTime.utc(2026, 11, 30));
      expect(dane.dzisiaj.nr, 8);
    });
  });

  group('przypomnienia z danych', () {
    test('po zapisie lista idzie do Androida; dzisiejszy trening znika po zrobieniu', () async {
      final zegar = Zegar(DateTime(2026, 11, 25, 12));
      List<Przypomnienie>? ostatnie;
      final dane = daneTestowe(zegar.call, planista: (l) async => ostatnie = l);
      await dane.ustawPaliDzis(true);
      expect(ostatnie, isNotNull);
      final dzis = ostatnie!.where((p) => p.kanal == 'trening' && p.kiedy.day == 25);
      expect(dzis.single.tresc, 'Kręgosłup 15 min (ok. 15 min)');
      expect(ostatnie!.firstWhere((p) => p.kanal == 'przerwy').kiedy, DateTime(2026, 11, 25, 12, 25));

      await trening(dane, zegar);
      expect(ostatnie!.where((p) => p.kanal == 'trening' && p.kiedy.day == 25), isEmpty);
    });

    test('przed ekranem powitania nic nie jest planowane', () async {
      final zegar = Zegar(DateTime(2026, 11, 25, 12));
      var wywolan = 0;
      final dane = daneTestowe(zegar.call, stan: Stan(), planista: (_) async => wywolan++);
      await dane.odswiezPrzypomnienia();
      expect(wywolan, 0);
    });
  });

  test('stan.json: nowe pola przechodzą zapis i odczyt', () async {
    final zegar = Zegar(DateTime(2026, 11, 26, 20));
    final dane = daneTestowe(zegar.call);
    await trening(dane, zegar);
    await dane.zapiszOcene(dane.dzis, const OcenaBolu(bol: 3, zasieg: Zasieg.posladek, mrowienie: true),
        nasililo: 'bird-dog');
    await dane.zapiszCheckin(1, Zasieg.brak);
    await dane.ustawWolne(DateTime.utc(2026, 11, 24), true);
    await dane.wstrzymaj('bird-dog');
    await dane.otworzOkienko();
    await dane.ustawPaliDzis(true);
    dane.stan
      ..fizjoOd = DateTime.utc(2026, 11, 26)
      ..pierwszeUruchomienie = DateTime.utc(2026, 11, 25)
      ..przypomnienia.drugie = true;
    final json = jsonDecode(jsonEncode(dane.stan.toJson())) as Map<String, Object?>;
    final odczyt = Stan.zJson(json);
    expect(odczyt.toJson(), json);
    expect(iso(odczyt.otwarteOkienko!), '2026-11-26');
    expect(odczyt.treningi['2026-11-26']!.ocena!.nasililo, 'bird-dog');
  });
}
