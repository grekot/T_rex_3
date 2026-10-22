// Nadgarstek i stuknięcia - czysta logika bez API zegarka (testy: test/wrist.test.mjs).
// Pozycja z akcelerometru: ekran zwrócony do twarzy, gdy grawitacja idzie głównie wzdłuż osi z
// (oś prostopadła do ekranu), ręka opuszczona, gdy grawitacja leży w płaszczyźnie ekranu.
// Znak z nie jest pewny (nie wiadomo, czy leżący zegarek daje +980 czy -980), więc liczy się |z|.

// Udział |z| w całym przyspieszeniu: od LOOK_RATIO patrzymy na zegarek, do DOWN_RATIO ręka opuszczona,
// pomiędzy - nic się nie zmienia (histereza)
export const LOOK_RATIO = 0.75;
export const DOWN_RATIO = 0.45;
// Jak długo pozycja musi się utrzymać, żeby ją uznać (zwykłe machanie ręką nie wystarczy)
export const LOOK_MS = 250;
export const DOWN_MS = 500;
// Poniżej tego (cm/s²) odczyt jest bez sensu (swobodny ruch, błąd czujnika)
const MIN_MAG = 300;

export const TAP_DOUBLE_MS = 400;

export function wristState() {
  return { pose: "", cand: "", since: 0 };
}

// "look" / "away" / "" (nie wiadomo)
export function classify(a) {
  if (!a || typeof a.x !== "number" || typeof a.y !== "number" || typeof a.z !== "number") return "";
  const mag = Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
  if (mag < MIN_MAG) return "";
  const ratio = Math.abs(a.z) / mag;
  if (ratio >= LOOK_RATIO) return "look";
  if (ratio <= DOWN_RATIO) return "away";
  return "";
}

// Kolejny odczyt; zwraca "up" (uniesienie), "down" (opuszczenie) albo "".
// Pierwsza ustalona pozycja nie jest zdarzeniem - ręka już uniesiona na starcie to nie gest.
export function feedWrist(st, a, now) {
  const cls = classify(a);
  if (!cls) {
    st.cand = "";
    return "";
  }
  if (cls !== st.cand) {
    st.cand = cls;
    st.since = now;
  }
  if (cls === st.pose) return "";
  if (now - st.since < (cls === "look" ? LOOK_MS : DOWN_MS)) return "";
  const prev = st.pose;
  st.pose = cls;
  if (!prev) return "";
  return cls === "look" ? "up" : "down";
}

export function tapState() {
  return { last: 0 };
}

// "double", gdy drugie stuknięcie przyszło szybko po pierwszym, inaczej "single"
export function tap(st, now) {
  if (st.last && now - st.last <= TAP_DOUBLE_MS) {
    st.last = 0;
    return "double";
  }
  st.last = now;
  return "single";
}
