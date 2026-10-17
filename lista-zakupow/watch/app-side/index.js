// Side Service - działa w aplikacji Zepp na telefonie.
// Loguje się do Firebase (e-mail + hasło z ustawień), pobiera listy z Firestore
// i wykonuje operacje z zegarka (odhaczenia, dodawanie/usuwanie produktów i list).
import { BaseSideService, settingsLib } from "@zeppos/zml/base-side";
import { FIREBASE_CONFIGURED, FIREBASE_API_KEY, FIREBASE_PROJECT_ID } from "../utils/firebase-config";
import {
  signInRequest,
  signUpRequest,
  emailIndexWrites,
  refreshRequest,
  listsQueryRequest,
  itemsRequest,
  commitRequest,
  opWrites,
  commitOutcome,
  parseBody,
  errorOf,
  authErrorMessage,
  isSessionDead,
  decodeQueryResponse,
  decodeListResponse,
} from "../utils/firestore";
import { compactList } from "../utils/shopping";

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
    const r = await call(commitRequest(FIREBASE_PROJECT_ID, idToken, emailIndexWrites(FIREBASE_PROJECT_ID, uid, email, Date.now())));
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
  // Konta sprzed wprowadzenia znajomych też trafią do książki adresowej
  await registerEmail(auth.uid, auth.email, session.idToken);
  return { ...auth, idToken: session.idToken };
}

const FAR = 8640000000000000;

async function fetchLists(s) {
  const r = await call(listsQueryRequest(FIREBASE_PROJECT_ID, s.idToken, s.uid));
  const err = apiError(r.status, r.body);
  if (err) throw err;
  const lists = decodeQueryResponse(r.body).sort((a, b) => (a.createdAt || FAR) - (b.createdAt || FAR));
  return Promise.all(
    lists.map(async (list) => {
      const ri = await call(itemsRequest(FIREBASE_PROJECT_ID, s.idToken, list.id));
      const e = apiError(ri.status, ri.body);
      if (e) throw e;
      return compactList(list, decodeListResponse(ri.body), s.uid);
    })
  );
}

// Reguły sprawdzają członkostwo w liście przy każdym produkcie (get), a Firestore pozwala
// na 20 takich odczytów w jednym commit - usuwamy więc produkty paczkami po 10
const MAX_WRITES = 10;

async function commit(s, op, writes) {
  const r = await call(commitRequest(FIREBASE_PROJECT_ID, s.idToken, writes));
  return commitOutcome(op, r.status, r.body);
}

// Usunięcie listy: najpierw pobieramy jej produkty, potem kasujemy wszystko razem
async function deleteList(s, op) {
  const r = await call(itemsRequest(FIREBASE_PROJECT_ID, s.idToken, op.l));
  const data = parseBody(r.body);
  if (data && data.error) {
    const st = data.error.status;
    if (st === "PERMISSION_DENIED" || st === "NOT_FOUND") return "gone"; // już usunięta
    if (st === "UNAUTHENTICATED" || data.error.code === 401) return "auth";
    return "error";
  }
  const ids = decodeListResponse(r.body).map((d) => d.id);
  while (ids.length > MAX_WRITES) {
    const chunk = ids.splice(0, MAX_WRITES);
    const outcome = await commit(s, op, chunk.map((id) => opWrites(FIREBASE_PROJECT_ID, { t: "delItem", l: op.l, i: id }, s.uid)[0]));
    if (outcome !== "applied") return outcome;
  }
  return commit(s, op, opWrites(FIREBASE_PROJECT_ID, op, s.uid, ids));
}

async function runOp(s, op) {
  if (op.t === "delList") return deleteList(s, op);
  const writes = opWrites(FIREBASE_PROJECT_ID, op, s.uid);
  if (!writes.length) return "gone";
  return commit(s, op, writes);
}

// Wykonuje operacje po kolei i zwraca id potwierdzonych.
// Przy błędzie przerywamy - reszta poczeka (np. produkt nie może trafić na listę, której jeszcze nie ma).
async function applyOps(s, ops) {
  const applied = [];
  for (let i = 0; i < ops.length; i++) {
    let outcome;
    try {
      outcome = await runOp(s, ops[i]);
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
    return {
      ok: false,
      needsLogin: true,
      error: settingsLib.getItem("authStatus") || "Zaloguj się w ustawieniach aplikacji w Zepp",
    };
  }
  const applied = ops.length ? await applyOps(s, ops) : [];
  const lists = await fetchLists(s);
  return { ok: true, lists, applied, fetchedAt: Date.now(), email: s.email };
}

async function sync(ops) {
  if (!FIREBASE_CONFIGURED) {
    return { ok: false, error: "Aplikacja bez konfiguracji Firebase (tools/configure.mjs)" };
  }
  try {
    return await syncOnce(ops);
  } catch (e) {
    // Token mógł wygasnąć wcześniej niż zakładaliśmy - jedna ponowna próba z nowym.
    // Powtórzone operacje są bezpieczne (dodanie istniejącego = "już jest", usunięcie usuniętego = OK).
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

    // Logowanie z ustawień: od razu wyślij listy na zegarek
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
