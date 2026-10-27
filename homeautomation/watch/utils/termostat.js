// Logika aplikacji bez API zegarka: nastawa, widok stanu, offline, potwierdzenia poleceń,
// zbieranie naciśnięć. Testy w test/termostat.test.mjs. Pola State/Config/Set według
// SmartTermostatOLED/docs/API.md (pkt 5-7).

export const TARGET_MIN = 15;
export const TARGET_MAX = 30;
export const TARGET_STEP = 0.5;
export const OFFLINE_MS = 3 * 60 * 1000; // lastSeen starsze = brak kontaktu (pkt 8.1)
export const SEND_DELAY_MS = 1000; // polecenie po tylu ms bez dotyku
export const ACK_TIMEOUT_MS = 30000; // tyle czekamy na lastCommand
export const SETTLE_MS = 15000; // po potwierdzeniu tyle czekamy, aż state pokaże nową wartość

const num = (x) => (typeof x === "number" && isFinite(x) ? x : null);

// Krok − / + o 0,5 °C w zakresie 15-30. Nastawa spoza zakresu (np. eko 12 w AUTO) nie skacze
// w przeciwną stronę: − przy 12 zostaje 12, + daje 15.
export function stepTarget(t, dir) {
  const cur = num(t);
  if (cur === null) return null;
  let next = Math.round((cur + dir * TARGET_STEP) / TARGET_STEP) * TARGET_STEP;
  next = Math.min(TARGET_MAX, Math.max(TARGET_MIN, next));
  if ((dir < 0 && next > cur) || (dir > 0 && next < cur)) return cur;
  return next;
}

// 21.4 -> "21,4°", brak -> "--,-°"
export function formatTemp(t) {
  const v = num(t);
  if (v === null) return "--,-°";
  const r = Math.round(v * 10) / 10;
  return (r < 0 ? "−" : "") + Math.abs(r).toFixed(1).replace(".", ",") + "°";
}

export function isOffline(lastSeen, now) {
  const seen = num(lastSeen);
  return seen === null || now - seen > OFFLINE_MS;
}

// Ile minut temu był kontakt -> tekst
export function agoText(lastSeen, now) {
  const seen = num(lastSeen);
  if (seen === null) return "";
  const min = Math.max(0, Math.floor((now - seen) / 60000));
  if (min < 1) return "przed chwilą";
  if (min < 60) return min + " min temu";
  const h = Math.floor(min / 60);
  if (h < 48) return h + " h temu";
  return Math.floor(h / 24) + " dni temu";
}

// state + config + lastSeen z bazy -> mały obiekt dla zegarka (liczy go Side Service czasem telefonu)
export function buildView(state, config, lastSeen, now) {
  const st = state && typeof state === "object" ? state : null;
  const cfg = config && typeof config === "object" ? config : {};
  const offline = isOffline(lastSeen, now);
  if (!st) return { name: cfg.name || "", hasData: false, offline, ago: agoText(lastSeen, now) };
  const temp = num(st.temp);
  const outdoor = st.outdoor && typeof st.outdoor === "object" ? num(st.outdoor.temp) : null;
  return {
    name: String(cfg.name || ""),
    hasData: true,
    offline,
    ago: agoText(lastSeen, now),
    temp,
    target: num(st.target),
    heating: st.heating === true,
    sensorFault: st.sensorFault === true || temp === null,
    power: st.power !== false,
    // ochrona: "frost" (wyłączony, pilnuje temperatury przeciwmrozowej), "faultDuty" (awaria czujnika,
    // grzanie awaryjne cyklami) albo null (API.md pkt 5)
    protect: st.protect === "frost" || st.protect === "faultDuty" ? st.protect : null,
    mode: st.mode === "auto" ? "auto" : "manual",
    override: st.override === true,
    comfortNow: st.comfortNow === true,
    nextChange: typeof st.nextChange === "string" && st.nextChange ? st.nextChange : null,
    outdoor,
  };
}

// Najważniejsze ostrzeżenie (czerwony napis) albo null
export function warningOf(view) {
  if (!view || !view.hasData) return null;
  if (view.offline) return "Brak kontaktu" + (view.ago ? " · " + view.ago : "");
  if (view.sensorFault) return view.protect === "faultDuty" ? "Awaria czujnika · grzanie awaryjne" : "Awaria czujnika";
  if (!view.power) return view.protect === "frost" ? "Wyłączony · ochrona przed mrozem" : "Termostat wyłączony";
  return null;
}

// Linia pod przełącznikiem trybu: w AUTO okres i „do HH:MM”, nadpisanie wyróżnione
export function modeInfo(view, mode) {
  if (!view || !view.hasData || mode !== "auto" || view.mode !== "auto") return { text: "", override: false };
  const until = view.nextChange ? " do " + view.nextChange : "";
  if (view.override) return { text: "nadpisane" + until, override: true };
  return { text: (view.comfortNow ? "komfort" : "eko") + until, override: false };
}

