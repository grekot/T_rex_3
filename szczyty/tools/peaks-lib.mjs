// Obróbka szczytów z OSM: wysokość, nazwa, izolacja, ranga, filtr "co widać z Polski".
// Funkcje są niezależne od zegarka - można ich użyć w innych aplikacjach (np. Korona).
import { distance } from "../utils/geo.js";

// Uproszczony obrys Polski (lat, lon), ~10 km dokładności - wystarcza do bufora "100 km od granicy"
export const POLAND = [
  [53.92, 14.23], [54.17, 15.4], [54.35, 16.2], [54.55, 16.9], [54.79, 17.9], [54.83, 18.35],
  [54.6, 18.8], [54.35, 18.65], [54.38, 19.45], [54.36, 19.63], [54.45, 20.5], [54.4, 21.5],
  [54.36, 22.79], [54.1, 23.35], [53.9, 23.6], [53.5, 23.9], [53.1, 23.9], [52.7, 23.95],
  [52.3, 23.2], [52.07, 23.62], [51.55, 23.55], [51.2, 23.7], [50.85, 24.15], [50.42, 24.0],
  [50.2, 23.6], [49.95, 23.05], [49.78, 22.9], [49.45, 22.7], [49.08, 22.57], [49.25, 22.0],
  [49.4, 21.7], [49.43, 20.95], [49.4, 20.3], [49.18, 20.08], [49.3, 19.8], [49.57, 19.53],
  [49.52, 19.0], [49.52, 18.85], [49.75, 18.63], [49.95, 18.3], [50.1, 17.7], [50.3, 17.4],
  [50.2, 17.1], [50.2, 16.85], [50.2, 16.5], [50.45, 16.2], [50.65, 16.0], [50.73, 15.74],
  [50.87, 14.82], [51.15, 14.98], [51.5, 14.72], [52.0, 14.7], [52.35, 14.55], [52.6, 14.6],
  [52.9, 14.15], [53.25, 14.4], [53.45, 14.25],
];

