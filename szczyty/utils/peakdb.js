// Format bazy szczytów assets/gt.r/peaks.bin - odczyt (zegarek i testy) + stałe dla kodera
// w tools/encode.mjs. Plik jest podzielony na kafle, zegarek czyta tylko kafle w zasięgu,
// więc w pamięci nigdy nie ma całej bazy.
//
// Wszystko little-endian:
//   nagłówek 32 B: "SZCZ", u8 wersja, u8 0, i16 lat0*100, i16 lon0*100, u16 kafel*100,
//                  u8 wiersze, u8 kolumny, u16 0, u32 data RRRRMMDD, u32 liczba szczytów,
//                  u32 początek indeksu, u32 początek danych
//   indeks: (wiersze*kolumny + 1) x u32 - początek kafla w pliku (kafel i = [off[i], off[i+1]) )
//   kafel: rekordy po kolei: u16 dlat, u16 dlon (0..65535 = cały kafel), u16 wysokość m,
//          u8 ranga, u8 długość nazwy, nazwa w UTF-8

export const MAGIC = "SZCZ";
export const VERSION = 1;
export const HEADER_SIZE = 32;
export const RECORD_FIXED = 8;
export const COORD_MAX = 65535;

const u16 = (b, i) => b[i] | (b[i + 1] << 8);
const i16 = (b, i) => {
  const v = u16(b, i);
  return v & 0x8000 ? v - 0x10000 : v;
};
const u32 = (b, i) => (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16)) + b[i + 3] * 0x1000000;

// Zegarek nie ma TextDecoder - własny dekoder UTF-8 (1-4 bajty, polskie/czeskie/słowackie znaki)
export function utf8Decode(b, start, len) {
  let s = "";
  const end = start + len;
  let i = start;
  while (i < end) {
    const c = b[i++];
    let cp;
    if (c < 0x80) cp = c;
    else if (c < 0xe0) cp = ((c & 0x1f) << 6) | (b[i++] & 0x3f);
    else if (c < 0xf0) {
      cp = ((c & 0x0f) << 12) | ((b[i] & 0x3f) << 6) | (b[i + 1] & 0x3f);
      i += 2;
    } else {
      cp = ((c & 0x07) << 18) | ((b[i] & 0x3f) << 12) | ((b[i + 1] & 0x3f) << 6) | (b[i + 2] & 0x3f);
      i += 3;
    }
    if (cp < 0x10000) s += String.fromCharCode(cp);
    else {
      cp -= 0x10000;
      s += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff));
    }
  }
  return s;
}

// Nagłówek z pierwszych HEADER_SIZE bajtów; null, gdy to nie nasz plik
export function parseHeader(b) {
  if (!b || b.length < HEADER_SIZE) return null;
  if (String.fromCharCode(b[0], b[1], b[2], b[3]) !== MAGIC || b[4] !== VERSION) return null;
  return {
    lat0: i16(b, 6) / 100,
    lon0: i16(b, 8) / 100,
    size: u16(b, 10) / 100,
    rows: b[12],
    cols: b[13],
    date: u32(b, 16),
    count: u32(b, 20),
    indexAt: u32(b, 24),
    dataAt: u32(b, 28),
  };
}

export function indexLength(h) {
  return (h.rows * h.cols + 1) * 4;
}

// Indeks kafli (bajty spod h.indexAt) -> tablica początków
export function parseIndex(h, b) {
  const n = h.rows * h.cols + 1;
  const off = new Array(n);
  for (let i = 0; i < n; i++) off[i] = u32(b, i * 4);
  return off;
}

// Numery kafli, które mogą zawierać szczyty w promieniu rangeKm od punktu
export function tilesInRange(h, lat, lon, rangeKm) {
  const dLat = rangeKm / 111.2;
  const cosLat = Math.max(0.2, Math.cos((Math.max(Math.abs(lat - dLat), Math.abs(lat + dLat)) * Math.PI) / 180));
  const dLon = rangeKm / (111.2 * cosLat);
  const r0 = Math.max(0, Math.floor((lat - dLat - h.lat0) / h.size));
  const r1 = Math.min(h.rows - 1, Math.floor((lat + dLat - h.lat0) / h.size));
  const c0 = Math.max(0, Math.floor((lon - dLon - h.lon0) / h.size));
  const c1 = Math.min(h.cols - 1, Math.floor((lon + dLon - h.lon0) / h.size));
  const out = [];
  for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) out.push(r * h.cols + c);
  return out;
}

export function tileOrigin(h, tile) {
  const r = Math.floor(tile / h.cols);
  const c = tile % h.cols;
  return { lat: h.lat0 + r * h.size, lon: h.lon0 + c * h.size };
}

// Bajty jednego kafla -> szczyty { name, lat, lon, ele, rank }; push do `out`
export function decodeTile(h, tile, b, out) {
  const o = tileOrigin(h, tile);
  const k = h.size / COORD_MAX;
  let i = 0;
  while (i + RECORD_FIXED <= b.length) {
    const len = b[i + 7];
    out.push({
      name: utf8Decode(b, i + RECORD_FIXED, len),
      lat: o.lat + u16(b, i) * k,
      lon: o.lon + u16(b, i + 2) * k,
      ele: u16(b, i + 4),
      rank: b[i + 6],
    });
    i += RECORD_FIXED + len;
  }
  return out;
}

// Szczyty w zasięgu z pliku dostępnego przez read(pozycja, długość) -> Uint8Array;
// każdy kafel to jeden odczyt.
export function loadPeaksNear(read, lat, lon, rangeKm) {
  const h = parseHeader(read(0, HEADER_SIZE));
  if (!h) return null;
  const off = parseIndex(h, read(h.indexAt, indexLength(h)));
  const peaks = [];
  const tiles = tilesInRange(h, lat, lon, rangeKm);
  for (const t of tiles) {
    const len = off[t + 1] - off[t];
    if (len > 0) decodeTile(h, t, read(off[t], len), peaks);
  }
  return { header: h, peaks, tiles: tiles.length };
}

// 20261020 -> "20.10.2026"
export function formatDbDate(n) {
  const s = String(n);
  if (s.length !== 8) return "?";
  return s.slice(6, 8) + "." + s.slice(4, 6) + "." + s.slice(0, 4);
}
