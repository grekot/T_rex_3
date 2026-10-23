// Synchronizacja pomiarów z telefonem (Side Service -> Firestore waga/{uid}, format w waga/SYNC.md).
// Wysyłamy wszystkie wpisy z pliku; Side Service odsyła dni, w których chmura ma nowsze dane
// (poprawki i usunięcia z telefonu) - scalamy je z plikiem, większe t wygrywa.
import { loadData, saveData } from "./store";
import { mergeRemote } from "./weight";

let busy = false;
let again = null; // zapis w trakcie synchronizacji - jeszcze jedna runda po tej

// page = strona z BasePage (ma request).
// done({ ok, changed, needsLogin, notConfigured, offline, error })
export function syncNow(page, done) {
  const finish = done || (() => {});
  if (busy) {
    again = finish;
    return;
  }
  busy = true;
  page
    .request({ method: "SYNC", params: { e: loadData().e }, timeout: 30000 })
    .then((result) => {
      busy = false;
      if (result && result.ok) {
        const remote = {};
        (result.apply || []).forEach((x) => {
          remote[x.d] = { w: x.w, t: x.t };
        });
        // plik czytamy od nowa: użytkownik mógł zapisać pomiar w trakcie
        const r = mergeRemote(loadData(), remote);
        if (r.changed) saveData(r.data);
        finish({ ok: true, changed: r.changed });
      } else {
        finish({
          ok: false,
          needsLogin: !!(result && result.needsLogin),
          notConfigured: !!(result && result.notConfigured),
          error: result && result.error,
        });
      }
      runAgain(page);
    })
    .catch(() => {
      busy = false;
      finish({ ok: false, offline: true });
      runAgain(page);
    });
}

function runAgain(page) {
  if (!again) return;
  const next = again;
  again = null;
  syncNow(page, next);
}
