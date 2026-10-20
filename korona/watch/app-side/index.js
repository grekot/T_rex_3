// Side Service - działa w aplikacji Zepp na telefonie.
// Loguje się do Firebase (to samo konto co w aplikacjach Korona, Powrót i Zakupy na telefonie) i zapisuje
// zdobyte szczyty z zegarka w dokumencie korona/{uid} (format: korona/SYNC.md). Bez logowania zegarek
// działa lokalnie.
import { BaseSideService, settingsLib } from "@zeppos/zml/base-side";
import { FIREBASE_CONFIGURED, FIREBASE_API_KEY, FIREBASE_PROJECT_ID } from "../utils/firebase-config";
import {
  signInRequest,
  signUpRequest,
  refreshRequest,
  commitRequest,
  koronaWrites,
  koronaGetRequest,
  decodeKoronaDoc,
  parseBody,
  errorOf,
  authErrorMessage,
  isSessionDead,
} from "../utils/firestore";

// Token dostępu trzymamy tylko w pamięci; w ustawieniach zostaje refresh token
let session = null; // { idToken, expiresAt }

function readAuth() {
  try {
    return JSON.parse(settingsLib.getItem("auth") || "null");
  } catch (e) {
    return null;
  }
}

function setStatus(text) {
  settingsLib.setItem("authStatus", text);
}

async function call(request) {
  const res = await fetch(request);
  return { status: res.status || 0, body: res.body };
}

function apiError(status, body) {
  const message = errorOf(status, body);
  if (!message) return null;
  const err = new Error(message);
  err.status = status;
  return err;
}

function loginRequested() {
  const req = settingsLib.getItem("loginRequest");
  return !!req && req !== settingsLib.getItem("loginHandled");
}

// Logowanie albo założenie konta (gdy w ustawieniach wybrano "Załóż konto")
async function login() {
  settingsLib.setItem("loginHandled", settingsLib.getItem("loginRequest") || "");
  const signUp = settingsLib.getItem("loginMode") === "signup";
  const email = String(settingsLib.getItem("email") || "").trim();
  const password = String(settingsLib.getItem("password") || "");
  if (!email || !password) {
    setStatus("Wpisz e-mail i hasło");
    return false;
  }
  setStatus(signUp ? "Zakładanie konta..." : "Logowanie...");
  let r;
  try {
    r = await call((signUp ? signUpRequest : signInRequest)(FIREBASE_API_KEY, email, password));
  } catch (e) {
    setStatus("Brak internetu - spróbuj ponownie");
    return false;
  }
  // Hasło jest potrzebne tylko do tej jednej próby - nie przechowujemy go
  settingsLib.removeItem("password");
  const err = errorOf(r.status, r.body);
  if (err) {
    setStatus("Błąd: " + authErrorMessage(err));
    return false;
  }
  const data = parseBody(r.body) || {};
  settingsLib.setItem(
    "auth",
    JSON.stringify({ uid: data.localId, email: data.email || email, refreshToken: data.refreshToken })
  );
  session = { idToken: data.idToken, expiresAt: Date.now() + (Number(data.expiresIn) || 3600) * 1000 - 60000 };
  settingsLib.setItem("loginMode", "login");
  setStatus((signUp ? "Konto założone. " : "") + "Zalogowano jako " + (data.email || email));
  return true;
}

function logout(reason) {
  session = null;
  settingsLib.removeItem("auth");
  setStatus(reason || "Wylogowano");
}

// Zwraca { uid, email, idToken } albo null, gdy użytkownik nie jest zalogowany
async function ensureSession() {
  if (loginRequested()) await login();
  const auth = readAuth();
  if (!auth || !auth.refreshToken) return null;
  if (session && session.expiresAt > Date.now()) return { ...auth, idToken: session.idToken };

  const r = await call(refreshRequest(FIREBASE_API_KEY, auth.refreshToken));
  const err = errorOf(r.status, r.body);
  if (err) {
    if (isSessionDead(err)) {
      logout(authErrorMessage(err));
      return null;
    }
    throw new Error(authErrorMessage(err));
  }
  const data = parseBody(r.body) || {};
  if (data.refresh_token && data.refresh_token !== auth.refreshToken) {
    settingsLib.setItem("auth", JSON.stringify({ ...auth, refreshToken: data.refresh_token }));
  }
  session = { idToken: data.id_token, expiresAt: Date.now() + (Number(data.expires_in) || 3600) * 1000 - 60000 };
  return { ...auth, idToken: session.idToken };
}

// Zegarek wysyła cały stan ({ climbs, custom }). fresh = na zegarku pusto i nigdy nie było
// synchronizacji (np. po ponownej instalacji) - wtedy zamiast nadpisywać zwracamy zapis z chmury.
async function syncOnce(params) {
  const s = await ensureSession();
  if (!s) {
    return { ok: false, needsLogin: true, error: settingsLib.getItem("authStatus") || "Nie zalogowano" };
  }
  if (params.fresh) {
    const r = await call(koronaGetRequest(FIREBASE_PROJECT_ID, s.idToken, s.uid));
    const err = apiError(r.status, r.body);
    if (err) throw err;
    const remote = decodeKoronaDoc(r.body);
    if (remote && (Object.keys(remote.climbs).length || Object.keys(remote.custom).length)) {
      return { ok: true, restore: remote, email: s.email };
    }
  }
  const r = await call(
    commitRequest(FIREBASE_PROJECT_ID, s.idToken, koronaWrites(FIREBASE_PROJECT_ID, s.uid, params.climbs, params.custom, Date.now()))
  );
  const err = apiError(r.status, r.body);
  if (err) throw err;
  return { ok: true, email: s.email, savedAt: Date.now() };
}

async function sync(params) {
  if (!FIREBASE_CONFIGURED) return { ok: false, error: "Aplikacja bez konfiguracji Firebase" };
  try {
    return await syncOnce(params);
  } catch (e) {
    // Token mógł wygasnąć wcześniej niż zakładaliśmy - jedna ponowna próba z nowym
    if (e && (e.status === 401 || /UNAUTHENTICATED/.test(String(e.message)))) {
      session = null;
      return syncOnce(params);
    }
    throw e;
  }
}

AppSideService(
  BaseSideService({
    onInit() {},

    onRequest(req, res) {
      if (req.method === "SYNC") {
        sync(req.params || {})
          .then((result) => res(null, result))
          .catch((e) => res(null, { ok: false, error: String((e && e.message) || e) }));
      } else {
        res(null, { ok: false, error: "Nieznane żądanie: " + req.method });
      }
    },

    // Logowanie z ustawień: zegarek wyśle stan przy następnej synchronizacji - dajemy mu znać
    onSettingsChange({ key }) {
      if (key !== "loginRequest" || !loginRequested()) return;
      login()
        .then((ok) => {
          if (ok) {
            try {
              this.call({ type: "LOGGED_IN" });
            } catch (e) {}
          }
        })
        .catch(() => {});
    },

    onRun() {},
    onDestroy() {},
  })
);
