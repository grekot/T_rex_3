// Side Service - działa w aplikacji Zepp na telefonie.
// Loguje się do Firebase (to samo konto co urządzenia domu i aplikacje HomeAutomation, Zakupy, Na szczycie na telefonie)
// i na prośbę zegarka zgłasza zegarek, czyta wybrany dom, pulpit zegarka i stan urządzeń z Realtime Database
// albo wysyła polecenie z "by": uid (SmartTermostatOLED/docs/API.md, pkt 8, 12, 13a). Sam z siebie nic nie robi - zegarek pyta co ~5 s,
// tylko gdy aplikacja jest na nim otwarta.
import { BaseSideService, settingsLib } from "@zeppos/zml/base-side";
import { FIREBASE_CONFIGURED, FIREBASE_API_KEY, FIREBASE_DB_URL } from "../utils/firebase-config";
import {
  signInRequest,
  refreshRequest,
  parseBody,
  errorOf,
  authErrorMessage,
  isSessionDead,
  isTokenRejected,
} from "../utils/firebase";
import { poll, pollHome, pollAck, send, registerWatch, newCache } from "../utils/cloud";

// Token dostępu trzymamy tylko w pamięci; w ustawieniach zostaje refresh token
let session = null; // { idToken, expiresAt }
const cache = newCache();

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

// Żądanie do bazy: sparsowana odpowiedź albo wyjątek z kodem HTTP
async function fetchJson(request) {
  const r = await call(request);
  const message = errorOf(r.status, r.body);
  if (message) {
    const err = new Error(message);
    err.status = r.status;
    throw err;
  }
  return parseBody(r.body);
}

function loginRequested() {
  const req = settingsLib.getItem("loginRequest");
  return !!req && req !== settingsLib.getItem("loginHandled");
}

async function login() {
  settingsLib.setItem("loginHandled", settingsLib.getItem("loginRequest") || "");
  const email = String(settingsLib.getItem("email") || "").trim();
  const password = String(settingsLib.getItem("password") || "");
  if (!email || !password) {
    setStatus("Wpisz e-mail i hasło");
    return false;
  }
  setStatus("Logowanie...");
  let r;
  try {
    r = await call(signInRequest(FIREBASE_API_KEY, email, password));
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
  cache.uid = null;
  setStatus("Zalogowano jako " + (data.email || email));
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
  if (!auth || !auth.refreshToken) {
    session = null;
    return null;
  }
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

async function withSession(action) {
  if (!FIREBASE_CONFIGURED) return { ok: false, notConfigured: true, error: "Brak konfiguracji" };
  const once = async () => {
    const s = await ensureSession();
    if (!s) return { ok: false, needsLogin: true, error: settingsLib.getItem("authStatus") || "Nie zalogowano" };
    return action({ fetchJson, db: FIREBASE_DB_URL, token: s.idToken, uid: s.uid });
  };
  try {
    return await once();
  } catch (e) {
    // Token mógł wygasnąć wcześniej niż zakładaliśmy - jedna ponowna próba z nowym
    if (e && isTokenRejected(e.status, e.message)) {
      session = null;
      return once();
    }
    throw e;
  }
}

// Lista domów osoby trafia do ustawień w Zepp (wybór domu, gdy jest ich kilka)
function publishHomes(homes) {
  const text = JSON.stringify(homes || []);
  if (settingsLib.getItem("homes") !== text) settingsLib.setItem("homes", text);
}

function handle(req) {
  const p = req.params || {};
  if (req.method === "HOME") {
    const wantedHome = settingsLib.getItem("homeId") || null;
    const watchId = p.watch ? String(p.watch) : null;
    const screen = p.screen && typeof p.screen === "object" ? p.screen : null;
    return withSession((ctx) => pollHome({ ...ctx, wantedHome, watchId, screen, pending: p.pending || null, cache, now: Date.now() })).then((r) => {
      if (r && r.ok) publishHomes(r.homes);
      return r;
    });
  }
  // Zegarek zgłasza się przy każdym uruchomieniu (model, ekran) - telefon układa pod niego pulpit
  if (req.method === "REGISTER") {
    return withSession((ctx) => registerWatch({ ...ctx, info: p.info, appVersion: p.app }));
  }
  // Szybkie potwierdzenie polecenia z pulpitu (zegarek pyta co ~1 s, aż przyjdzie lastCommand)
  if (req.method === "ACK") {
    if (!p.home || !p.id || !p.key) return Promise.resolve({ ok: false, error: "Złe żądanie" });
    return withSession((ctx) =>
      pollAck({ ...ctx, homeId: p.home, id: p.id, key: p.key, type: p.type || null, points: p.points || [], now: Date.now() })
    );
  }
  if (req.method === "POLL") {
    if (!p.home || !p.id) return Promise.resolve({ ok: false, error: "Brak urządzenia" });
    return withSession((ctx) => poll({ ...ctx, homeId: p.home, id: p.id, pending: p.pending || null, now: Date.now() }));
  }
  if (req.method === "SET") {
    if (!p.home || !p.id || !p.values) return Promise.resolve({ ok: false, error: "Złe polecenie" });
    return withSession((ctx) => send({ ...ctx, homeId: p.home, id: p.id, values: p.values }));
  }
  return Promise.resolve({ ok: false, error: "Nieznane żądanie: " + req.method });
}

AppSideService(
  BaseSideService({
    onInit() {},

    onRequest(req, res) {
      handle(req)
        .then((result) => res(null, result))
        .catch((e) => res(null, { ok: false, error: String((e && e.message) || e) }));
    },

    // Logowanie albo zmiana domu w ustawieniach: dajemy znać zegarkowi, żeby od razu odświeżył
    onSettingsChange({ key }) {
      const notify = () => {
        try {
          this.call({ type: "LOGGED_IN" });
        } catch (e) {}
      };
      if (key === "homeId") {
        cache.at = 0;
        return notify();
      }
      if (key !== "loginRequest" || !loginRequested()) return;
      login()
        .then((ok) => {
          if (ok) notify();
        })
        .catch(() => {});
    },

    onRun() {},
    onDestroy() {},
  })
);
