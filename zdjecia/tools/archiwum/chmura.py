"""Firestore i logowanie przez REST (bez bibliotek Google): konto właściciela, ten sam projekt co aplikacje.
Hasło wpisuje właściciel w swoim terminalu (`zaloguj`); w pliku sesji zostaje tylko token odświeżania.
"""
from __future__ import annotations

import base64
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request

CONFIG_DART = os.path.join(os.path.dirname(__file__), "..", "..", "phone", "lib", "cloud", "firebase_config.dart")


class CloudError(Exception):
    pass


def load_config(path: str = CONFIG_DART) -> tuple[str, str]:
    """Klucz API i projekt: zmienne ZDJECIA_API_KEY / ZDJECIA_PROJECT albo plik konfiguracji aplikacji na telefon."""
    key, project = os.environ.get("ZDJECIA_API_KEY"), os.environ.get("ZDJECIA_PROJECT")
    if key and project:
        return key, project
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as e:
        raise CloudError(f"Brak konfiguracji Firebase ({os.path.normpath(path)}) - patrz README") from e
    k = re.search(r"firebaseApiKey\s*=\s*'([^']+)'", text)
    p = re.search(r"firebaseProjectId\s*=\s*'([^']+)'", text)
    if not k or not p:
        raise CloudError("Konfiguracja Firebase bez klucza API albo projektu")
    return k.group(1), p.group(1)


def _request(method: str, url: str, body: dict | None = None, token: str | None = None, form: dict | None = None) -> dict:
    headers = {}
    data = None
    if form is not None:
        data = urllib.parse.urlencode(form).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    elif body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            text = e.read().decode("utf-8", "replace")
            if e.code in (429, 500, 502, 503, 504) and attempt < 3:
                time.sleep(2 ** attempt * 2)
                continue
            try:
                msg = json.loads(text).get("error", {})
                msg = msg.get("message") if isinstance(msg, dict) else msg
            except ValueError:
                msg = text[:200]
            raise CloudError(f"HTTP {e.code}: {msg}") from None
        except urllib.error.URLError as e:
            if attempt < 3:
                time.sleep(2 ** attempt * 2)
                continue
            raise CloudError(f"Sieć: {e.reason}") from None
    raise CloudError("Nie udało się")


def to_value(v):
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, float):
        return {"doubleValue": v}
    if isinstance(v, (bytes, bytearray)):
        return {"bytesValue": base64.b64encode(bytes(v)).decode()}
    if isinstance(v, str):
        return {"stringValue": v}
    if isinstance(v, Timestamp):
        return {"timestampValue": v.iso}
    raise TypeError(type(v))


def from_value(v: dict):
    if "stringValue" in v:
        return v["stringValue"]
    if "integerValue" in v:
        return int(v["integerValue"])
    if "doubleValue" in v:
        return float(v["doubleValue"])
    if "booleanValue" in v:
        return v["booleanValue"]
    if "bytesValue" in v:
        return base64.b64decode(v["bytesValue"])
    if "timestampValue" in v:
        return v["timestampValue"]
    return None


class Timestamp:
    def __init__(self, seconds: float | None = None) -> None:
        t = time.time() if seconds is None else seconds
        self.iso = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + f".{int((t % 1) * 1000):03d}Z"


class Cloud:
    def __init__(self, session_path: str) -> None:
        self.api_key, self.project = load_config()
        self.session_path = session_path
        self._token: str | None = None
        self._token_until = 0.0
        self.uid: str | None = None
        self.email: str | None = None
        if os.path.exists(session_path):
            s = json.load(open(session_path, encoding="utf-8"))
            self.uid, self.email = s.get("uid"), s.get("email")

    @property
    def base(self) -> str:
        return f"https://firestore.googleapis.com/v1/projects/{self.project}/databases/(default)/documents"

    def login(self, email: str, password: str) -> None:
        j = _request(
            "POST",
            f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={self.api_key}",
            {"email": email, "password": password, "returnSecureToken": True},
        )
        self._save(j["localId"], j["email"], j["refreshToken"])
        self._token, self._token_until = j["idToken"], time.time() + int(j.get("expiresIn", 3600)) - 120

    def _save(self, uid: str, email: str, refresh: str) -> None:
        self.uid, self.email = uid, email
        os.makedirs(os.path.dirname(os.path.abspath(self.session_path)), exist_ok=True)
        with open(self.session_path, "w", encoding="utf-8") as f:
            json.dump({"uid": uid, "email": email, "refreshToken": refresh}, f)

    def token(self) -> str:
        if self._token and time.time() < self._token_until:
            return self._token
        if not os.path.exists(self.session_path):
            raise CloudError("Brak sesji - najpierw: python archiwum.py zaloguj")
        s = json.load(open(self.session_path, encoding="utf-8"))
        j = _request(
            "POST",
            f"https://securetoken.googleapis.com/v1/token?key={self.api_key}",
            form={"grant_type": "refresh_token", "refresh_token": s["refreshToken"]},
        )
        self._save(j["user_id"], s.get("email", ""), j["refresh_token"])
        self._token, self._token_until = j["id_token"], time.time() + int(j.get("expires_in", 3600)) - 120
        return self._token

    def set(self, path: str, fields: dict) -> None:
        _request("PATCH", f"{self.base}/{path}", {"fields": {k: to_value(v) for k, v in fields.items()}}, token=self.token())

    def get(self, path: str) -> dict | None:
        try:
            j = _request("GET", f"{self.base}/{path}", token=self.token())
        except CloudError as e:
            if str(e).startswith("HTTP 404"):
                return None
            raise
        return {k: from_value(v) for k, v in j.get("fields", {}).items()}

    def list_ids(self, collection: str, mask: tuple[str, ...] = ("t",)) -> list[str]:
        out, page = [], None
        while True:
            q = [("pageSize", "300")] + [("mask.fieldPaths", m) for m in mask]
            if page:
                q.append(("pageToken", page))
            j = _request("GET", f"{self.base}/{collection}?{urllib.parse.urlencode(q)}", token=self.token())
            out += [d["name"].rsplit("/", 1)[1] for d in j.get("documents", [])]
            page = j.get("nextPageToken")
            if not page:
                return out

    def delete(self, path: str) -> None:
        _request("DELETE", f"{self.base}/{path}", token=self.token())
