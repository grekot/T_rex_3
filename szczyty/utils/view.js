// Co pokazać na ekranie - czysta funkcja stanu, testy w test/pick.test.mjs.
import { cardinal, formatDeg, formatDistance, formatWhen } from "./geo.js";
import { pickPeak, stripPeaks, PICK } from "./pick.js";

// Krótka nazwa na boki ekranu: bez dopisków w nawiasach, najwyżej SIDE_CHARS znaków
export const SIDE_CHARS = 14;
export function shortName(name, max = SIDE_CHARS) {
  const n = name.replace(/\s*\(.*\)\s*/g, " ").trim() || name;
  return n.length <= max ? n : n.slice(0, max - 1).trim() + ".";
}

const sideText = (s) => (s ? shortName(s.c.name) + " " + Math.round(Math.abs(s.off)) + "°" : "");

function turnHint(offset) {
  const a = Math.round(Math.abs(offset));
  if (a < 1) return "na wprost";
  return a + "° w " + (offset < 0 ? "lewo" : "prawo");
}

// st: { pos: {lat,lon,t,live} | null, ele: m | null, heading: stopnie | null, cands: [] | null,
//       frozen, now, noDb }
// -> { top, status, name, details, hint, left, right, behind, strip: [{off, elev, best}] }
export function screenModel(st, o = PICK) {
  const m = { top: "", status: "", name: "", details: "", hint: "", left: "", right: "", behind: "", strip: [] };
  const pos = st.pos;
  if (pos) {
    const where = pos.live ? "GPS" : "pozycja: " + formatWhen(pos.t, st.now);
    m.status = isFinite(st.ele) && st.ele !== null ? where + " · " + Math.round(st.ele) + " m n.p.m." : where;
  } else m.status = "szukam GPS...";

  if (st.heading === null || st.heading === undefined) m.top = "kompas ?";
  else m.top = (st.frozen ? "STOP " : "") + formatDeg(st.heading) + " " + cardinal(st.heading);

  if (st.noDb) {
    m.name = "Brak bazy szczytów";
    m.details = "zainstaluj aplikację ponownie";
    return m;
  }
  if (!pos) {
    m.name = "Szukam GPS...";
    m.details = "wyjdź na otwartą przestrzeń";
    m.hint = "pierwszy fix trwa do 1-2 min";
    return m;
  }
  if (st.heading === null || st.heading === undefined) {
    m.name = "Kalibracja kompasu";
    m.details = "zatocz nadgarstkiem ósemkę";
    m.hint = "kilka razy, w różnych kierunkach";
    return m;
  }
  const cands = st.cands || [];
  if (!cands.length) {
    m.name = "Brak szczytów";
    m.details = "w promieniu " + Math.round(o.rangeM / 1000) + " km";
    m.hint = "baza: Polska i pasma przygraniczne";
    return m;
  }
  const r = pickPeak(cands, st.heading, o);
  if (r.best) {
    m.name = r.best.name;
    m.details = r.best.ele + " m · " + formatDistance(r.best.d);
    m.hint = r.best.hidden
      ? formatDeg(r.best.b) + " · " + turnHint(r.offset) + " · może zasłonięty"
      : "kierunek " + formatDeg(r.best.b) + " · " + turnHint(r.offset);
  } else {
    m.name = "Brak szczytu";
    m.details = "w tym kierunku";
    m.hint = "obróć się - strzałki pokazują najbliższe";
  }
  m.left = sideText(r.left);
  m.right = sideText(r.right);
  if (r.behind) m.behind = "za nim: " + shortName(r.behind.name, 20) + " " + r.behind.ele + " m";
  m.strip = stripPeaks(cands, st.heading, o).map((s) => ({ off: s.off, elev: s.c.elev, best: s.c === r.best }));
  return m;
}
