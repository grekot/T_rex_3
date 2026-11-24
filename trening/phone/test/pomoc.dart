import 'dart:convert';
import 'dart:io';

import 'package:trening/dane/aplikacja.dart';
import 'package:trening/dane/magazyn.dart';
import 'package:trening/dane/stan.dart';
import 'package:trening/plan/atlas.dart';
import 'package:trening/plan/model.dart';
import 'package:trening/przypomnienia/harmonogram.dart';

final planTestowy = Plan.zJson(jsonDecode(File('assets/plan/plan.json').readAsStringSync()));
final atlasTestowy = Atlas.zJson(jsonDecode(File('assets/plan/atlas.json').readAsStringSync()));

/// Magazyn bez dysku (testy widżetów działają w udawanym czasie, prawdziwe IO by się zawiesiło).
class MagazynWPamieci extends Magazyn {
  MagazynWPamieci() : super(Directory('.'));

  Stan? zapisany;
  int zapisow = 0;

  @override
  Future<Stan> wczytaj() async => zapisany ?? Stan();

  @override
  Future<void> zapisz(Stan stan) async {
    zapisany = stan;
    zapisow++;
  }
}

/// Zegar do testów: czas stoi, dopóki go nie przesuniesz.
class Zegar {
  Zegar(this.teraz);

  DateTime teraz;

  DateTime call() => teraz;

  void przesun(Duration d) => teraz = teraz.add(d);
}

/// Dane po ekranie powitania (start 23.11.2026). [planista] zbiera zaplanowane przypomnienia.
DaneAplikacji daneTestowe(
  DateTime Function() zegar, {
  Stan? stan,
  Future<void> Function(List<Przypomnienie>)? planista,
}) =>
    DaneAplikacji(
      plan: planTestowy,
      atlas: atlasTestowy,
      stan: stan ?? (Stan()..powitanieZrobione = true),
      magazyn: MagazynWPamieci(),
      zegar: zegar,
      planista: planista,
    );
