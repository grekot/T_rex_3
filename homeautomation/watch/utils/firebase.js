// Firebase Auth + Realtime Database przez REST - czyste funkcje (adresy, treści żądań, dekodowanie).
// Używa ich Side Service; testy w test/firebase.test.mjs.
// Logowanie jak w aplikacjach Na szczycie i Waga; dane według SmartTermostatOLED/docs/API.md,
// pkt 8.1, 12, 13a:
//   users/{uid}/homes | watches/{watchId} | watchDashboards/{homeId}/{watchId}
//   homes/{homeId}/ name | ownerUid | access/{uid} | rooms | deviceIndex
//   homes/{homeId}/ scenes/{id}
//   homes/{homeId}/devices/{id}/ info | state | config | lastSeen | lastCommand | describe
//   commands/{homeId}/{id}/{push}

export const AUTH_URL = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword";
export const REFRESH_URL = "https://securetoken.googleapis.com/v1/token";

export function signInRequest(apiKey, email, password) {
  return {
    url: AUTH_URL + "?key=" + encodeURIComponent(apiKey),
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  };
}

export function refreshRequest(apiKey, refreshToken) {
  return {
    url: REFRESH_URL + "?key=" + encodeURIComponent(apiKey),
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=refresh_token&refresh_token=" + encodeURIComponent(refreshToken),
  };
}

// fetch w Zepp OS zwraca body jako tekst albo już rozpakowany JSON - zależnie od telefonu. Rozpakowany napis
// (np. węzeł name albo ownerUid z bazy) przychodzi jako gołe Dom zamiast "Dom" - to nie jest JSON, zostaje jak jest.
// Tekst JSON-a napisu zawsze zaczyna się od cudzysłowu, więc tylko liczby, true/false/null i obiekty bez cudzysłowu
// mogłyby się pomylić - nazwy i uid takie nie bywają.
export function parseBody(body) {
  if (typeof body !== "string") return body === undefined ? null : body;
  try {
    return JSON.parse(body);
  } catch (e) {
    return body.trim() ? body : null;
  }
}

// Komunikat błędu z odpowiedzi Google ({error: {message}}) albo bazy ({error: "Permission denied"}), inaczej null
export function errorOf(status, body) {
  const data = parseBody(body);
  if (data && typeof data === "object" && data.error) {
    if (typeof data.error === "string") return data.error;
    return data.error.message || data.error.status || "HTTP " + (data.error.code || status);
  }
  if (status >= 400) return "HTTP " + status;
  return null;
}

const AUTH_MESSAGES = {
  INVALID_LOGIN_CREDENTIALS: "Nieprawidłowy e-mail lub hasło",
  EMAIL_NOT_FOUND: "Nie ma konta z tym e-mailem",
  INVALID_PASSWORD: "Nieprawidłowe hasło",
  INVALID_EMAIL: "Niepoprawny adres e-mail",
  USER_DISABLED: "Konto zablokowane",
  TOO_MANY_ATTEMPTS_TRY_LATER: "Za dużo prób, spróbuj później",
  OPERATION_NOT_ALLOWED: "Logowanie e-mailem wyłączone w Firebase",
  TOKEN_EXPIRED: "Sesja wygasła - zaloguj się ponownie",
  INVALID_REFRESH_TOKEN: "Sesja wygasła - zaloguj się ponownie",
  USER_NOT_FOUND: "Konto usunięte - zaloguj się ponownie",
};

// "INVALID_LOGIN_CREDENTIALS" / "TOO_MANY_ATTEMPTS_TRY_LATER : ..." -> polski komunikat
export function authErrorMessage(message) {
  const code = String(message || "").split(" ")[0].split(":")[0].trim();
  return AUTH_MESSAGES[code] || String(message || "Błąd logowania");
}

// Czy po tym błędzie trzeba zalogować się od nowa (sesja nie do odświeżenia)
export function isSessionDead(message) {
  const code = String(message || "").split(" ")[0].split(":")[0].trim();
  return ["TOKEN_EXPIRED", "INVALID_REFRESH_TOKEN", "USER_NOT_FOUND", "USER_DISABLED", "INVALID_ID_TOKEN"].indexOf(code) !== -1;
}

// Baza odrzuca wygasły token ID: 401 {"error":"Auth token is expired"} - wtedy jedna próba z nowym tokenem
export function isTokenRejected(status, message) {
  return status === 401 || /token is expired|invalid_token|Invalid token/i.test(String(message || ""));
}

// --- Realtime Database ---

// {db}/a/b/c.json?auth=...[&shallow=true]
export function dbUrl(db, parts, idToken, extra) {
  const path = parts.map((p) => encodeURIComponent(String(p))).join("/");
  return String(db).replace(/\/+$/, "") + "/" + path + ".json?auth=" + encodeURIComponent(idToken) + (extra || "");
}

// Odczyt dowolnego węzła; shallow = same klucze (lista domów, urządzeń - bez historii)
export function readRequest(db, idToken, parts, shallow) {
  return { url: dbUrl(db, parts, idToken, shallow ? "&shallow=true" : ""), method: "GET" };
}

// Zapis całego węzła (PUT). Wysyłamy POST z X-HTTP-Method-Override - fetch w Zepp nie musi znać PUT.
export function writeRequest(db, idToken, parts, value) {
  return {
    url: dbUrl(db, parts, idToken),
    method: "POST",
    headers: { "Content-Type": "application/json", "X-HTTP-Method-Override": "PUT" },
    body: JSON.stringify(value),
  };
}

// homes/{homeId}/devices/{id}[/state | config | lastSeen | lastCommand | config/name | info | describe]
export function devicePath(homeId, id, node) {
  return ["homes", homeId, "devices", id].concat(node ? String(node).split("/") : []);
}

// Polecenie: push do commands/{homeId}/{id} (poza devices - urządzenie słucha tylko tej gałęzi, API.md pkt 8.1).
// "ts" wypełnia serwer bazy; "by" = uid zalogowanej osoby (reguły wymagają by == auth.uid, urządzenie sprawdza
// poziom autora, pkt 12); "source" tylko informacyjnie.
// Potwierdzenie przychodzi w homes/{homeId}/devices/{id}/lastCommand.
export function commandRequest(db, idToken, homeId, id, values, uid) {
  return {
    url: dbUrl(db, ["commands", homeId, id], idToken),
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ values, ts: { ".sv": "timestamp" }, by: uid, source: "watch" }),
  };
}

// {"termostat-ab12cd": true, ...} -> ["termostat-ab12cd", ...] (posortowane; pusto przy null)
export function decodeDevices(body) {
  const data = parseBody(body);
  if (!data || typeof data !== "object" || Array.isArray(data)) return [];
  return Object.keys(data).sort();
}

// Odpowiedź POST: {"name": "-NxYz..."} -> klucz polecenia albo null
export function pushKeyOf(body) {
  const data = parseBody(body);
  return data && typeof data.name === "string" ? data.name : null;
}
