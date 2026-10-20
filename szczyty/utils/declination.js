// Deklinacja magnetyczna (o ile kompas odchyla się od północy geograficznej) dla Polski
// i okolic. Siatka policzona kalkulatorem NOAA z modelu WMM2025 na 1.01.2027 razem ze
// zmianą roczną; między węzłami interpolacja dwuliniowa. Błąd modelu ok. 0,4°, a kompas
// zegarka i tak drga o kilka stopni - dokładniej nie trzeba.

const LAT0 = 48;
const LAT_STEP = 1.5;
const LON0 = 12;
const LON_STEP = 2.5;
const EPOCH = 2027.0;
// wiersze: szerokość 48, 49.5, 51, 52.5, 54, 55.5; kolumny: długość 12, 14.5, 17, 19.5, 22, 24.5
const DECL = [
  [4.47, 4.994, 5.494, 5.971, 6.428, 6.864],
  [4.586, 5.153, 5.695, 6.215, 6.715, 7.194],
  [4.706, 5.32, 5.909, 6.477, 7.024, 7.551],
  [4.833, 5.497, 6.138, 6.758, 7.356, 7.935],
  [4.966, 5.686, 6.383, 7.059, 7.714, 8.348],
  [5.109, 5.888, 6.645, 7.381, 8.096, 8.791],
];
// zmiana roczna w stopniach
const SV = [
  [0.117, 0.11, 0.103, 0.096, 0.09, 0.084],
  [0.124, 0.117, 0.11, 0.103, 0.097, 0.09],
  [0.131, 0.124, 0.117, 0.111, 0.104, 0.098],
  [0.139, 0.132, 0.125, 0.119, 0.112, 0.106],
  [0.148, 0.141, 0.134, 0.128, 0.121, 0.115],
  [0.157, 0.15, 0.144, 0.137, 0.131, 0.125],
];

function bilinear(grid, lat, lon) {
  const fr = Math.min(Math.max((lat - LAT0) / LAT_STEP, 0), grid.length - 1);
  const fc = Math.min(Math.max((lon - LON0) / LON_STEP, 0), grid[0].length - 1);
  const r = Math.min(Math.floor(fr), grid.length - 2);
  const c = Math.min(Math.floor(fc), grid[0].length - 2);
  const tr = fr - r;
  const tc = fc - c;
  const top = grid[r][c] * (1 - tc) + grid[r][c + 1] * tc;
  const bottom = grid[r + 1][c] * (1 - tc) + grid[r + 1][c + 1] * tc;
  return top * (1 - tr) + bottom * tr;
}

// Deklinacja w stopniach (dodatnia = wschodnia: igła odchyla się na wschód od północy)
// dla roku ułamkowego, np. 2026.8. Poza siatką bierze najbliższy brzeg.
export function declination(lat, lon, year) {
  const dt = Math.min(Math.max(year - EPOCH, -3), 5); // poza 2024-2032 nie ekstrapolujemy
  return bilinear(DECL, lat, lon) + bilinear(SV, lat, lon) * dt;
}

export function yearOf(ms) {
  const d = new Date(ms);
  return d.getFullYear() + d.getMonth() / 12;
}

// Kierunek magnetyczny + deklinacja wschodnia = kierunek geograficzny
export function trueHeading(magnetic, decl) {
  const h = (magnetic + decl) % 360;
  return h < 0 ? h + 360 : h;
}
