// Koder pliku peaks.bin - format opisany w utils/peakdb.js (tam też dekoder).
import { MAGIC, VERSION, HEADER_SIZE, RECORD_FIXED, COORD_MAX } from "../utils/peakdb.js";

// peaks: [{ name, lat, lon, ele, rank }]; grid: { lat0, lon0, size, rows, cols }; date: RRRRMMDD
export function encodeDb(peaks, grid, date) {
  const { lat0, lon0, size, rows, cols } = grid;
  const tiles = Array.from({ length: rows * cols }, () => []);
  const enc = new TextEncoder();
  let count = 0;
  for (const p of peaks) {
    const r = Math.floor((p.lat - lat0) / size);
    const c = Math.floor((p.lon - lon0) / size);
    if (r < 0 || r >= rows || c < 0 || c >= cols) continue;
    let name = enc.encode(p.name);
    if (name.length > 255) name = enc.encode(p.name.slice(0, 80));
    const rec = new Uint8Array(RECORD_FIXED + name.length);
    const dlat = Math.round(((p.lat - (lat0 + r * size)) / size) * COORD_MAX);
    const dlon = Math.round(((p.lon - (lon0 + c * size)) / size) * COORD_MAX);
    const ele = Math.max(0, Math.min(65535, Math.round(p.ele)));
    const rank = Math.max(0, Math.min(255, Math.round(p.rank || 0)));
    rec.set([dlat & 255, dlat >> 8, dlon & 255, dlon >> 8, ele & 255, ele >> 8, rank, name.length]);
    rec.set(name, RECORD_FIXED);
    tiles[r * cols + c].push(rec);
    count++;
  }
  const indexLen = (rows * cols + 1) * 4;
  const dataAt = HEADER_SIZE + indexLen;
  const total = dataAt + tiles.reduce((s, t) => s + t.reduce((a, r) => a + r.length, 0), 0);
  const out = new Uint8Array(total);
  const dv = new DataView(out.buffer);
  for (let i = 0; i < 4; i++) out[i] = MAGIC.charCodeAt(i);
  out[4] = VERSION;
  dv.setInt16(6, Math.round(lat0 * 100), true);
  dv.setInt16(8, Math.round(lon0 * 100), true);
  dv.setUint16(10, Math.round(size * 100), true);
  out[12] = rows;
  out[13] = cols;
  dv.setUint32(16, date, true);
  dv.setUint32(20, count, true);
  dv.setUint32(24, HEADER_SIZE, true);
  dv.setUint32(28, dataAt, true);
  let pos = dataAt;
  tiles.forEach((t, i) => {
    dv.setUint32(HEADER_SIZE + i * 4, pos, true);
    for (const rec of t) {
      out.set(rec, pos);
      pos += rec.length;
    }
  });
  dv.setUint32(HEADER_SIZE + tiles.length * 4, pos, true);
  return out;
}
