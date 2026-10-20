// Most lokalny: aplikacja „Zdjęcia” na telefonie udostępnia listę zdjęć i pliki PNG pod 127.0.0.1,
// a Side Service w aplikacji Zepp (na tym samym telefonie) je stamtąd pobiera.
export const BRIDGE_PORT = 8765;
export const BRIDGE_URL = "http://127.0.0.1:" + BRIDGE_PORT;

// Obrazek z internetu do sprawdzenia samego łańcucha pobierz → konwertuj → prześlij (bez mostu)
export const TEST_IMAGE_URL = "https://docs.zepp.com/img/logo.png";
export const TEST_IMAGE_ID = "test_internet";

const ID_RE = /^[A-Za-z0-9_-]{1,40}$/;

export function parseManifest(body) {
  const data = typeof body === "string" ? JSON.parse(body) : body;
  if (!data || !Array.isArray(data.photos)) throw new Error("telefon zwrócił złą listę zdjęć");
  return data.photos
    .filter((p) => p && typeof p.id === "string" && ID_RE.test(p.id))
    .map((p) => ({
      id: p.id,
      size: Number(p.size) || 0,
      taken: Number(p.taken) || 0,
      caption: typeof p.caption === "string" ? p.caption.slice(0, 40) : "",
    }));
}

// Pobieramy tylko zdjęcia, których zegarek jeszcze nie ma; max > 0 = najwyżej tyle naraz
// (przy samoczynnym wyskoczeniu zdjęcia dociągamy po trochu), w kolejności puli telefonu (najlepsze najpierw)
export function photosToFetch(photos, haveIds, max) {
  const have = {};
  (haveIds || []).forEach((id) => (have[id] = true));
  const todo = photos.filter((p) => !have[p.id]);
  return max > 0 ? todo.slice(0, max) : todo;
}

// Zdjęcia do skasowania: tych nie ma już w puli telefonu. Kasujemy tylko nadmiar ponad wielkość puli,
// najstarsze odebrane najpierw - przy dociąganiu po trochu stare znikają dopiero, gdy przyjdą następcy.
// Pusta pula telefonu (np. błąd) niczego nie kasuje.
export function staleToDelete(watchPhotos, poolIds) {
  const pool = poolIds || [];
  if (!pool.length) return [];
  const inPool = {};
  pool.forEach((id) => (inPool[id] = true));
  const extra = watchPhotos.length - pool.length;
  if (extra <= 0) return [];
  return watchPhotos
    .filter((p) => !inPool[p.id])
    .sort((a, b) => (a.rx || 0) - (b.rx || 0))
    .slice(0, extra)
    .map((p) => p.id);
}

export function watchFileName(id) {
  return "zd_" + id + ".png";
}

export function photoUrl(id) {
  return BRIDGE_URL + "/p/" + id + ".png";
}