export function insidePolygon(lat, lon, poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [yi, xi] = poly[i];
    const [yj, xj] = poly[j];
    if (yi > lat !== yj > lat && lon < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

// Odległość punktu od obrysu w km (0 wewnątrz); odcinki liczone w rzucie lokalnym
export function distanceToPolygonKm(lat, lon, poly) {
  if (insidePolygon(lat, lon, poly)) return 0;
  const kx = 111.32 * Math.cos((lat * Math.PI) / 180);
  const ky = 110.57;
  let best = Infinity;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const ax = (poly[j][1] - lon) * kx, ay = (poly[j][0] - lat) * ky;
    const bx = (poly[i][1] - lon) * kx, by = (poly[i][0] - lat) * ky;
    const dx = bx - ax, dy = by - ay;
    const t = Math.max(0, Math.min(1, -(ax * dx + ay * dy) / (dx * dx + dy * dy || 1)));
    best = Math.min(best, Math.hypot(ax + t * dx, ay + t * dy));
  }
  return best;
}

// "1725", "1725 m", "1 725,3", "5660 ft", "~1200" -> metry albo NaN
export function parseEle(raw) {
  if (raw === undefined || raw === null) return NaN;
  const s = String(raw).trim().toLowerCase().replace(/(\d)[\s ](\d{3})\b/g, "$1$2").replace(",", ".");
  const m = s.match(/-?\d+(\.\d+)?/);
  if (!m) return NaN;
  let v = parseFloat(m[0]);
  if (/ft|feet|'/.test(s)) v *= 0.3048;
  return v > -500 && v < 9000 ? v : NaN;
}

const CYRILLIC = /[Ѐ-ӿ]/;

// Transliteracja ukraińska (i rosyjska) na polski zapis: Говерла -> Howerla, Пікуй -> Pikuj
const TRANSLIT = {
  а: "a", б: "b", в: "w", г: "h", ґ: "g", д: "d", е: "e", є: "je", ж: "ż", з: "z", и: "y", і: "i",
  ї: "ji", й: "j", к: "k", л: "l", м: "m", н: "n", о: "o", п: "p", р: "r", с: "s", т: "t", у: "u",
  ф: "f", х: "ch", ц: "c", ч: "cz", ш: "sz", щ: "szcz", ь: "", ю: "ju", я: "ja", ъ: "", ы: "y",
  э: "e", ё: "jo", "’": "", "'": "", "ʼ": "",
};

export function transliterate(s) {
  let out = "";
  for (const ch of s) {
    const low = ch.toLowerCase();
    const t = TRANSLIT[low];
    if (t === undefined) out += ch;
    else out += ch !== low && t ? t[0].toUpperCase() + t.slice(1) : t;
  }
  return out;
}

// Nazwa w wybranym języku (name:pl), potem zwykła. Nazwy cyrylicą (Ukraina) zamieniamy na
// łacińskie: z innego tagu (sk, cs), z części łacińskiej "Vihorlat / Вігорлат" albo
// polską transliteracją (nie angielską z name:en) - font zegarka i czytelnik nie muszą znać cyrylicy.
export function pickName(tags, lang = "pl") {
  let n = (lang && tags["name:" + lang]) || tags.name || "";
  if (CYRILLIC.test(n)) {
    const latin = ["name:sk", "name:cs"].map((k) => tags[k]).find((v) => v && !CYRILLIC.test(v));
    const part = n.split(/\s*\/\s*/).find((v) => v && !CYRILLIC.test(v));
    n = latin || part || transliterate(n);
  }
  return n.replace(/\s+/g, " ").trim();
}

// Węzły OSM -> { id, name, lat, lon, ele, wiki }; bez wysokości odpadają, bez nazwy zostają
// (potrzebne do izolacji), nazwę mają puste
export function normalizePeaks(elements, lang = "pl") {
  const out = [];
  for (const el of elements) {
    if (el.type !== "node" || !el.tags) continue;
    const ele = parseEle(el.tags.ele);
    if (!isFinite(ele)) continue;
    out.push({
      id: el.id,
      name: pickName(el.tags, lang),
      lat: el.lat,
      lon: el.lon,
      ele: Math.round(ele),
      wiki: !!(el.tags.wikidata || el.tags.wikipedia),
      prominence: parseEle(el.tags.prominence),
    });
  }
  return out;
}

// Różnica wysokości, poniżej której dwa szczyty uznajemy za równe (pomiary w OSM różnią się
// o metry: Agata 613,96 m obok Łysicy 613,31 m). Przy remisie "wyższy" jest ten z Wikipedii,
// a gdy oba mają (albo oba nie mają) hasło - żaden, więc zostają oba.
export const TIE_M = 3;

export function isHigher(q, p) {
  const dh = q.ele - p.ele;
  if (Math.abs(dh) <= TIE_M) return q.wiki && !p.wiki;
  return dh > 0;
}

// Izolacja topograficzna (przybliżona): odległość w km do najbliższego wyższego szczytu
// z tej samej bazy, najwyżej capKm. Siatka kubełków 0,1° - kilka sekund dla 100 tys. szczytów.
export function computeIsolation(peaks, capKm = 50) {
  const CELL = 0.1;
  const key = (r, c) => r * 100000 + c;
  const grid = new Map();
  for (const p of peaks) {
    const k = key(Math.floor(p.lat / CELL), Math.floor(p.lon / CELL));
    if (!grid.has(k)) grid.set(k, []);
    grid.get(k).push(p);
  }
  for (const p of peaks) {
    const r0 = Math.floor(p.lat / CELL);
    const c0 = Math.floor(p.lon / CELL);
    const kmPerCellLat = 11.1;
    const kmPerCellLon = 11.1 * Math.cos((p.lat * Math.PI) / 180);
    let best = capKm;
    for (let ring = 0; ; ring++) {
      // poza tym pierścieniem nic bliżej niż best już nie ma
      if ((ring - 1) * Math.min(kmPerCellLat, kmPerCellLon) > best) break;
      for (let dr = -ring; dr <= ring; dr++) {
        for (let dc = -ring; dc <= ring; dc++) {
          if (Math.max(Math.abs(dr), Math.abs(dc)) !== ring) continue;
          const cell = grid.get(key(r0 + dr, c0 + dc));
          if (!cell) continue;
          for (const q of cell) {
            if (q === p || !isHigher(q, p)) continue;
            const d = distance(p.lat, p.lon, q.lat, q.lon) / 1000;
            if (d < best) best = d;
          }
        }
      }
      if (ring * Math.min(kmPerCellLat, kmPerCellLon) > capKm) break;
    }
    p.iso = best;
  }
  return peaks;
}

// Ranga 0-255: izolacja (log), wysokość i to, czy szczyt ma hasło w Wikipedii/Wikidanych
export function rankOf(p) {
  const iso = Math.max(0.05, p.iso);
  const r = 70 * Math.log10(iso * 10) + p.ele / 40 + (p.wiki ? 40 : 0);
  return Math.max(0, Math.min(255, Math.round(r)));
}

// Czy szczyt jest wart pokazania: wystarczająco odosobniony jak na swoją wysokość
// (wysokie góry - wierzchołki gęściej, niziny - tylko wyraźne wzniesienia),
// znane szczyty (Wikipedia) z mniejszym progiem.
export function keepPeak(p, o = {}) {
  const minEle = o.minEle ?? 200;
  if (!p.name || p.ele < minEle) return false;
  if (isFinite(p.prominence) && p.prominence >= (o.minProminence ?? 100)) return true;
  // próg izolacji: 3 km na nizinach, maleje do 0,8 km powyżej 1500 m
  const t = p.ele >= 1500 ? 0.8 : p.ele >= 800 ? 1.5 : 3;
  return p.iso >= (p.wiki ? t / 3 : t);
}

// Całość: elementy OSM -> przefiltrowane szczyty z rangą
export function selectPeaks(elements, o = {}) {
  const lang = o.lang ?? "pl";
  const all = computeIsolation(normalizePeaks(elements, lang), o.isoCapKm ?? 50);
  const maxKm = o.maxKmFromPoland ?? 100;
  const region = o.region === null ? null : o.region || POLAND;
  const out = [];
  for (const p of all) {
    if (!keepPeak(p, o)) continue;
    if (region && distanceToPolygonKm(p.lat, p.lon, region) > maxKm) continue;
    p.rank = rankOf(p);
    out.push(p);
  }
  // Ta sama nazwa i prawie to samo miejsce (dwa węzły jednego szczytu) - zostaje wyższy
  out.sort((a, b) => b.ele - a.ele);
  const kept = [];
  for (const p of out) {
    if (kept.some((q) => q.name === p.name && Math.abs(q.lat - p.lat) < 0.01 && Math.abs(q.lon - p.lon) < 0.015)) continue;
    kept.push(p);
  }
  return kept;
}
