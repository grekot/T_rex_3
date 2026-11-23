/// Dane aplikacji w jednym miejscu: plan, atlas, stan użytkownika i jego zapis.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../plan/atlas.dart';
import '../plan/model.dart';
import '../silnik/daty.dart';
import '../silnik/kalendarz.dart';
import '../trening/przebieg.dart';
import '../trening/rozpiska.dart';
import '../urzadzenie.dart';
import 'magazyn.dart';
import 'stan.dart';

class DaneAplikacji extends ChangeNotifier {
  DaneAplikacji({
    required this.plan,
    required this.atlas,
    required this.stan,
    required this.magazyn,
    DateTime Function()? zegar,
  }) : _zegar = zegar ?? DateTime.now;

  final Plan plan;
  final Atlas atlas;
  final Stan stan;
  final Magazyn magazyn;
  final DateTime Function() _zegar;

  static Future<DaneAplikacji> wczytaj({AssetBundle? zasoby, Urzadzenie urzadzenie = const Urzadzenie()}) async {
    final b = zasoby ?? rootBundle;
    final plan = Plan.zJson(jsonDecode(await b.loadString('assets/plan/plan.json')));
    final atlas = Atlas.zJson(jsonDecode(await b.loadString('assets/plan/atlas.json')));
    final sciezka = await urzadzenie.katalog();
    final magazyn = Magazyn(Directory(sciezka ?? '${Directory.systemTemp.path}/trening'));
    return DaneAplikacji(plan: plan, atlas: atlas, stan: await magazyn.wczytaj(), magazyn: magazyn);
  }

  DateTime get dzis => dzien(_zegar());

  Kalendarz get kalendarz => Kalendarz.wylicz(plan, stan.start, stan.etapy, dzis);

  DzienPlanu get dzisiaj => kalendarz.naDzien(dzis)!;

  Set<String> get flagi => stan.flagi(dzis);

  ZapisTreningu? get treningDzis => stan.treningi[iso(dzis)];

  Rozpiska rozpiszDzis({int? czesc}) => rozpisz(plan, atlas, plan.sesje[dzisiaj.sesja]!, flagi, czesc: czesc);

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
    );
    await _zapisz();
  }

  Future<void> zapiszTest(WynikTestuKierunkowego w) async {
    stan.testKierunkowy = w;
    await _zapisz();
  }

  Future<void> oznaczTechnikeWidziana(String id) async {
    if (stan.widzianeTechniki.add(id)) await _zapisz();
  }

  Future<void> _zapisz() async {
    await magazyn.zapisz(stan);
    notifyListeners();
  }
}
