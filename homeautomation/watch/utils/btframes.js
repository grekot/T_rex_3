// Ramki zegarek ↔ hub przez węzeł btnode (API.md pkt 15.2) - bez API zegarka, testy w test/btframes.test.mjs
// na wektorach z SmartTermostatOLED/docs/BTNODE_GATT_WEKTORY.md (te same bajty sprawdza hub).
// Każda ramka <= 20 B, liczby big-endian, MAC = pierwsze 8 B HMAC-SHA256(klucz 32 B, wcześniejsze bajty ramki).
import { hmacSha256 } from "./sha256.js";

export const VER = 1;
export const T_COMMAND = 0x01;
export const T_STATE = 0x02;
export const T_ACK = 0x81;
export const T_PART = 0x82;
export const T_END = 0x83;
export const MAC_LEN = 8;
export const MAX_COUNT = 32; // punktów w jednym odczycie stanu

// Wyniki potwierdzenia
export const R_OK = 0;
export const R_MAC = 1; // zły MAC / nieznany slot
export const R_FORBIDDEN = 2;
export const R_COUNTER = 3; // licznik za mały - w polu wartość ostatni licznik huba
export const R_CFGVER = 4; // lista punktów w hubie inna (zegarek pobiera ją przez telefon)
export const R_OFFLINE = 5; // urządzenie nie odpowiedziało w 2 s
export const R_VALUE = 6;

// Status punktu w stanie i flagi ramki 0x83
export const S_ONLINE = 0x01;
export const S_NO_VALUE = 0x02;
export const F_CLOUD = 0x01;
export const F_CFGVER = 0x02;

const put32 = (a, v) => a.push((v >>> 24) & 0xff, (v >>> 16) & 0xff, (v >>> 8) & 0xff, v & 0xff);
const get32 = (f, i) => ((f[i] << 24) | (f[i + 1] << 16) | (f[i + 2] << 8) | f[i + 3]) | 0; // int32 ze znakiem
const getU32 = (f, i) => get32(f, i) >>> 0;

function mac(key, bytes) {
  return Array.prototype.slice.call(hmacSha256(key, bytes), 0, MAC_LEN);
}

function macEqual(key, bytes, got) {
  const want = mac(key, bytes);
  let diff = 0;
  for (let i = 0; i < MAC_LEN; i++) diff |= want[i] ^ got[i];
  return diff === 0;
}

function header(type, slot, counter) {
  const a = [VER, type, slot & 0xff];
  put32(a, counter >>> 0);
  return a;
}

function signed(key, a) {
  return Uint8Array.from(a.concat(mac(key, a)));
}

// 0x01 polecenie: punkt (indeks w liście) i wartość int32 -> 20 B
export function commandFrame(key, slot, counter, index, value) {
  const a = header(T_COMMAND, slot, counter);
  a.push(index & 0xff);
  put32(a, value | 0);
  return signed(key, a);
}

// 0x02 odczyt stanu punktów od..od+ile-1 -> 19 B
export function stateFrame(key, slot, counter, cfgVer, from, count) {
  const a = header(T_STATE, slot, counter);
  a.push((cfgVer >>> 8) & 0xff, cfgVer & 0xff, from & 0xff, count & 0xff);
  return signed(key, a);
}

// Długość 0x81: ver, typ, slot, licznik (4), wynik, wartość (4), MAC (8) = 20 B - bez indeksu, punkt wynika
// z licznika zapytania (API.md 15.2 od 2026-11-03, wektory w docs/BTNODE_GATT_WEKTORY.md).
export const ACK_LEN = 20;

// 0x81 -> { counter, result, value } albo null (zła ramka, inny slot, zły MAC)
export function decodeAck(key, slot, f) {
  if (!f || f.length !== ACK_LEN || f[0] !== VER || f[1] !== T_ACK || f[2] !== (slot & 0xff)) return null;
  const body = ACK_LEN - MAC_LEN;
  if (!macEqual(key, Array.prototype.slice.call(f, 0, body), Array.prototype.slice.call(f, body))) return null;
  return { counter: getU32(f, 3), result: f[7], value: get32(f, 8) };
}

// Odpowiedź na 0x02: części 0x82 (po kolei) + 0x83. -> { counter, cfgVer, flags, points: [{status, value}] } albo null
export function decodeState(key, slot, frames) {
  if (!frames || !frames.length) return null;
  const end = frames[frames.length - 1];
  if (!end || end.length !== 19 || end[0] !== VER || end[1] !== T_END || end[2] !== (slot & 0xff)) return null;
  if (end[7] !== frames.length - 1) return null;
  let signedBytes = [];
  let stream = [];
  for (let i = 0; i + 1 < frames.length; i++) {
    const f = frames[i];
    if (!f || f.length < 5 || f[0] !== VER || f[1] !== T_PART || f[2] !== (slot & 0xff) || f[3] !== i) return null;
    const bytes = Array.prototype.slice.call(f);
    signedBytes = signedBytes.concat(bytes);
    stream = stream.concat(bytes.slice(4));
  }
  const endBytes = Array.prototype.slice.call(end);
  signedBytes = signedBytes.concat(endBytes.slice(0, 19 - MAC_LEN));
  if (!macEqual(key, signedBytes, endBytes.slice(19 - MAC_LEN))) return null;
  if (stream.length % 5) return null;
  const points = [];
  for (let off = 0; off < stream.length; off += 5) points.push({ status: stream[off], value: get32(stream, off + 1) });
  return { counter: getU32(endBytes, 3), cfgVer: (end[8] << 8) | end[9], flags: end[10], points };
}

// Rodzaj ramki od huba (do składania odpowiedzi stanu)
export function frameType(f) {
  return f && f.length >= 2 && f[0] === VER ? f[1] : null;
}
