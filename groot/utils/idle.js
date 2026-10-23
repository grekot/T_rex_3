// Co robi pupil, gdy nic mu nie trzeba: stoi i oddycha, spaceruje w lewo i w prawo
// albo zajmuje się czymś (klocki, książka, stanie na rękach, piłka). Czysta logika -
// strona główna woła stepIdle() co klatkę animacji i rysuje to, co zwróci idleSprite().

export const ACTS = ["dance", "flower", "game", "spores"];
export const WALK_RANGE = 56; // najdalej tyle px od środka
export const WALK_STEP = 8; // px na klatkę (600 ms)

const STAND = [8, 16]; // klatki stania (min, max)
const ACT = [14, 24]; // klatki zajęcia

function between(rng, [a, b]) {
  return a + Math.floor(rng() * (b - a + 1));
}

export function newIdle() {
  return { kind: "stand", left: STAND[0], x: 0, target: 0, act: null, face: 1, last: null };
}

// Następna klatka; canAct = forma ma klatki zajęć
export function stepIdle(st, canAct, rng) {
  if (st.kind === "walk") {
    const d = st.target - st.x;
    if (Math.abs(d) <= WALK_STEP) {
      st.x = st.target;
      st.kind = "stand";
      st.left = between(rng, STAND);
    } else {
      st.face = d > 0 ? 1 : -1;
      st.x += st.face * WALK_STEP;
    }
    return st;
  }
  st.left--;
  if (st.left > 0) return st;
  // koniec stania albo zajęcia: losujemy, co dalej (nie to samo zajęcie dwa razy z rzędu)
  const r = rng();
  if (st.kind === "act" || !canAct || r < 0.45) {
    if (st.kind === "act" || r < 0.75) {
      st.kind = "walk";
      let t = Math.round((rng() * 2 - 1) * WALK_RANGE);
      if (Math.abs(t - st.x) < WALK_STEP * 3) t = st.x > 0 ? -WALK_RANGE / 2 : WALK_RANGE / 2;
      st.target = t;
      st.act = null;
    } else {
      st.kind = "stand";
      st.left = between(rng, STAND);
    }
    return st;
  }
  const options = ACTS.filter((a) => a !== st.last);
  st.act = options[Math.floor(rng() * options.length)];
  st.last = st.act;
  st.kind = "act";
  st.left = between(rng, ACT);
  st.face = 1;
  return st;
}

// Klatka i przesunięcie: { frame, dx, dy }; frame = licznik klatek strony
export function idleSprite(st, frame) {
  const slow = Math.floor(frame / 2) % 2;
  if (st.kind === "walk") {
    return { frame: st.face < 0 ? "left" : "idle0", dx: st.x, dy: frame % 2 ? -4 : 0 };
  }
  if (st.kind === "act") return { frame: "act_" + st.act + slow, dx: st.x, dy: 0 };
  return { frame: (st.face < 0 ? "left" : "idle") + (st.face < 0 ? "" : slow), dx: st.x, dy: 0 };
}

// Groot musi wrócić na środek (jedzenie, smutek, sen) - bez spaceru
export function resetIdle(st) {
  st.kind = "stand";
  st.left = STAND[0];
  st.x = 0;
  st.target = 0;
  st.act = null;
  st.face = 1;
  return st;
}
