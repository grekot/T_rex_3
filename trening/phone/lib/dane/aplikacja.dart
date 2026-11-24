/// Dane aplikacji w jednym miejscu: plan, atlas, stan użytkownika i jego zapis.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../plan/atlas.dart';
import '../plan/model.dart';
import '../przypomnienia/harmonogram.dart';
import '../silnik/daty.dart';
import '../silnik/flagi.dart';
import '../silnik/kalendarz.dart';
import '../silnik/sygnalizacja.dart';
import '../trening/przebieg.dart';
import '../trening/rozpiska.dart';
import '../urzadzenie.dart';
import 'magazyn.dart';
import 'okienka.dart';
import 'stan.dart';

/// Ile dni wstecz można odznaczyć trening „bez aplikacji” albo dzień wolny.
const dniWstecz = 7;

/// Na ile dni wstrzymuje się ćwiczenie, które nasiliło ból.
const dniWstrzymania = 7;

class DaneAplikacji extends ChangeNotifier {
  DaneAplikacji({
    required this.plan,
    required this.atlas,
    required this.stan,
    required this.magazyn,
    DateTime Function()? zegar,
    this.planista,
  }) : _zegar = zegar ?? DateTime.now;

  final Plan plan;
  final Atlas atlas;
  final Stan stan;
  final Magazyn magazyn;
  final DateTime Function() _zegar;

  /// Ustawia przypomnienia w systemie (Android); null w testach.
  final Future<void> Function(List<Przypomnienie>)? planista;

  static Future<DaneAplikacji> wczytaj({AssetBundle? zasoby, Urzadzenie urzadzenie = const Urzadzenie()}) async {
    final b = zasoby ?? rootBundle;
    final plan = Plan.zJson(jsonDecode(await b.loadString('assets/plan/plan.json')));
    final atlas = Atlas.zJson(jsonDecode(await b.loadString('assets/plan/atlas.json')));
    final sciezka = await urzadzenie.katalog();
    final magazyn = Magazyn(Directory(sciezka ?? '${Directory.systemTemp.path}/trening'));
    final dane = DaneAplikacji(
      plan: plan,
      atlas: atlas,
      stan: await magazyn.wczytaj(),
      magazyn: magazyn,
      planista: urzadzenie.zaplanujPrzypomnienia,
    );
    unawaited(dane.odswiezPrzypomnienia());
    return dane;
  }

  DateTime get teraz => _zegar();

  DateTime get dzis => dzien(_zegar());

  Kalendarz get kalendarz => Kalendarz.wylicz(plan, stan.start, stan.etapy, dzis);

  DzienPlanu get dzisiaj => kalendarz.naDzien(dzis)!;

  Set<String> get flagi => stan.flagi(dzis);

  ZapisTreningu? get treningDzis => stan.treningi[iso(dzis)];

  bool get wolneDzis => stan.wolne.contains(iso(dzis));

  /// Ćwiczenia wstrzymane po bólu, które obowiązują w dniu [d].
  Map<String, DateTime> wstrzymaneNa(DateTime d) => {
        for (final MapEntry(:key, :value) in stan.wstrzymane.entries)
          if (!dzien(d).isAfter(value)) key: value,
      };

  Rozpiska rozpiszDzis({int? czesc}) =>
      rozpisz(plan, atlas, plan.sesje[dzisiaj.sesja]!, flagi, czesc: czesc, wstrzymane: wstrzymaneNa(dzis));

  /// Podgląd sesji dowolnego dnia z dzisiejszymi flagami.
  Rozpiska rozpiszNa(DzienPlanu d) =>
      rozpisz(plan, atlas, plan.sesje[d.sesja]!, flagi, wstrzymane: wstrzymaneNa(d.data));

  Okienko okienkoNa(DzienPlanu d) => okienko(d, stan, dzis);

