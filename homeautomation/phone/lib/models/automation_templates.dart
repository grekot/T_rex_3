// Gotowe reguły: wejście jednego węzła steruje wyjściem drugiego przez hub (API.md pkt „Tryby wejść switch”).

import 'hub.dart';
import 'json_utils.dart';

enum AutomationTemplate {
  button('Przycisk przełącza wyjście', 'Każde wciśnięcie zmienia stan wyjścia.'),
  staircase('Łącznik schodowy', 'Każda zmiana położenia łącznika przełącza wyjście.'),
  follow('Łącznik steruje wyjściem', 'Wyjście jest włączone, gdy łącznik jest zwarty. Dwie reguły.'),
  timer('Czujka - światło na czas', 'Włącza na podany czas, kolejny ruch liczy czas od nowa.');

  const AutomationTemplate(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

String _name(String prefix, String input, String output) {
  final s = '$prefix: $input → $output';
  return s.length > 40 ? s.substring(0, 40) : s;
}

/// Reguły szablonu. [output] to `on` albo `onN`; [seconds] - czas włączenia, tylko [AutomationTemplate.timer].
/// Pierwsze słowo nazwy rozróżnia też id reguł zapisywanych w tej samej milisekundzie ([hubDocId]).
List<Automation> buildTemplate(
  AutomationTemplate template, {
  required String inputDevice,
  required String input,
  required String inputName,
  required String outputDevice,
  required String output,
  required String outputName,
  num seconds = 180,
}) {
  Json trigger(String press) => {'device': inputDevice, 'input': input, 'press': press};
  Json set(String key, bool value) => {
    'device': outputDevice,
    'set': {key: value},
  };
  Automation rule(String prefix, String press, List<Json> then, {String mode = 'single'}) {
    final name = _name(prefix, inputName, outputName);
    return Automation(id: hubDocId(name), name: name, when: [trigger(press)], then: then, mode: mode);
  }

  final toggle = output.replaceFirst('on', 'toggle');
  return switch (template) {
    AutomationTemplate.button => [
      rule('Przycisk', 'down', [set(toggle, true)]),
    ],
    AutomationTemplate.staircase => [
      rule('Schody', 'change', [set(toggle, true)]),
    ],
    AutomationTemplate.follow => [
      rule('Włącz', 'down', [set(output, true)]),
      rule('Wyłącz', 'up', [set(output, false)]),
    ],
    AutomationTemplate.timer => [
      rule('Na czas', 'down', [
        set(output, true),
        {'delay': seconds},
        set(output, false),
      ], mode: 'restart'),
    ],
  };
}
