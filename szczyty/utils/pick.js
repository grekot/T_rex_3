// Który szczyt wskazuje zegarek? Czyste funkcje, testy w test/pick.test.mjs.
//
// 1) buildCandidates - raz na zmianę pozycji: odległość, kierunek i kąt wzniesienia
//    każdego szczytu w zasięgu, z uwzględnieniem krzywizny Ziemi; zgrubnie oznacza szczyty
//    zasłonięte przez bliższy, "wyższy w oczach" szczyt w prawie tym samym kierunku.
// 2) pickPeak - przy każdym odczycie kompasu: najlepszy szczyt w stożku wokół kierunku
//    12:00 (mały kąt odchylenia, duży kąt wzniesienia), sąsiedzi po bokach i "za nim".
import { distance, bearing, elevationAngle, horizonDistance, angleDiff } from "./geo.js";

export const PICK = {
  rangeM: 100000, // dalej z zegarka i tak nie rozpoznasz szczytu
  minDistM: 150, // szczyt, na którym stoisz, pomijamy
  sectorDeg: 5, // kandydaci wybierani osobno w każdym wycinku 5° kierunku...
  perSector: 6, //   ...najwyżej 6 najbardziej widocznych (żeby wysokie Tatry nie wypchnęły
  //                   z listy niższych, ale bliskich szczytów w innych kierunkach)
  maxCandidates: 432, // 72 wycinki x 6 - tyle liczymy przy każdym odczycie kompasu
  cone: 15, // +- stopnie wokół kierunku 12:00 (kompas zegarka drga o kilka stopni)
  elevWeight: 1.5, // 1° wzniesienia nad oko = 1,5° odchylenia (wyższe/bliższe wygrywają)
  elevMin: -3, // kąty wzniesienia przycinamy do tego zakresu, żeby jeden bliski
  elevMax: 8, //   pagórek nie wygrywał zawsze
  rankDiv: 64, // ranga z bazy (0-255) dodaje do 4° przewagi znanym szczytom
  hideDeg: 1.2, // szczyt w tym samym kierunku za wyższym (w oczach) bliższym jest zasłonięty
  hiddenPenalty: 8,
  behindDeg: 2.5, // "za nim": prawie ten sam kierunek, dalej
  sideMin: 3, // sąsiedzi: od 3° do 60° w bok od wybranego
  sideMax: 60,
  stripHalf: 30, // pasek horyzontu: +-30°
  stripMax: 9,
};

const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

// Jak bardzo szczyt "rzuca się w oczy" (w stopniach odchylenia, które może nadrobić)
export function weight(c, o = PICK) {
  return o.elevWeight * clamp(c.elev, o.elevMin, o.elevMax) + c.rank / o.rankDiv;
}

// peaks: [{ name, lat, lon, ele, rank }], obs: { lat, lon, ele } -> kandydaci posortowani wg kierunku
export function buildCandidates(peaks, obs, o = PICK) {
  const hObs = isFinite(obs.ele) ? obs.ele : 0;
  const horizonObs = horizonDistance(hObs);
  let list = [];
  for (let i = 0; i < peaks.length; i++) {
    const p = peaks[i];
    const d = distance(obs.lat, obs.lon, p.lat, p.lon);
    if (d < o.minDistM || d > o.rangeM) continue;
    if (d > horizonObs + horizonDistance(p.ele)) continue; // za krzywizną Ziemi
    const c = {
      name: p.name,
      ele: p.ele,
      rank: p.rank,
      lat: p.lat,
      lon: p.lon,
      d,
      b: bearing(obs.lat, obs.lon, p.lat, p.lon),
      elev: elevationAngle(hObs, p.ele, d),
      hidden: false,
    };
    c.w = weight(c, o);
    list.push(c);
  }
  if (list.length > o.maxCandidates) {
    list.sort((a, b) => b.w - a.w);
    const taken = {};
    const kept = [];
    for (let i = 0; i < list.length && kept.length < o.maxCandidates; i++) {
      const sector = Math.floor(list[i].b / o.sectorDeg);
      taken[sector] = (taken[sector] || 0) + 1;
      if (taken[sector] <= o.perSector) kept.push(list[i]);
    }
    list = kept;
  }
  // Zasłonięcie: bliższy szczyt w prawie tym samym kierunku, widziany wyżej
  list.sort((a, b) => a.d - b.d);
  for (let i = 1; i < list.length; i++) {
    const c = list[i];
    for (let j = 0; j < i; j++) {
      const n = list[j];
      if (n.elev > c.elev && Math.abs(angleDiff(n.b, c.b)) < o.hideDeg) {
        c.hidden = true;
        break;
      }
    }
  }
  list.sort((a, b) => a.b - b.b);
  return list;
}

function score(c, offset, o) {
  return Math.abs(offset) - c.w + (c.hidden ? o.hiddenPenalty : 0);
}

// Najlepszy kandydat z przesunięciem kątowym w [lo, hi] względem kierunku ref
function bestIn(cands, ref, lo, hi, o, skip) {
  let best = null;
  let bestScore = Infinity;
  let bestOff = 0;
  for (let i = 0; i < cands.length; i++) {
    const c = cands[i];
    if (c === skip) continue;
    const off = angleDiff(c.b, ref);
    if (off < lo || off > hi) continue;
    const s = score(c, lo < 0 && hi > 0 ? off : Math.abs(off) - Math.min(Math.abs(lo), Math.abs(hi)), o);
    if (s < bestScore) {
      bestScore = s;
      best = c;
      bestOff = off;
    }
  }
  return best ? { c: best, off: bestOff } : null;
}

// Wynik dla kierunku heading (stopnie od północy geograficznej):
// { best, offset, behind, left, right } - offset/kąty względem kierunku 12:00 (ujemny = w lewo)
export function pickPeak(cands, heading, o = PICK) {
  const hit = bestIn(cands, heading, -o.cone, o.cone, o, null);
  const ref = hit ? hit.c.b : heading;
  const res = { best: hit ? hit.c : null, offset: hit ? hit.off : 0, behind: null, left: null, right: null };

  if (hit) {
    let far = null;
    for (let i = 0; i < cands.length; i++) {
      const c = cands[i];
      if (c === hit.c || c.d <= hit.c.d + 1000) continue;
      if (Math.abs(angleDiff(c.b, ref)) > o.behindDeg) continue;
      if (!far || c.w > far.w) far = c;
    }
    res.behind = far;
  }
  const l = bestIn(cands, ref, -o.sideMax, -o.sideMin, o, res.best);
  const r = bestIn(cands, ref, o.sideMin, o.sideMax, o, res.best);
  if (l) res.left = { c: l.c, off: angleDiff(l.c.b, heading) };
  if (r) res.right = { c: r.c, off: angleDiff(r.c.b, heading) };
  return res;
}

// Szczyty na pasek horyzontu: [{ c, off }] - do stripMax najbardziej widocznych w +-stripHalf
export function stripPeaks(cands, heading, o = PICK) {
  const out = [];
  for (let i = 0; i < cands.length; i++) {
    const c = cands[i];
    if (c.hidden) continue;
    const off = angleDiff(c.b, heading);
    if (Math.abs(off) <= o.stripHalf) out.push({ c, off });
  }
  out.sort((a, b) => b.c.w - a.c.w);
  return out.slice(0, o.stripMax);
}

// "Babia Góra · 1725 m · 38 km" bez nazwy: "1725 m · 38 km"
export function peakDetails(c, formatDistance) {
  return c.ele + " m · " + formatDistance(c.d);
}