export function outdoorText(view) {
  if (!view || !view.hasData || view.outdoor === null || view.outdoor === undefined) return "";
  return "na zewnątrz " + formatTemp(view.outdoor);
}

// --- potwierdzenie polecenia (lastCommand) ---

const FIELD_NAMES = { target: "nastawa", mode: "tryb", power: "zasilanie", _: "polecenie" };
const CODE_NAMES = {
  range: "poza zakresem",
  type: "zły typ",
  format: "zły format",
  value: "zła wartość",
  length: "za długie",
  json: "błędny JSON",
};
const ERROR_NAMES = {
  expired: "Polecenie wygasło",
  busy: "Urządzenie zajęte",
  forbidden: "Brak uprawnień",
};

export function errorsText(errors) {
  const keys = Object.keys(errors || {});
  if (!keys.length) return "Błąd";
  // urządzenie odrzuca pola ponad poziom dostępu autora (API.md pkt 12)
  if (keys.some((k) => errors[k] === "forbidden")) return "Brak uprawnień";
  const k = keys[0];
  return "Błąd: " + (FIELD_NAMES[k] || k) + " " + (CODE_NAMES[errors[k]] || errors[k]);
}

// lastCommand {key, ok, errors?, error?} -> null (jeszcze nie to polecenie) albo { ok, text }
export function ackResult(lastCommand, key) {
  const lc = lastCommand && typeof lastCommand === "object" ? lastCommand : null;
  if (!key || !lc || lc.key !== key) return null;
  const errors = lc.errors && typeof lc.errors === "object" && Object.keys(lc.errors).length ? lc.errors : null;
  if (lc.ok === true && !errors) return { ok: true, text: "Zapisano" };
  if (errors) return { ok: false, text: errorsText(errors) };
  if (lc.error) return { ok: false, text: ERROR_NAMES[lc.error] || "Błąd: " + lc.error };
  return { ok: false, text: "Błąd" };
}

// --- wartość zmieniana na zegarku (nastawa albo tryb) ---
// local = null | { value, touchedAt, sentAt, key, ackedAt, chain }. Póki local istnieje, ekran pokazuje
// local.value zamiast wartości z bazy (dotyk działa od razu, bez czekania na termostat).
// chain = wcześniej wysłano już inną wartość, której baza może jeszcze nie pokazywać.

export function editLocal(local, value, touchedAt) {
  return { value, touchedAt, sentAt: 0, key: null, ackedAt: 0, chain: !!(local && (local.sentAt || local.chain)) };
}

// Kolejne − / + liczone od wartości na ekranie; wysyłka po SEND_DELAY_MS bez dotyku
export function pressTarget(local, remoteTarget, dir, now) {
  const base = local ? local.value : remoteTarget;
  const value = stepTarget(base, dir);
  if (value === null) return local;
  return editLocal(local, value, now);
}

// Tryb wysyłamy od razu
export function chooseValue(local, value, now) {
  return editLocal(local, value, now - SEND_DELAY_MS);
}

export function sendDue(local, now) {
  return !!local && !local.sentAt && now - local.touchedAt >= SEND_DELAY_MS;
}

// Po + i − z powrotem do wartości z bazy nic nie wysyłamy (w AUTO samo polecenie target
// włączyłoby nadpisanie) - chyba że w drodze jest już inna wartość, którą trzeba cofnąć
export function needsSend(local, remote) {
  return !!local && (local.value !== remote || local.chain);
}

export function shownValue(local, remote) {
  return local ? local.value : remote;
}

// Czy local jeszcze potrzebny, gdy przyszedł nowy stan z bazy
export function settleLocal(local, remote, now) {
  if (!local) return null;
  if (!local.sentAt) return local; // jeszcze zbieramy naciśnięcia
  // baza już pokazuje nową wartość (przy cofnięciu - dopiero po potwierdzeniu, bo przed nim to stara)
  if (remote === local.value && (!local.chain || local.ackedAt)) return null;
  if (local.ackedAt) return now - local.ackedAt > SETTLE_MS ? null : local;
  return now - local.sentAt > ACK_TIMEOUT_MS ? null : local;
}

// Potwierdzenie przyszło dla ostatniego wysłanego polecenia - wcześniejsze termostat wykonał przed nim
export function applyAck(local, ack, key, now) {
  if (!local || !local.sentAt || !local.key) return local;
  if (ack.ok || local.key !== key) return { ...local, ackedAt: now };
  return null; // odrzucone - wracamy do wartości z bazy
}
