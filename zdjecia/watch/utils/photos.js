// Lista zdjęć na zegarku: łączenie pomiarów, które przychodzą z dwóch stron
// (parametry pliku i odbiór na zegarku, osobno komunikat „wysłano” z telefonu).

export function mergePhoto(list, photo) {
  const out = list.slice();
  const i = out.findIndex((p) => p.id === photo.id);
  const clean = {};
  Object.keys(photo).forEach((k) => {
    if (photo[k] !== undefined && photo[k] !== null) clean[k] = photo[k];
  });
  if (i < 0) out.push(clean);
  else out[i] = Object.assign({}, out[i], clean);
  return out;
}

// Do pokazania tylko te, które naprawdę doszły na zegarek
export function shownPhotos(list) {
  return list.filter((p) => p.fileName || p.filePath);
}

export function haveIds(list) {
  return shownPhotos(list).map((p) => p.id);
}

export function readParams(params) {
  if (!params) return {};
  if (typeof params === "string") {
    try {
      return JSON.parse(params) || {};
    } catch (e) {
      return {};
    }
  }
  return params;
}
