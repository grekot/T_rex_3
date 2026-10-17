// Formatowanie tekstów na zegarku - czyste funkcje.

// Date -> "14:05"
export function formatTime(date) {
  const h = date.getHours();
  const m = date.getMinutes();
  return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
}

export function plural(value, one, few, many) {
  const n = Math.abs(Math.round(Number(value) || 0));
  if (n === 1) return one;
  const last = n % 10;
  const last2 = n % 100;
  if (last >= 2 && last <= 4 && (last2 < 12 || last2 > 14)) return few;
  return many;
}

// Linia stanu synchronizacji, np. "zsynchronizowano 14:05" albo "offline · 2 zmiany czekają"
export function syncStatus(fetchedAt, pendingCount, offline) {
  if (offline || pendingCount > 0) {
    if (pendingCount > 0) {
      return (
        (offline ? "offline · " : "") +
        pendingCount +
        " " +
        plural(pendingCount, "zmiana czeka", "zmiany czekają", "zmian czeka")
      );
    }
    return "offline";
  }
  if (!fetchedAt) return "";
  return "zsynchronizowano " + formatTime(new Date(fetchedAt));
}

export function shorten(text, max = 60) {
  const t = String(text || "");
  return t.length > max ? t.slice(0, max - 3) + "..." : t;
}
