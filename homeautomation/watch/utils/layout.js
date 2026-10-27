// Układ kafelków pulpitu zegarka w wierszach (API.md pkt 13a) - bez API zegarka, testy w test/layout.test.mjs.
// half = pół wiersza (dwa obok siebie), full = cały wiersz, big = cały wiersz o podwójnej wysokości.
// Strony leżą jedna pod drugą (przewijanie pionowe), każda z nagłówkiem. Na okrągłym ekranie szerokość
// wiersza to cięciwa koła w miejscu, w którym wiersz da się najbliżej środka ekranu przewinąć - kafelki
// na samej górze i na samym dole treści są węższe.

export const GEOMETRY = {
  top: 92, // pod tytułem i linią stanu
  header: 40, // nagłówek strony
  row: 88, // wysokość wiersza half / full
  big: 186, // wysokość wiersza big (dwa wiersze + odstęp)
  gap: 10, // odstęp między kafelkami
  margin: 14, // od krawędzi koła
  maxWidth: 400, // szerszy kafelek nic nie daje
  minWidth: 220,
  bottom: 70, // miejsce pod ostatnim wierszem
};

// Kolejne kafelki -> wiersze: dwa half obok siebie; half bez pary zostaje sam (na środku)
export function rowsOf(items) {
  const rows = [];
  let pending = null;
  (items || []).forEach((item) => {
    const size = item.size === "half" || item.size === "big" ? item.size : "full";
    if (size === "half") {
      if (pending) {
        pending.items.push(item);
        pending = null;
      } else {
        pending = { size: "half", items: [item] };
        rows.push(pending);
      }
      return;
    }
    pending = null;
    rows.push({ size, items: [item] });
  });
  return rows;
}

// Połowa cięciwy koła o promieniu r w odległości d od środka
function halfChord(r, d) {
  return d >= r ? 0 : Math.sqrt(r * r - d * d);
}

// pages = [{title, items}] -> { blocks: [{type:"header", text, y, h, x, w} | {type:"tile", item, x, y, w, h}], height }
export function layoutPages(pages, screen, geometry) {
  const g = { ...GEOMETRY, ...(geometry || {}) };
  const W = screen.width;
  const H = screen.height;
  const round = screen.shape !== "square";

  // najpierw pionowo, potem szerokości (zależą od tego, ile treści da się przewinąć)
  const rows = [];
  let y = g.top;
  (pages || []).forEach((page) => {
    const items = (page && page.items) || [];
    if (!items.length) return;
    if (page.title) {
      rows.push({ type: "header", text: String(page.title), y, h: g.header });
      y += g.header;
    }
    rowsOf(items).forEach((row) => {
      const h = row.size === "big" ? g.big : g.row;
      rows.push({ type: "row", row, y, h });
      y += h + g.gap;
    });
  });
  const height = y + g.bottom;
  const maxScroll = Math.max(0, height - H);

  const widthAt = (top, h) => {
    if (!round) return Math.min(g.maxWidth, W - 2 * g.margin);
    // przewinięcie, które stawia wiersz najbliżej środka ekranu
    const s = Math.min(maxScroll, Math.max(0, top + h / 2 - H / 2));
    const cy = H / 2;
    const d = Math.max(Math.abs(top - s - cy), Math.abs(top + h - s - cy));
    const w = 2 * halfChord(Math.min(W, H) / 2, d) - 2 * g.margin;
    return Math.round(Math.max(g.minWidth, Math.min(g.maxWidth, w)));
  };

  const blocks = [];
  rows.forEach((r) => {
    const w = widthAt(r.y, r.h);
    const x = Math.round((W - w) / 2);
    if (r.type === "header") {
      blocks.push({ type: "header", text: r.text, x, y: r.y, w, h: r.h });
      return;
    }
    const n = r.row.size === "half" ? 2 : 1;
    const tw = n === 2 ? Math.floor((w - g.gap) / 2) : w;
    // pojedynczy half stoi na środku wiersza
    const startX = n === 2 && r.row.items.length === 1 ? Math.round((W - tw) / 2) : x;
    r.row.items.forEach((item, i) => {
      blocks.push({ type: "tile", item, size: r.row.size, x: startX + i * (tw + g.gap), y: r.y, w: tw, h: r.h });
    });
  });
  return { blocks, height };
}