  /// Zapisuje trening z prowadzenia. Kilka podejść jednego dnia (np. dwie krótsze
  /// wersje) łączy się w jeden wpis.
  Future<void> zapiszTrening(Rozpiska r, WynikPrzebiegu w, {int? czesc}) async {
    if (w.wykonane.isEmpty && !w.ukonczony) return;
    final klucz = iso(w.start);
    final stary = stan.treningi[klucz];
    final wykonane = {...?stary?.wykonane, ...w.wykonane};
    final czesci = {...?stary?.czesci, ?czesc}.toList()..sort();
    final calosc = (w.ukonczony && czesc == null) || (stary?.stan == StanDnia.wykonane) ||
        (r.sesja.krotszaWersja.isNotEmpty && czesci.length == r.sesja.krotszaWersja.length);
    stan.treningi[klucz] = ZapisTreningu(
      data: dzien(w.start),
      sesja: r.sesja.id,
      stan: calosc ? StanDnia.wykonane : StanDnia.skrocone,
      planWersja: plan.wersja,
      start: stary?.start ?? w.start,
      koniec: w.koniec,
      wykonane: wykonane.toList(),
      pominiete: {...?stary?.pominiete, ...w.pominiete}.difference(wykonane).toList(),
      bolesne: {...?stary?.bolesne, ...w.bolesne}.toList(),
      czesci: czesci,
      ocena: stary?.ocena,
    );
    stan.wolne.remove(klucz);
    await _zapisz();
  }

  Future<void> zapiszTest(WynikTestuKierunkowego w) async {
    stan.testKierunkowy = w;
    await _zapisz();
  }

  Future<void> oznaczTechnikeWidziana(String id) async {
    if (stan.widzianeTechniki.add(id)) await _zapisz();
  }

  // ------------------------------------------------------------ sygnalizacja

  /// Najgorszy zasięg z 7 dni przed [d]: punkt odniesienia dla „schodzi niżej”.
  Zasieg? odniesienie(DateTime d) => najgorszyZasieg(stan.zasiegi, d);

  /// Ocena po treningu dnia [d] (sekcja 5.1). Trening musi być już zapisany.
  Future<WynikSygnalizacji> zapiszOcene(DateTime d, OcenaBolu o, {String? nasililo}) async {
    final zapis = stan.treningi[iso(d)]!;
    final w = ocenStrefe(o, odniesienie: odniesienie(d));
    zapis.ocena = OcenaPoTreningu(
      bol: o.bol,
      zasieg: o.zasieg,
      mrowienie: o.mrowienie,
      nasililo: nasililo,
      strefa: w.strefa,
    );
    _sprawdzFizjo(d);
    await _zapisz();
    return w;
  }

  /// Rano, po godzinie 5:00, dopóki nie ma dzisiejszego check-inu.
  bool get potrzebnyCheckin => _zegar().hour >= 5 && !stan.checkiny.containsKey(iso(dzis));

  /// Wczorajszy trening z bólem ≥ 3, przy którym jeszcze nie wiadomo, czy ból minął.
  ZapisTreningu? get pytajCzyMinelo {
    final z = stan.treningi[iso(dodajDni(dzis, -1))];
    final o = z?.ocena;
    return o != null && o.bol >= 3 && o.minelo == null ? z : null;
  }

  /// Poranny check-in (sekcja 5.2). [minelo] odpowiada na [pytajCzyMinelo]:
  /// ból po wczorajszym treningu, który nie minął w 24 h, to strefa czerwona.
  Future<WynikSygnalizacji> zapiszCheckin(int bol, Zasieg zasieg, {bool? minelo}) async {
    final w = ocenStrefe(OcenaBolu(bol: bol, zasieg: zasieg), odniesienie: odniesienie(dzis));
    final wczoraj = pytajCzyMinelo;
    if (wczoraj != null && minelo != null) {
      wczoraj.ocena!.minelo = minelo;
      if (!minelo) wczoraj.ocena!.strefa = Strefa.czerwona;
    }
    stan.checkiny[iso(dzis)] = Checkin(data: dzis, bol: bol, zasieg: zasieg);
    _sprawdzFizjo(dzis);
    await _zapisz();
    return w;
  }

  Checkin? get checkinDzis => stan.checkiny[iso(dzis)];

  /// Plan: ból albo drętwienie poniżej kolana, które się utrzymuje → specjalista.
  /// Utrzymuje się = 2 różne dni w ciągu ostatniego tygodnia.
  void _sprawdzFizjo(DateTime d) {
    if (stan.fizjoOd != null) return;
    final dni = stan.dniObjawowNerwowych.where((x) {
      final r = dniMiedzy(x, d);
      return r >= 0 && r < 7;
    });
    if (dni.length >= 2) stan.fizjoOd = dzien(d);
  }

  bool get zalecenieFizjo => stan.fizjoOd != null && !stan.fizjoUmowione;

  Future<void> fizjoUmowione() async {
    stan.fizjoUmowione = true;
    await _zapisz();
  }

  Future<void> wstrzymaj(String cwiczenie) async {
    stan.wstrzymane[cwiczenie] = dodajDni(dzis, dniWstrzymania);
    await _zapisz();
  }

