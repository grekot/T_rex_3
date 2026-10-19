// Dokumentacja Zepp nie mówi, jakiej ścieżki oczekuje IMG dla pliku odebranego przez TransferFile,
// więc próbujemy kilku zapisów; ten, który zadziała, zapamiętujemy (przycisk „ścieżka” na ekranie zdjęcia).
export function srcVariants(photo) {
  const name = photo.fileName || photo.name;
  const list = [];
  if (photo.filePath) list.push(photo.filePath);
  list.push("data://download/" + name, "download/" + name, "/data/download/" + name, name);
  return list.filter((v, i) => v && list.indexOf(v) === i);
}

export function pickSrc(photo, variant) {
  const list = srcVariants(photo);
  return list[((variant % list.length) + list.length) % list.length];
}
