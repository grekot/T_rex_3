import '../urzadzenie.dart';
import 'przebieg.dart';

/// Sygnały na telefonie: telefon leży na podłodze, więc podstawą jest dźwięk,
/// a wibracja tylko go uzupełnia.
class SygnalyUrzadzenia extends Sygnaly {
  const SygnalyUrzadzenia(this.urzadzenie, {this.dzwieki = true});

  final Urzadzenie urzadzenie;
  final bool dzwieki;

  void _ton(String typ, int ms) {
    if (dzwieki) urzadzenie.ton(typ, ms: ms);
  }

  @override
  void startTrzymania() {
    _ton('krotki', 120);
    urzadzenie.wibracja(ms: 60);
  }

  @override
  void odliczanie(int sekund) => _ton('krotki', 60);

  @override
  void koniecTrzymania() {
    _ton('wysoki', 350);
    urzadzenie.wibracja(ms: 250);
  }

  @override
  void zmianaStrony() {
    _ton('potwierdzenie', 250);
    urzadzenie.wibracja(ms: 150);
  }

  @override
  void koniecPrzerwy() => _ton('wysoki', 250);

  @override
  void celOsiagniety() => _ton('potwierdzenie', 200);

  @override
  void koniecTreningu() {
    _ton('potwierdzenie', 700);
    urzadzenie.wibracja(ms: 400);
  }
}
