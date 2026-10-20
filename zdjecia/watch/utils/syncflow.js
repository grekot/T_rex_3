// Odbiór zdjęć z telefonu i porządki po synchronizacji - wspólne dla panelu i samoczynnie
// wyskakującego zdjęcia.
import { savePhoto, loadPhotos, removePhotos } from "./store.js";
import { readParams, shownPhotos } from "./photos.js";
import { staleToDelete } from "./sync.js";

// Plik przysłany przez Side Service (TransferFile); rx = kiedy doszedł (świeże zdjęcia wyskakują pierwsze)
export function receiveFile(file, onSaved, onError) {
  const started = Date.now();
  const params = readParams(file.params);
  let handled = false;
  const done = () => {
    if (handled) return;
    handled = true;
    const now = Date.now();
    savePhoto({
      ...params,
      id: params.id || file.fileName,
      fileName: file.fileName,
      filePath: file.filePath,
      rxMs: now - started,
      rx: now,
    });
    if (onSaved) onSaved(params.id);
  };
  file.on("change", (ev) => {
    const state = ev && ev.data ? ev.data.readyState : file.readyState;
    if (state === "transferred") done();
    else if ((state === "error" || state === "canceled") && onError) onError(params.id || file.fileName, state);
  });
  if (file.readyState === "transferred") done();
}

// Po synchronizacji: kasuje zdjęcia, które wypadły z puli telefonu (tylko nadmiar ponad wielkość puli)
export function cleanupAfterSync(poolIds) {
  return removePhotos(staleToDelete(shownPhotos(loadPhotos()), poolIds));
}
