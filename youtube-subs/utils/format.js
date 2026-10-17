// Formatowanie liczb i polskiej odmiany - czyste funkcje, testowane w Node.

// 1234567 -> "1 234 567"
export function formatNumber(value) {
  const n = Math.round(Number(value) || 0);
  const digits = String(Math.abs(n));
  let out = "";
  for (let i = 0; i < digits.length; i++) {
    const fromEnd = digits.length - i;
    out += digits[i];
    if (fromEnd > 1 && (fromEnd - 1) % 3 === 0) out += " ";
  }
  return (n < 0 ? "-" : "") + out;
}

// Duże liczby skracane, żeby zmieściły się na tarczy: 12345678 -> "12,3 mln"
export function formatCompact(value) {
  const n = Math.round(Number(value) || 0);
  if (n >= 1e9) return (n / 1e9).toFixed(1).replace(".", ",") + " mld";
  if (n >= 1e7) return (n / 1e6).toFixed(1).replace(".", ",") + " mln";
  return formatNumber(n);
}

// Polska odmiana: plural(5, "film", "filmy", "filmów") -> "filmów"
export function plural(value, one, few, many) {
  const n = Math.abs(Math.round(Number(value) || 0));
  if (n === 1) return one;
  const last = n % 10;
  const last2 = n % 100;
  if (last >= 2 && last <= 4 && (last2 < 12 || last2 > 14)) return few;
  return many;
}

export function withUnit(value, one, few, many) {
  return formatNumber(value) + " " + plural(value, one, few, many);
}

// Date -> "14:05"
export function formatTime(date) {
  const h = date.getHours();
  const m = date.getMinutes();
  return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
}

// 3723 -> "1:02:03", 754 -> "12:34", 45 -> "0:45"
export function formatDuration(totalSec) {
  const s = Math.max(0, Math.round(Number(totalSec) || 0));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  const two = (n) => (n < 10 ? "0" : "") + n;
  return h > 0 ? h + ":" + two(m) + ":" + two(sec) : m + ":" + two(sec);
}

// Numer dnia kalendarzowego w czasie lokalnym (odporny na zmianę czasu letni/zimowy)
function localDayNumber(ms) {
  const d = new Date(ms);
  return Math.floor(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 86400000);
}

// Kiedy opublikowano: "dzisiaj", "wczoraj", "3 dni temu", "2 tyg. temu", "4 mies. temu", "rok temu".
// Liczy dni kalendarzowe, nie pełne doby: film z wczoraj 23:00 oglądany dziś o 8:00 to "wczoraj".
export function relativeDay(thenMs, nowMs) {
  const days = localDayNumber(nowMs) - localDayNumber(thenMs);
  if (days <= 0) return "dzisiaj";
  if (days === 1) return "wczoraj";
  if (days < 7) return days + " dni temu";
  if (days < 30) {
    const w = Math.floor(days / 7);
    return w === 1 ? "tydzień temu" : w + " tyg. temu";
  }
  if (days < 365) {
    const mo = Math.floor(days / 30);
    return mo === 1 ? "miesiąc temu" : mo + " mies. temu";
  }
  const y = Math.floor(days / 365);
  return y === 1 ? "rok temu" : y + " " + plural(y, "rok", "lata", "lat") + " temu";
}

// Skraca długie komunikaty błędów, żeby zmieściły się na dole tarczy
export function shorten(text, max = 60) {
  const t = String(text || "");
  return t.length > max ? t.slice(0, max - 3) + "..." : t;
}
