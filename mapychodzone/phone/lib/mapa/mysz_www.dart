import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui';

void ustawNakladki(List<Rect> prostokaty, {required bool okno}) {
  final stan = globalContext.getProperty<JSObject?>('mapyChodzone'.toJS);
  if (stan == null) return;
  stan.setProperty('okno'.toJS, okno.toJS);
  stan.setProperty(
    'prostokaty'.toJS,
    [
      for (final r in prostokaty) [r.left.toJS, r.top.toJS, r.right.toJS, r.bottom.toJS].toJS,
    ].toJS,
  );
}
