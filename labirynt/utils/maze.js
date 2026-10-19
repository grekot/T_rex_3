// Labirynt - bez UI, dzięki temu da się go przetestować w Node.
// Poziom N zawsze wygląda tak samo (ziarno losowania = numer poziomu), więc po
// wpadnięciu do dziury albo wyjściu z gry wracasz do tego samego labiryntu.
import { SIZES } from "./geometry.js";

// Rozmiar planszy na kolejnych poziomach; od 8. poziomu zawsze 11x11
const GRID_BY_LEVEL = [7, 7, 8, 9, 9, 10, 10, 11];

export function sizeForLevel(level) {
  const n = GRID_BY_LEVEL[Math.min(Math.max(1, level), GRID_BY_LEVEL.length) - 1];
  for (const s of SIZES) if (s.n === n) return s;
  return SIZES[SIZES.length - 1];
}

// Na poziomie N jest N + 1 dziur, ale nie więcej niż 1 na 5 pól
export function holesForLevel(level, cellCount) {
  return Math.min(Math.max(1, level) + 1, Math.floor(cellCount / 5));
}

// Mały generator liczb pseudolosowych (mulberry32) - ten sam wynik dla tego samego ziarna
export function rng(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function isActive(size, i) {
  return size.active.charAt(i) === "1";
}

// Sąsiedzi pola w kolejności: góra, prawo, dół, lewo (tylko pola labiryntu)
export function gridNeighbors(size, i) {
  const n = size.n;
  const r = Math.floor(i / n);
  const c = i % n;
  const out = [];
  if (r > 0) out.push(i - n);
  if (c < n - 1) out.push(i + 1);
  if (r < n - 1) out.push(i + n);
  if (c > 0) out.push(i - 1);
  return out.filter((j) => isActive(size, j));
}

export function cellCenter(size, i) {
  return {
    x: size.x + (i % size.n) * size.cell + Math.floor(size.cell / 2),
    y: size.y + Math.floor(i / size.n) * size.cell + Math.floor(size.cell / 2),
  };
}

// Labirynt metodą „wędrówki z cofaniem”: długie, kręte korytarze bez pętli.
// Zwraca links[i] = lista pól, do których z i prowadzi przejście.
export function carve(size, start, rnd) {
  const total = size.n * size.n;
  const links = [];
  const seen = [];
  for (let i = 0; i < total; i++) {
    links.push([]);
    seen.push(false);
  }
  const stack = [start];
  seen[start] = true;
  while (stack.length) {
    const cur = stack[stack.length - 1];
    const options = gridNeighbors(size, cur).filter((j) => !seen[j]);
    if (!options.length) {
      stack.pop();
      continue;
    }
    const next = options[Math.floor(rnd() * options.length)];
    links[cur].push(next);
    links[next].push(cur);
    seen[next] = true;
    stack.push(next);
  }
  return links;
}

// Odległości (w krokach) od pola start po przejściach labiryntu + rodzic na najkrótszej drodze
export function distances(links, start) {
  const dist = links.map(() => -1);
  const parent = links.map(() => -1);
  dist[start] = 0;
  const queue = [start];
  for (let q = 0; q < queue.length; q++) {
    const cur = queue[q];
    for (const j of links[cur]) {
      if (dist[j] !== -1) continue;
      dist[j] = dist[cur] + 1;
      parent[j] = cur;
      queue.push(j);
    }
  }
  return { dist, parent };
}

function shuffle(list, rnd) {
  for (let i = list.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    const t = list[i];
    list[i] = list[j];
    list[j] = t;
  }
  return list;
}

// Ściany jako prostokąty (px). Sąsiednie odcinki na jednej linii są łączone,
// żeby na zegarku było mniej widżetów.
export function wallRects(size, links) {
  const { n, cell, x: x0, y: y0, wall } = size;
  const half = Math.floor(wall / 2);
  const horizontal = {}; // y -> [[xa, xb], ...]
  const vertical = {}; // x -> [[ya, yb], ...]
  const add = (map, key, a, b) => (map[key] = map[key] || []).push([a, b]);
  const open = (i, j) => j >= 0 && j < n * n && isActive(size, j) && links[i].indexOf(j) !== -1;

  for (let i = 0; i < n * n; i++) {
    if (!isActive(size, i)) continue;
    const r = Math.floor(i / n);
    const c = i % n;
    const left = x0 + c * cell;
    const top = y0 + r * cell;
    const up = r > 0 ? i - n : -1;
    const down = r < n - 1 ? i + n : -1;
    const west = c > 0 ? i - 1 : -1;
    const east = c < n - 1 ? i + 1 : -1;
    // górna i lewa krawędź zawsze należą do tego pola; dolna i prawa tylko na brzegu labiryntu
    if (!open(i, up)) add(horizontal, top, left, left + cell);
    if (down === -1 || !isActive(size, down)) add(horizontal, top + cell, left, left + cell);
    if (!open(i, west)) add(vertical, left, top, top + cell);
    if (east === -1 || !isActive(size, east)) add(vertical, left + cell, top, top + cell);
  }

  const rects = [];
  const merge = (map, makeRect) => {
    Object.keys(map)
      .map(Number)
      .sort((a, b) => a - b)
      .forEach((key) => {
        const segs = map[key].sort((a, b) => a[0] - b[0]);
        let [a, b] = segs[0];
        for (let k = 1; k <= segs.length; k++) {
          if (k < segs.length && segs[k][0] <= b) {
            b = Math.max(b, segs[k][1]);
            continue;
          }
          rects.push(makeRect(key, a, b));
          if (k < segs.length) [a, b] = segs[k];
        }
      });
  };
  merge(horizontal, (y, a, b) => ({ x: a - half, y: y - half, w: b - a + wall, h: wall }));
  merge(vertical, (x, a, b) => ({ x: x - half, y: a - half, w: wall, h: b - a + wall }));
  return rects;
}

// Dla każdego pola: indeksy ścian, które kulka stojąca w tym polu może dotknąć
export function wallIndex(size, rects) {
  const { n, cell, x: x0, y: y0, ball } = size;
  const index = [];
  for (let i = 0; i < n * n; i++) index.push([]);
  rects.forEach((w, k) => {
    const margin = ball + 1;
    const c0 = Math.max(0, Math.floor((w.x - margin - x0) / cell));
    const c1 = Math.min(n - 1, Math.floor((w.x + w.w + margin - x0) / cell));
    const r0 = Math.max(0, Math.floor((w.y - margin - y0) / cell));
    const r1 = Math.min(n - 1, Math.floor((w.y + w.h + margin - y0) / cell));
    for (let r = r0; r <= r1; r++) {
      for (let c = c0; c <= c1; c++) index[r * n + c].push(k);
    }
  });
  return index;
}

// Pole, w którym jest punkt (px) - przycięte do planszy
export function cellAt(size, x, y) {
  const n = size.n;
  const c = Math.min(n - 1, Math.max(0, Math.floor((x - size.x) / size.cell)));
  const r = Math.min(n - 1, Math.max(0, Math.floor((y - size.y) / size.cell)));
  return r * n + c;
}

// Cały poziom: ściany, start, meta i dziury
export function buildLevel(level) {
  const size = sizeForLevel(level);
  const rnd = rng(level * 7919 + 13);
  const total = size.n * size.n;
  const cells = [];
  for (let i = 0; i < total; i++) if (isActive(size, i)) cells.push(i);

  // start: pole najbliżej lewego górnego rogu, meta: najdalej od startu po korytarzach
  let start = cells[0];
  for (const i of cells) {
    const score = Math.floor(i / size.n) + (i % size.n);
    if (score < Math.floor(start / size.n) + (start % size.n)) start = i;
  }
  const links = carve(size, start, rnd);
  const { dist, parent } = distances(links, start);
  let goal = start;
  for (const i of cells) if (dist[i] > dist[goal]) goal = i;

  const path = [];
  for (let i = goal; i !== -1; i = parent[i]) path.unshift(i);

  // Dziury nigdy nie leżą na drodze, przy starcie ani na mecie. Kolejność wyboru:
  // 1. pułapki na zakrętach - pole na wprost za zakrętem drogi. Jeśli dzieli je od zakrętu
  //    ściana, otwieramy ją: rozpędzona kulka, która nie wyhamuje, wjeżdża prosto do dziury.
  //    Dziura praktycznie zamyka swoje pole, więc nowe przejście nie skraca drogi do mety.
  // 2. pozostałe odnogi odchodzące od drogi,
  // 3. reszta ślepych zaułków.
  const onPath = {};
  path.forEach((i) => (onPath[i] = true));
  const allowed = {};
  cells.forEach((i) => (allowed[i] = !onPath[i] && dist[i] > 1));
  const want = holesForLevel(level, cells.length);
  const holes = [];
  const opened = [];
  const take = (i) => {
    if (holes.length < want && allowed[i] && holes.indexOf(i) === -1) holes.push(i);
  };
  const turns = [];
  for (let k = 1; k < path.length - 1; k++) {
    const b = path[k];
    const straight = b + (b - path[k - 1]);
    if (path[k + 1] !== straight && gridNeighbors(size, b).indexOf(straight) !== -1) turns.push([b, straight]);
  }
  shuffle(turns, rnd).forEach(([b, d]) => {
    if (holes.length >= want || !allowed[d] || holes.indexOf(d) !== -1) return;
    if (links[b].indexOf(d) === -1) {
      links[b].push(d);
      links[d].push(b);
      opened.push([b, d]);
    }
    holes.push(d);
  });
  const traps = holes.slice();
  shuffle(cells.filter((i) => links[i].some((j) => onPath[j])), rnd).forEach(take);
  shuffle(cells.slice(), rnd).forEach(take);

  const walls = wallRects(size, links);
  return {
    level,
    size,
    links,
    walls,
    index: wallIndex(size, walls),
    start,
    goal,
    path,
    holes,
    traps,
    opened,
    startPoint: cellCenter(size, start),
    goalPoint: cellCenter(size, goal),
    holePoints: holes.map((i) => cellCenter(size, i)),
  };
}

// Kulka wpada, gdy jej środek jest nad dziurą
export function holeUnder(lv, ball) {
  const limit = lv.size.hole * 0.8;
  for (let k = 0; k < lv.holePoints.length; k++) {
    const p = lv.holePoints[k];
    const dx = ball.x - p.x;
    const dy = ball.y - p.y;
    if (dx * dx + dy * dy < limit * limit) return k;
  }
  return -1;
}

// Dziura ściąga kulkę, która najechała na jej brzeg - tym mocniej, im bliżej środka.
// Zwraca dodatkowe przyspieszenie (px/s^2).
export function holePull(lv, ball, strength) {
  const reach = lv.size.hole + lv.size.ball * 0.6;
  let ax = 0;
  let ay = 0;
  for (const p of lv.holePoints) {
    const dx = p.x - ball.x;
    const dy = p.y - ball.y;
    const d = Math.sqrt(dx * dx + dy * dy);
    if (d >= reach || d < 1e-6) continue;
    const k = strength * (1 - d / reach);
    ax += (dx / d) * k;
    ay += (dy / d) * k;
  }
  return { ax, ay };
}

export function atGoal(lv, ball) {
  const limit = lv.size.goal * 0.7;
  const dx = ball.x - lv.goalPoint.x;
  const dy = ball.y - lv.goalPoint.y;
  return dx * dx + dy * dy < limit * limit;
}

// 83 500 ms -> "1:23"
export function formatClock(ms) {
  const total = Math.floor(ms / 1000);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return m + ":" + (s < 10 ? "0" : "") + s;
}
