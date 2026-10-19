// Teksty pomiarów na ekranie zegarka.

export function formatBytes(n) {
  if (typeof n !== "number" || isNaN(n) || n < 0) return "?";
  if (n < 1024) return n + " B";
  const kb = n / 1024;
  if (kb < 1024) return Math.round(kb) + " KB";
  return (kb / 1024).toFixed(1).replace(".", ",") + " MB";
}

export function formatMs(ms) {
  if (typeof ms !== "number" || isNaN(ms) || ms < 0) return "?";
  if (ms < 1000) return Math.round(ms) + " ms";
  const s = ms / 1000;
  if (s < 10) return s.toFixed(1).replace(".", ",") + " s";
  if (s < 60) return Math.round(s) + " s";
  const total = Math.round(s);
  const min = Math.floor(total / 60);
  return min + " min " + (total - min * 60) + " s";
}

function average(values) {
  const ok = values.filter((v) => typeof v === "number" && !isNaN(v));
  if (!ok.length) return undefined;
  return ok.reduce((a, b) => a + b, 0) / ok.length;
}

// Czas przesłania: wolimy pomiar z telefonu (od wysłania do potwierdzenia), a jak go brak - z zegarka
export function transferMs(p) {
  return typeof p.txMs === "number" ? p.txMs : p.rxMs;
}

export function summaryLines(photos) {
  const list = photos.filter((p) => !p.test);
  if (!list.length) return [];
  const png = average(list.map((p) => p.png));
  const conv = average(list.map((p) => p.conv));
  const tx = average(list.map(transferMs));
  const cv = average(list.map((p) => p.cvMs));
  return [
    "Średnio: PNG " + formatBytes(png) + ", na zegarku " + formatBytes(conv),
    "konwersja " + formatMs(cv) + ", Bluetooth " + formatMs(tx),
  ];
}

export function photoInfoLines(p, index, total) {
  return [
    index + 1 + "/" + total + (p.test ? " (test internetu)" : "") + " · PNG " + formatBytes(p.png) + " · zeg. " + formatBytes(p.conv),
    "pobr. " + formatMs(p.dlMs) + " · konw. " + formatMs(p.cvMs) + " · BT " + formatMs(transferMs(p)),
  ];
}
