/// Daty słownie, po polsku.
library;

const _miesiace = [
  'stycznia', 'lutego', 'marca', 'kwietnia', 'maja', 'czerwca', //
  'lipca', 'sierpnia', 'września', 'października', 'listopada', 'grudnia',
];
const _dni = ['poniedziałek', 'wtorek', 'środa', 'czwartek', 'piątek', 'sobota', 'niedziela'];

/// `środa, 25 listopada`
String dataSlownie(DateTime d) => '${_dni[d.weekday - 1]}, ${dataSlownieKrotko(d)}';

/// `25 listopada`
String dataSlownieKrotko(DateTime d) => '${d.day} ${_miesiace[d.month - 1]}';

/// `25 listopada 2026`
String dataPelna(DateTime d) => '${dataSlownieKrotko(d)} ${d.year}';
