// Podsumowanie pomiarów (bez API Zepp, testy w test/stats.test.mjs)

// Próg z SmartTermostatOLED docs/ARCHITEKTURA.md pkt 4.9: dłuższe łączenie = rola mostu zegarka odpada
export const CONNECT_LIMIT_MS = 1500;

export function summary(values) {
  const v = values.filter((x) => typeof x === "number").sort((a, b) => a - b);
  if (!v.length) return null;
  const sum = v.reduce((a, b) => a + b, 0);
  return { n: v.length, min: v[0], avg: Math.round(sum / v.length), max: v[v.length - 1] };
}

export function line(name, s) {
  return s ? `${name}: ${s.min}/${s.avg}/${s.max} ms` : `${name}: brak`;
}

// Wynik serii: łączenie liczymy po średniej, bo pojedynczy długi przypadek widać w max
export function verdict(ready) {
  const s = summary(ready);
  if (!s) return "brak polaczenia";
  return s.avg <= CONNECT_LIMIT_MS ? "OK: laczenie w limicie" : "za wolno: limit 1,5 s";
}
