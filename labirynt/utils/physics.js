// Fizyka kulki - bez UI. Pozycje i prędkości w px ekranu 480 x 480 (prędkość w px/s).
//
// Akcelerometr Zepp OS podaje przyspieszenie w cm/s^2: x w prawo, y w stronę „12”,
// z prostopadle do ekranu. Dokumentacja nie mówi, czy leżący zegarek pokazuje
// z = +980 czy -980, więc znak odczytu poznajemy po osi z podczas kalibracji
// (ekran jest wtedy zwrócony do gracza). Gdyby i tak coś było odwrócone, ekran
// „Czujnik” pozwala odwrócić osie ręcznie.

export const PHYS = {
  gain: 0.8, // px/s^2 na każdy cm/s^2 pochylenia (pochylenie o 20° ≈ 270 px/s^2)
  deadZone: 25, // cm/s^2 - drżenie ręki nie rusza kulki
  friction: 1.1, // tłumienie toczenia na sekundę
  maxSpeed: 380, // px/s
  restitution: 0.35, // ile prędkości zostaje po odbiciu od ściany
};

// Punkt zerowy = średnia z odczytów zebranych, gdy gracz trzyma zegarek „poziomo”.
// Pierwszą połowę pomijamy: zegarek jeszcze drga po stuknięciu, a wygładzone
// odczyty nie dogoniły nowego trzymania.
export function calibrate(all) {
  const samples = all.slice(Math.floor(all.length / 2));
  let x = 0;
  let y = 0;
  let z = 0;
  for (const s of samples) {
    x += s.x;
    y += s.y;
    z += s.z;
  }
  const n = Math.max(1, samples.length);
  return { x: x / n, y: y / n, zSign: z < 0 ? -1 : 1 };
}

function dead(v) {
  const d = PHYS.deadZone;
  if (v > d) return v - d;
  if (v < -d) return v + d;
  return 0;
}

// Odczyt akcelerometru -> przyspieszenie kulki na ekranie (px/s^2, y w dół ekranu).
// Odczyt wskazuje „w górę” (przeciwnie do grawitacji), gdy z > 0 dla ekranu do góry -
// wtedy kulka toczy się w stronę -x i +y; przy odwrotnej konwencji znaki się zamieniają.
export function tiltToAccel(reading, cal, flip) {
  const s = cal.zSign;
  let gx = dead(-s * (reading.x - cal.x));
  let gy = dead(s * (reading.y - cal.y));
  if (flip && flip.x) gx = -gx;
  if (flip && flip.y) gy = -gy;
  return { ax: gx * PHYS.gain, ay: gy * PHYS.gain };
}

// Odpycha kulkę od prostokątów ścian. Zwraca największą prędkość uderzenia (px/s).
export function collideRects(ball, r, rects, ids) {
  let impact = 0;
  for (let k = 0; k < ids.length; k++) {
    const w = rects[ids[k]];
    const cx = Math.max(w.x, Math.min(ball.x, w.x + w.w));
    const cy = Math.max(w.y, Math.min(ball.y, w.y + w.h));
    let dx = ball.x - cx;
    let dy = ball.y - cy;
    const d2 = dx * dx + dy * dy;
    if (d2 >= r * r) continue;
    let nx;
    let ny;
    if (d2 > 1e-9) {
      const d = Math.sqrt(d2);
      nx = dx / d;
      ny = dy / d;
      ball.x = cx + nx * r;
      ball.y = cy + ny * r;
    } else {
      // środek kulki w ścianie (nie powinno się zdarzyć) - wypychamy najkrótszą drogą
      const pushes = [
        [ball.x - w.x + r, -1, 0],
        [w.x + w.w - ball.x + r, 1, 0],
        [ball.y - w.y + r, 0, -1],
        [w.y + w.h - ball.y + r, 0, 1],
      ].sort((a, b) => a[0] - b[0]);
      nx = pushes[0][1];
      ny = pushes[0][2];
      ball.x += nx * pushes[0][0];
      ball.y += ny * pushes[0][0];
    }
    const vn = ball.vx * nx + ball.vy * ny;
    if (vn < 0) {
      ball.vx -= (1 + PHYS.restitution) * vn * nx;
      ball.vy -= (1 + PHYS.restitution) * vn * ny;
      if (-vn > impact) impact = -vn;
    }
  }
  return impact;
}

// Trzyma kulkę wewnątrz okręgu (ekran testu czujnika)
export function collideCircle(ball, r, cx, cy, R) {
  const dx = ball.x - cx;
  const dy = ball.y - cy;
  const d = Math.sqrt(dx * dx + dy * dy);
  const limit = R - r;
  if (d <= limit || d < 1e-9) return 0;
  const nx = dx / d;
  const ny = dy / d;
  ball.x = cx + nx * limit;
  ball.y = cy + ny * limit;
  const vn = ball.vx * nx + ball.vy * ny;
  if (vn <= 0) return 0;
  ball.vx -= (1 + PHYS.restitution) * vn * nx;
  ball.vy -= (1 + PHYS.restitution) * vn * ny;
  return vn;
}

// Jeden krok symulacji. Ruch dzielimy na kawałki nie dłuższe niż pół promienia kulki,
// żeby szybka kulka nie przeskoczyła przez cienką ścianę. collide(ball) -> prędkość uderzenia.
export function step(ball, acc, dt, r, collide) {
  ball.vx += acc.ax * dt;
  ball.vy += acc.ay * dt;
  const damp = Math.exp(-PHYS.friction * dt);
  ball.vx *= damp;
  ball.vy *= damp;
  let speed = Math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy);
  if (speed > PHYS.maxSpeed) {
    ball.vx *= PHYS.maxSpeed / speed;
    ball.vy *= PHYS.maxSpeed / speed;
    speed = PHYS.maxSpeed;
  }
  const parts = Math.max(1, Math.ceil((speed * dt) / (r * 0.5)));
  let impact = 0;
  for (let k = 0; k < parts; k++) {
    ball.x += (ball.vx * dt) / parts;
    ball.y += (ball.vy * dt) / parts;
    impact = Math.max(impact, collide(ball));
  }
  return impact;
}
