// Atlas ćwiczeń → assets/plan/atlas.json + rysunki w assets/plan/img/.
//
// Uruchom z folderu trening/phone, podając folder atlasu (ten z atlas_cwiczen.md i img/):
//   dart run tool/atlas_do_json.dart C:\TMP\My_GIT\Trening\cwiczenia
// Atlas żyje poza repozytorium (folder planu treningowego); tutaj trafia jego kopia jako dane.
import 'dart:convert';
import 'dart:io';

import 'atlas_parser.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Użycie: dart run tool/atlas_do_json.dart <folder atlasu>');
    exit(64);
  }
  final zrodlo = Directory(args.single);
  final md = File('${zrodlo.path}/atlas_cwiczen.md');
  if (!md.existsSync()) {
    stderr.writeln('Brak pliku ${md.path}');
    exit(66);
  }
  final atlas = parsujAtlas(md.readAsStringSync());
  final cwiczenia = atlas['cwiczenia'] as Map<String, Map<String, Object?>>;

  final cel = Directory('assets/plan/img')..createSync(recursive: true);
  for (final stary in cel.listSync().whereType<File>()) {
    stary.deleteSync();
  }
  var rysunkow = 0;
  for (final c in cwiczenia.values) {
    final rysunki = c['rysunki'] as Map<String, Map<String, String>>;
    for (final r in rysunki.values) {
      final plik = File('${zrodlo.path}/${r['plik']}');
      if (!plik.existsSync()) {
        stderr.writeln('Brak rysunku ${plik.path}');
        exit(66);
      }
      plik.copySync('${cel.path}/${plik.uri.pathSegments.last}');
      rysunkow++;
    }
  }

  const enkoder = JsonEncoder.withIndent('  ');
  File('assets/plan/atlas.json').writeAsStringSync('${enkoder.convert(atlas)}\n');
  stdout.writeln('atlas.json: ${cwiczenia.length} ćwiczeń, $rysunkow rysunków, '
      '${(atlas['zasadyWspolne'] as List).length} zasad wspólnych');
}
