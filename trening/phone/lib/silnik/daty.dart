/// Daty kalendarzowe bez godzin. Liczymy w UTC, żeby zmiana czasu (DST)
/// nie robiła z doby 23 albo 25 godzin.
library;

DateTime dzien(DateTime d) => DateTime.utc(d.year, d.month, d.day);

DateTime dodajDni(DateTime d, int ile) => DateTime.utc(d.year, d.month, d.day + ile);

/// Ile dni od [od] do [do_] (0 = ten sam dzień).
int dniMiedzy(DateTime od, DateTime do_) => dzien(do_).difference(dzien(od)).inDays;

String iso(DateTime d) {
  final x = dzien(d);
  String dwa(int n) => n.toString().padLeft(2, '0');
  return '${x.year}-${dwa(x.month)}-${dwa(x.day)}';
}

/// `27.11`
String krotkaData(DateTime d) => '${d.day}.${d.month.toString().padLeft(2, '0')}';
