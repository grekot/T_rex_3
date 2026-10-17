// Side Service - działa w aplikacji Zepp na telefonie.
// Loguje się do Firebase (to samo konto co w aplikacjach Powrót i Zakupy na telefonie), wysyła zapisane na zegarku miejsca
// i pobiera miejsca udostępnione przez znajomych. Bez logowania zegarek działa lokalnie.
import { BaseSideService, settingsLib } from "@zeppos/zml/base-side";
import { FIREBASE_CONFIGURED, FIREBASE_API_KEY, FIREBASE_PROJECT_ID } from "../utils/firebase-config";
import {
  signInRequest,
  signUpRequest,
  emailIndexWrites,
  refreshRequest,
  placesQueryRequest,
  commitRequest,
  opWrites,
  commitOutcome,
  parseBody,
  errorOf,
  authErrorMessage,
  isSessionDead,
  decodeQueryResponse,
} from "../utils/firestore";
import { compactPlace, sortPlaces } from "../utils/places";

// Token dostępu trzymamy tylko w pamięci; w ustawieniach zostaje refresh token
let session = null; // { idToken, expiresAt }
// Czy w tej sesji zapisaliśmy już e-mail w książce adresowej (emails/{e-mail})
let emailRegistered = false;

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

// Wpis e-mail -> uid, dzięki któremu inni mogą dodać mnie do znajomych (błędy pomijamy)
async function registerEmail(uid, email, idToken) {
  if (emailRegistered || !uid || !email) return;
  try {
    const r = await call(
      commitRequest(FIREBASE_PROJECT_ID, idToken, emailIndexWrites(FIREBASE_PROJECT_ID, uid, email, Date.now()))
    );
    if (!errorOf(r.status, r.body)) emailRegistered = true;
  } catch (e) {}
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
  emailRegistered = false;
  await registerEmail(data.localId, data.email || email, data.idToken);
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
  await registerEmail(auth.uid, auth.email, session.idToken);
  return { ...auth, idToken: session.idToken };
}

async function fetchPlaces(s) {
  const r = await call(placesQueryRequest(FIREBASE_PROJECT_ID, s.idToken, s.uid));
  const err = apiError(r.status, r.body);
  if (err) throw err;
  return sortPlaces(decodeQueryResponse(r.body).map((doc) => compactPlace(doc, s.uid)));
}

// Wykonuje operacje po kolei i zwraca id potwierdzonych; przy błędzie przerywa (reszta poczeka)
async function applyOps(s, ops) {
  const applied = [];
  for (let i = 0; i < ops.length; i++) {
    let outcome;
    try {
      const writes = opWrites(FIREBASE_PROJECT_ID, ops[i], s.uid, s.email);
      if (!writes.length) {
        outcome = "gone";
      } else {
        const r = await call(commitRequest(FIREBASE_PROJECT_ID, s.idToken, writes));
        outcome = commitOutcome(ops[i], r.status, r.body);
      }
    } catch (e) {
      outcome = "error";
    }
    if (outcome === "applied" || outcome === "gone") {
      applied.push(ops[i].id);
    } else if (outcome === "auth") {
      const err = new Error("UNAUTHENTICATED");
      err.status = 401;
      throw err;
    } else {
      break;
    }
  }
  return applied;
}

async function syncOnce(ops) {
  const s = await ensureSession();
  if (!s) {
    return { ok: false, needsLogin: true, error: settingsLib.getItem("authStatus") || "Nie zalogowano" };
  }
  const applied = ops.length ? await applyOps(s, ops) : [];
  const places = await fetchPlaces(s);
  return { ok: true, places, applied, fetchedAt: Date.now(), email: s.email };
}

async function sync(ops) {
  if (!FIREBASE_CONFIGURED) return { ok: false, error: "Aplikacja bez konfiguracji Firebase" };
  try {
    return await syncOnce(ops);
  } catch (e) {
    // Token mógł wygasnąć wcześniej niż zakładaliśmy - jedna ponowna próba z nowym
    if (e && (e.status === 401 || /UNAUTHENTICATED/.test(String(e.message)))) {
      session = null;
      return syncOnce(ops);
    }
    throw e;
  }
}

AppSideService(
  BaseSideService({
    onInit() {},

    onRequest(req, res) {
      if (req.method === "SYNC") {
        const ops = (req.params && req.params.ops) || [];
        sync(ops)
          .then((result) => res(null, result))
          .catch((e) => res(null, { ok: false, error: String((e && e.message) || e) }));
      } else {
        res(null, { ok: false, error: "Nieznane żądanie: " + req.method });
      }
    },

    // Logowanie z ustawień: od razu wyślij miejsca na zegarek
    onSettingsChange({ key }) {
      if (key !== "loginRequest" || !loginRequested()) return;
      login()
        .then((ok) => (ok ? sync([]) : null))
        .then((result) => {
          if (result) {
            try {
              this.call({ type: "DATA", result });
            } catch (e) {}
          }
        })
        .catch(() => {});
    },

    onRun() {},
    onDestroy() {},
  })
);
