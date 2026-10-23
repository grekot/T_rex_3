// Side Service - działa w aplikacji Zepp na telefonie.
// Loguje się do Firebase (to samo konto co w aplikacjach Waga, Zakupy, Powrót i Na szczycie na telefonie)
// i scala pomiary z zegarka z dokumentem waga/{uid} (format: waga/SYNC.md). Bez logowania zegarek
// działa lokalnie.
import { BaseSideService, settingsLib } from "@zeppos/zml/base-side";
import { FIREBASE_CONFIGURED, FIREBASE_API_KEY, FIREBASE_PROJECT_ID } from "../utils/firebase-config";
import {
  signInRequest,
  signUpRequest,
  refreshRequest,
  commitRequest,
  wagaWrites,
  wagaGetRequest,
  decodeWagaDoc,
  parseBody,
  errorOf,
  authErrorMessage,
  isSessionDead,
} from "../utils/firestore";
import { syncPlan } from "../utils/weight";

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

// Zegarek wysyła wszystkie swoje wpisy (e: [{ d, w, t }], z nagrobkami). Pobieramy dokument,
// scalamy (większe t wygrywa), wysyłamy dni, w których zegarek ma nowsze dane, a zegarkowi
// oddajemy dni, w których nowsza jest chmura (apply) - zegarek scala je u siebie.
async function syncOnce(params) {
  const s = await ensureSession();
  if (!s) {
    return { ok: false, needsLogin: true, error: settingsLib.getItem("authStatus") || "Nie zalogowano" };
  }
  const r = await call(wagaGetRequest(FIREBASE_PROJECT_ID, s.idToken, s.uid));
  const err = apiError(r.status, r.body);
  if (err) throw err;
  const remote = decodeWagaDoc(r.body);
  if (!remote) throw new Error("Nieczytelna odpowiedź Firestore");

  const plan = syncPlan(params.e, remote.e);
  if (plan.push.length) {
    const c = await call(commitRequest(FIREBASE_PROJECT_ID, s.idToken, wagaWrites(FIREBASE_PROJECT_ID, s.uid, plan.push, Date.now())));
    const cErr = apiError(c.status, c.body);
    if (cErr) throw cErr;
  }
  return { ok: true, email: s.email, pushed: plan.push.length, apply: plan.apply, goal: remote.goal };
}

async function sync(params) {
  if (!FIREBASE_CONFIGURED) return { ok: false, notConfigured: true, error: "Aplikacja bez konfiguracji Firebase" };
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

    // Logowanie z ustawień: dajemy znać zegarkowi, żeby od razu zsynchronizował
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
