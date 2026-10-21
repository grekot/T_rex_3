// Wysyłanie zdobyć do telefonu (Side Service -> Firestore korona/{uid}, format w korona/SYNC.md).
// Zegarek jest źródłem prawdy: wysyłamy cały stan, gdy coś się zmieniło. Po ponownej instalacji
// (pusto i nigdy nie synchronizowano) Side Service zwraca zapis z chmury i go przywracamy.
import { loadClimbs, loadCustom, stamp, isDirty, wasSynced, restore, setSynced } from "./store";

let busy = false;

// page = strona z BasePage (ma request). done({ ok, restored, needsLogin, offline, error })
export function syncNow(page, done) {
  const finish = done || (() => {});
  if (busy) return finish({ ok: false, busy: true });
  const climbs = loadClimbs();
  const custom = loadCustom();
  const empty = !Object.keys(climbs).length && !Object.keys(custom).length;
  const fresh = empty && !wasSynced();
  if (!fresh && !isDirty()) return finish({ ok: true, nothing: true });
  const sent = stamp();
  busy = true;
  page
    .request({ method: "SYNC", params: { climbs, custom, fresh }, timeout: 30000 })
    .then((result) => {
      busy = false;
      if (result && result.ok) {
        if (result.restore) restore(result.restore);
        setSynced(result.restore ? stamp() : sent);
        finish({ ok: true, restored: !!result.restore });
      } else {
        finish({ ok: false, needsLogin: !!(result && result.needsLogin), error: result && result.error });
      }
    })
    .catch(() => {
      busy = false;
      finish({ ok: false, offline: true });
    });
}
