// Co pokazać na ekranie - czysta funkcja stanu, testy w test/pick.test.mjs.
import { cardinal, formatDeg, formatDistance, formatWhen } from "./geo.js";
import { pickPeak, stripPeaks, targetInfo, PICK } from "./pick.js";

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
//       frozen, now, noDb, dbError, loading, target: {name, lat, lon, ele} | null }
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
    m.details = "błąd odczytu";
    m.hint = st.dbError ? "szczegóły: przycisk i" : "zainstaluj aplikację ponownie";
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
  if (st.target) return targetModel(m, st);
  if (st.loading) {
    m.name = "Wczytuję szczyty...";
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

// Ekran naprowadzania na wybrany szczyt: nazwa, odległość, w którą stronę się obrócić,
// strzałka po stronie celu i znacznik na pasku horyzontu, gdy cel jest w zasięgu ±30°
const AHEAD_DEG = 3;
function targetModel(m, st) {
  const t = st.target;
  const obs = { lat: st.pos.lat, lon: st.pos.lon, ele: st.ele };
  const r = targetInfo(t, obs, st.heading);
  m.top = "CEL · " + m.top;
  m.name = t.name;
  m.details = t.ele + " m · " + formatDistance(r.d);
  m.hint = "kierunek " + formatDeg(r.b) + " · " + turnHint(r.offset);
  if (r.d < 150) m.hint = "jesteś na szczycie";
  const a = Math.round(Math.abs(r.offset));
  if (r.offset <= -AHEAD_DEG) m.left = "obróć " + a + "°";
  else if (r.offset >= AHEAD_DEG) m.right = "obróć " + a + "°";
  m.behind = "zmiana celu: przycisk cel";
  if (Math.abs(r.offset) <= PICK.stripHalf) m.strip = [{ off: r.offset, elev: r.elev, best: true }];
  return m;
}
