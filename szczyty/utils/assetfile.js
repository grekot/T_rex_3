// Odczyt pliku z assets odporny na różnice firmware'u: kilka sposobów po kolei, każdy
// sprawdzany na nagłówku pliku. Czysta logika (bez @zos), testy w test/assetfile.test.mjs.
//
// Sposób (backend): { name, open() -> uchwyt | rzuca }, uchwyt:
//   { readAt(pozycja, długość) -> Uint8Array | null   - odczyt od pozycji (może być brak),
//     readNext(długość) -> Uint8Array                  - odczyt po kolei od bieżącego miejsca,
//     close() }
// Wynik: { read(pozycja, długość) -> Uint8Array, close(), how } albo { error } z opisem, co
// zawiodło (pokazywany na ekranie, żeby było wiadomo, co poprawić).

const CHUNK = 16384;
const MAX_SIZE = 4 * 1024 * 1024;

function startsWith(b, magic) {
  if (!b || b.length < magic.length) return false;
  for (let i = 0; i < magic.length; i++) if (b[i] !== magic.charCodeAt(i)) return false;
  return true;
}

function safeClose(h) {
  try {
    h.close();
  } catch (e) {}
}

// Odczyt od pozycji działa, jeśli dwa razy z rzędu na pozycji 0 jest nagłówek (gdyby pozycja
// była ignorowana, drugi odczyt dałby bajty spod 32)
function tryPositional(h, magic) {
  if (!h.readAt) return null;
  const a = h.readAt(0, 32);
  if (!startsWith(a, magic)) return "nagłówek " + describe(a);
  const b = h.readAt(0, magic.length);
  if (!startsWith(b, magic)) return "pozycja ignorowana";
  return "";
}

// Cały plik po kawałku do pamięci (~130 KB)
function readAll(h) {
  const parts = [];
  let total = 0;
  for (;;) {
    const part = h.readNext(CHUNK);
    if (!part || !part.length) break;
    parts.push(part);
    total += part.length;
    if (part.length < CHUNK || total > MAX_SIZE) break;
  }
  const all = new Uint8Array(total);
  let at = 0;
  for (const p of parts) {
    all.set(p, at);
    at += p.length;
  }
  return all;
}

function describe(b) {
  if (!b) return "brak";
  if (!b.length) return "pusty";
  let s = "";
  for (let i = 0; i < Math.min(4, b.length); i++) s += (b[i] < 16 ? "0" : "") + b[i].toString(16);
  return s;
}

const msg = (e) => String((e && e.message) || e).slice(0, 40);

export function openVerified(backends, magic) {
  const errors = [];
  for (const be of backends) {
    let h;
    try {
      h = be.open();
    } catch (e) {
      errors.push(be.name + ": " + msg(e));
      continue;
    }
    try {
      const why = tryPositional(h, magic);
      if (why === "") {
        return { read: (p, n) => h.readAt(p, n), close: () => safeClose(h), how: be.name };
      }
      if (why) errors.push(be.name + ": " + why);
    } catch (e) {
      errors.push(be.name + " poz.: " + msg(e));
    }
    safeClose(h);
    // Drugie podejście tym samym sposobem: świeży uchwyt, cały plik do pamięci
    h = null;
    try {
      h = be.open();
      const all = readAll(h);
      safeClose(h);
      if (startsWith(all, magic)) {
        return {
          read: (p, n) => all.subarray(p, Math.min(all.length, p + n)),
          close() {},
          how: be.name + " (całość)",
        };
      }
      errors.push(be.name + " całość: " + describe(all) + " " + all.length + " B");
    } catch (e) {
      if (h) safeClose(h);
      errors.push(be.name + " całość: " + msg(e));
    }
  }
  return { error: errors.join("\n") || "brak sposobu odczytu" };
}
