// Firebase Auth + Firestore przez REST - czyste funkcje (adresy, treści zapytań, dekodowanie).
// Używa ich Side Service; testy w test/firestore.test.mjs.
// Część ogólna (logowanie, commit, dekodowanie) jak w aplikacji Zakupy; tu dla kolekcji "places".

export const AUTH_URL = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword";
export const REFRESH_URL = "https://securetoken.googleapis.com/v1/token";

export function documentsBase(projectId) {
  return "https://firestore.googleapis.com/v1/projects/" + projectId + "/databases/(default)/documents";
}

export function signInRequest(apiKey, email, password) {
  return {
    url: AUTH_URL + "?key=" + encodeURIComponent(apiKey),
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  };
}

// Założenie konta e-mail + hasło (odpowiedź jak przy logowaniu)
export function signUpRequest(apiKey, email, password) {
  return {
    url: "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + encodeURIComponent(apiKey),
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

// Miejsca, do których użytkownik ma dostęp (warunek musi pasować do reguł Firestore)
export function placesQueryRequest(projectId, idToken, uid) {
  return {
    url: documentsBase(projectId) + ":runQuery",
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer " + idToken },
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId: "places" }],
        where: {
          fieldFilter: {
            field: { fieldPath: "members" },
            op: "ARRAY_CONTAINS",
            value: { stringValue: uid },
          },
        },
      },
    }),
  };
}

// --- zapisy: wszystko przez documents:commit (zawsze POST - nie zależymy od PATCH/DELETE w Zepp) ---

export function docName(projectId, path) {
  return "projects/" + projectId + "/databases/(default)/documents/" + path;
}

const ts = (ms) => ({ timestampValue: new Date(ms).toISOString() });
const str = (s) => ({ stringValue: String(s) });

export function commitRequest(projectId, idToken, writes) {
  return {
    url: documentsBase(projectId) + ":commit",
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer " + idToken },
    body: JSON.stringify({ writes }),
  };
}

// Zapisy Firestore dla operacji z zegarka (format operacji opisany w utils/places.js)
export function opWrites(projectId, op, uid, email) {
  const path = "places/" + (op.p ? op.p.id : op.pid);
  if (op.t === "addPlace") {
    const p = op.p;
    return [
      {
        update: {
          name: docName(projectId, path),
          fields: {
            name: str(p.name),
            lat: { doubleValue: p.lat },
            lon: { doubleValue: p.lon },
            savedAt: ts(p.at),
            ownerId: str(uid),
            members: { arrayValue: { values: [str(uid)] } },
            memberEmails: { mapValue: { fields: { [uid]: str(email || "") } } },
            createdAt: ts(op.at),
            updatedAt: ts(op.at),
            source: str("watch"),
          },
        },
        currentDocument: { exists: false },
      },
    ];
  }
  if (op.t === "delPlace") {
    return [{ delete: docName(projectId, path) }];
  }
  if (op.t === "leavePlace") {
    // Usuwamy siebie z members i swój e-mail z memberEmails (pole w masce bez wartości = usunięcie)
    return [
      {
        update: { name: docName(projectId, path), fields: { updatedAt: ts(op.at) } },
        updateMask: { fieldPaths: ["updatedAt", "memberEmails.`" + uid + "`"] },
        updateTransforms: [{ fieldPath: "members", removeAllFromArray: { values: [str(uid)] } }],
        currentDocument: { exists: true },
      },
    ];
  }
  return [];
}

export function emailKey(email) {
  return String(email || "")
    .trim()
    .toLowerCase();
}

// Wpis w książce adresowej (emails/{e-mail}) - żeby inni mogli dodać mnie do znajomych
export function emailIndexWrites(projectId, uid, email, atMs) {
  const key = emailKey(email);
  return [
    {
      update: {
        name: docName(projectId, "emails/" + key),
        fields: { uid: str(uid), email: str(key), updatedAt: ts(atMs) },
      },
    },
  ];
}

// Wynik zapisu operacji:
//  "applied" - zapisane (także ponowienie czegoś, co już się zapisało),
//  "gone"    - nieaktualne (miejsce usunięte w międzyczasie) - porzucamy,
//  "auth"    - wygasł token, "error" - inny błąd: zostaw w kolejce i przerwij (kolejność ma znaczenie).
export function commitOutcome(op, status, body) {
  const data = parseBody(body);
  if (data && data.error) {
    const e = data.error;
    const s = e.status || "";
    if (e.code === 401 || s === "UNAUTHENTICATED") return "auth";
    if (s === "ALREADY_EXISTS") return "applied";
    if (s === "FAILED_PRECONDITION") return op.t === "addPlace" ? "applied" : "gone";
    if (s === "NOT_FOUND" || s === "PERMISSION_DENIED") return "gone";
    return "error";
  }
  if (status === 401) return "auth";
  if (status >= 400 || !data) return "error";
  return data.writeResults || data.commitTime ? "applied" : "error";
}

// fetch w Zepp OS zwraca body jako tekst albo już jako obiekt - zależnie od telefonu
export function parseBody(body) {
  if (typeof body !== "string") return body;
  try {
    return JSON.parse(body);
  } catch (e) {
    return null;
  }
}

// Komunikat błędu z odpowiedzi Google ({error: {message}}) albo null
export function errorOf(status, body) {
  const data = parseBody(body);
  if (data && data.error) {
    if (typeof data.error === "string") return data.error;
    return data.error.message || data.error.status || "HTTP " + (data.error.code || status);
  }
  if (Array.isArray(data) && data[0] && data[0].error) return data[0].error.message || "HTTP " + status;
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
  EMAIL_EXISTS: "Konto z tym e-mailem już istnieje - zaloguj się",
  WEAK_PASSWORD: "Hasło za słabe (minimum 6 znaków)",
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

// "2026-10-16T10:00:00.123456Z" -> ms. Firestore podaje mikrosekundy, a nie każdy
// silnik JS (np. QuickJS) czyta więcej niż 3 cyfry ułamka - przycinamy je.
export function parseTimestamp(text) {
  return Date.parse(String(text || "").replace(/(\.\d{3})\d+/, "$1")) || null;
}

// Wartość Firestore -> zwykła wartość JS
export function decodeValue(v) {
  if (!v || typeof v !== "object") return null;
  if ("stringValue" in v) return v.stringValue;
  if ("booleanValue" in v) return v.booleanValue;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("timestampValue" in v) return parseTimestamp(v.timestampValue);
  if ("nullValue" in v) return null;
  if ("arrayValue" in v) return ((v.arrayValue && v.arrayValue.values) || []).map(decodeValue);
  if ("mapValue" in v) return decodeFields((v.mapValue && v.mapValue.fields) || {});
  return null;
}

export function decodeFields(fields) {
  const out = {};
  Object.keys(fields || {}).forEach((k) => {
    out[k] = decodeValue(fields[k]);
  });
  return out;
}

// {name: ".../documents/lists/abc", fields} -> {id: "abc", ...pola}
export function decodeDocument(doc) {
  const name = String(doc.name || "");
  return { id: name.slice(name.lastIndexOf("/") + 1), ...decodeFields(doc.fields) };
}

// Odpowiedź runQuery to tablica; puste wyniki mają tylko readTime
export function decodeQueryResponse(body) {
  const data = parseBody(body);
  if (!Array.isArray(data)) return [];
  return data.filter((r) => r && r.document).map((r) => decodeDocument(r.document));
}

export function decodeListResponse(body) {
  const data = parseBody(body);
  return ((data && data.documents) || []).map(decodeDocument);
}