  Future<void> przywroc(String cwiczenie) async {
    stan.wstrzymane.remove(cwiczenie);
    await _zapisz();
  }

  // ------------------------------------------------------------ kalendarz

  /// Czy dzień [d] można jeszcze odznaczyć ręcznie: do 7 dni wstecz, a dni sprzed
  /// pierwszego uruchomienia aplikacji (od startu planu) zawsze.
  bool moznaOdznaczyc(DateTime d) {
    final r = dniMiedzy(d, dzis);
    if (r < 0 || dzien(d).isBefore(stan.start)) return false;
    if (r <= dniWstecz) return true;
    final p = stan.pierwszeUruchomienie;
    return p != null && dzien(d).isBefore(p);
  }

  /// „Zrobiłem bez aplikacji”.
  Future<void> oznaczRecznie(DzienPlanu d) async {
    stan.treningi[iso(d.data)] = ZapisTreningu(
      data: d.data,
      sesja: d.sesja,
      stan: StanDnia.wykonane,
      planWersja: plan.wersja,
      recznie: true,
    );
    stan.wolne.remove(iso(d.data));
    await _zapisz();
  }

  Future<void> cofnijOdznaczenie(DateTime d) async {
    stan.treningi.remove(iso(d));
    await _zapisz();
  }

  Future<void> ustawWolne(DateTime d, bool wolne) async {
    if (wolne) {
      stan.wolne.add(iso(d));
    } else {
      stan.wolne.remove(iso(d));
    }
    await _zapisz();
  }

  bool get okienkoOtwarte => stan.otwarteOkienko == dzis;

  Future<void> otworzOkienko() async {
    stan.otwarteOkienko = dzis;
    await _zapisz();
  }

  // ------------------------------------------------------------ profil i ustawienia

  /// Koniec ekranu powitania: data startu planu, zastrzeżenie potwierdzone.
  Future<void> zakonczPowitanie(DateTime start) async {
    _ustawStart(start);
    stan.pierwszeUruchomienie = dzis;
    stan.powitanieZrobione = true;
    await _zapisz();
  }

  /// Datę startu można zmienić, dopóki trwa etap 1 (historia etapów to jeden wpis).
  bool get moznaZmienicStart => stan.etapy.length == 1;

  Future<void> zmienStart(DateTime start) async {
    _ustawStart(start);
    await _zapisz();
  }

  void _ustawStart(DateTime start) {
    stan.start = dzien(start);
    if (stan.etapy.length == 1) stan.etapy[0] = WpisEtapu(stan.etapy[0].nr, stan.start);
  }

  Future<void> ustawSlizgi(bool tak) async {
    stan.slizgiOdFizjo = tak;
    await _zapisz();
  }

  bool get paliDzis => stan.paliDzis == dzis;

  Future<void> ustawPaliDzis(bool pali) async {
    stan.paliDzis = pali ? dzis : null;
    await _zapisz();
  }

  /// Po zmianie [Stan.przypomnienia] w ustawieniach.
  Future<void> zapiszUstawienia() => _zapisz();

  // ------------------------------------------------------------ przypomnienia

  List<Przypomnienie> harmonogram() {
    final k = kalendarz;
    final biezacy = plan.etap(dzisiaj.etap);
    return harmonogramPrzypomnien(
      u: stan.przypomnienia,
      teraz: _zegar(),
      bezTreningu: (d) => stan.treningi.containsKey(iso(d)) || stan.wolne.contains(iso(d)),
      opisTreningu: (d) {
        final dp = k.naDzien(dzien(d));
        // dni zablokowanego etapu: do przejścia obowiązuje sesja bieżącego etapu
        final id = dp == null || dp.zablokowany ? biezacy.harmonogram[d.weekday]! : dp.sesja;
        final s = plan.sesje[id]!;
        return s.minuty == null ? s.nazwa : '${s.nazwa} (ok. ${s.minuty} min)';
      },
      paliDzis: paliDzis,
      wyprostyDozwolone: flagi.contains('wyprostNieSzkodzi'),
    );
  }

  Future<void> odswiezPrzypomnienia() async {
    final p = planista;
    if (p == null || !stan.powitanieZrobione) return;
    await p(harmonogram());
  }

  /// Po powrocie do aplikacji (np. następnego dnia): odśwież ekran i przypomnienia.
  void odswiez() {
    notifyListeners();
    unawaited(odswiezPrzypomnienia());
  }

  Future<void> _zapisz() async {
    await magazyn.zapisz(stan);
    notifyListeners();
    unawaited(odswiezPrzypomnienia());
  }
}
