// Buduje data/peaks.json: Korona Gór Polski (z watch/utils/kgp.js) + wszystkie szczyty pasm
// z kategorii polskiej Wikipedii, ze współrzędnymi dopasowanymi do węzłów OSM natural=peak.
//
// Użycie (w folderze korona):  node tools/fetch_peaks.mjs [--refresh]
// Surowe odpowiedzi trzymamy w %TEMP%\korona-cache (poza projektem; --refresh pobiera od nowa).
//
// Źródła: pl.wikipedia.org (przynależność do pasma, wysokość z infoboksu, CC BY-SA),
// OpenStreetMap przez Overpass API (współrzędne, © współtwórcy OpenStreetMap, ODbL).
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { KGP } from "../watch/utils/kgp.js";

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const CACHE = path.join(os.tmpdir(), "korona-cache");
const REFRESH = process.argv.includes("--refresh");
const UA = { "User-Agent": "korona-zepp-app/1.0 (personal project)", "Api-User-Agent": "korona-zepp-app/1.0" };

export const GROUPS = [
  { id: "kgp", name: "Korona Gór Polski", short: "KGP" },
  { id: "wyspowy", name: "Beskid Wyspowy", short: "Wyspowy", category: "Szczyty Beskidu Wyspowego" },
  { id: "sadecki", name: "Beskid Sądecki", short: "Sądecki", category: "Szczyty Beskidu Sądeckiego" },
  { id: "gorce", name: "Gorce", short: "Gorce", category: "Szczyty Gorców" },
  { id: "tatry", name: "Tatry polskie", short: "Tatry", category: "Szczyty polskich Tatr" },
];

// Prostokąt obejmujący wszystkie pasma (do zapytania OSM)
const BBOX = [49.05, 19.55, 49.95, 21.3];
// Promień rozpoznania (jak SUMMIT_RADIUS_M w watch/utils/korona.js) - przy gęstych
// wierzchołkach zmniejszany do połowy odległości od sąsiada, żeby strefy się nie nakładały
const RADIUS = 120;
const MIN_RADIUS = 40;

fs.mkdirSync(CACHE, { recursive: true });

async function cached(name, fetcher) {
  const file = path.join(CACHE, name);
  if (!REFRESH && fs.existsSync(file)) return JSON.parse(fs.readFileSync(file, "utf8"));
  const data = await fetcher();
  fs.writeFileSync(file, JSON.stringify(data));
  return data;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function wiki(params) {
  const url = "https://pl.wikipedia.org/w/api.php?" + new URLSearchParams({ format: "json", formatversion: "2", ...params });
  for (let i = 0; ; i++) {
    const r = await fetch(url, { headers: UA });
    if (r.ok) return r.json();
    if (i >= 8) throw new Error("Wikipedia " + r.status);
    // 429 = za szybko; czekamy tyle, ile każe serwer, albo coraz dłużej
    const wait = Number(r.headers.get("retry-after")) || 10 * (i + 1);
    console.error("Wikipedia " + r.status + ", czekam " + wait + " s");
    await sleep(wait * 1000);
  }
}

async function categoryMembers(category) {
  const out = [];
  let cont = {};
  for (;;) {
    const j = await wiki({ action: "query", list: "categorymembers", cmtitle: "Kategoria:" + category, cmnamespace: "0", cmlimit: "500", ...cont });
    out.push(...j.query.categorymembers.map((m) => m.title));
    if (!j.continue) break;
    cont = { cmcontinue: j.continue.cmcontinue };
  }
  // Duże szczyty mają własną podkategorię („Kategoria:Mogielica”) i bywa, że ich strona jest
  // tylko tam - dokładamy stronę o nazwie podkategorii
  const subs = await wiki({ action: "query", list: "categorymembers", cmtitle: "Kategoria:" + category, cmtype: "subcat", cmlimit: "500" });
  for (const s of subs.query.categorymembers) {
    const title = s.title.replace(/^Kategoria:/, "");
    if (!out.includes(title)) out.push(title);
  }
  return out;
}

// Współrzędne, id Wikidata i wysokość z infoboksu dla stron (po 50)
async function pageInfo(titles) {
  const out = {};
  for (let i = 0; i < titles.length; i += 50) {
    const batch = titles.slice(i, i + 50);
    const j = await wiki({
      action: "query",
      prop: "coordinates|pageprops|revisions",
      rvprop: "content",
      rvslots: "main",
      ppprop: "wikibase_item",
      redirects: "1",
      titles: batch.join("|"),
    });
    for (const p of j.query.pages) {
      const text = (p.revisions && p.revisions[0].slots.main.content) || "";
      // Współrzędne z {{coord}}, a gdy ich brak - z parametru infoboksu „współrzędne”
      const c = (p.coordinates && p.coordinates[0]) || infoboxCoords(text);
      out[p.title] = {
        title: p.title,
        pageid: p.pageid,
        wikidata: p.pageprops && p.pageprops.wikibase_item,
        lat: c ? c.lat : null,
        lon: c ? c.lon : null,
        h: infoboxHeight(text),
        country: /państwo\s*=\s*([^\n|]*)/i.exec(text)?.[1]?.trim() || "",
      };
    }
    await sleep(1500);
  }
  return out;
}

// "wysokość = 1170" / "wysokość = 1170,5 m" / "wysokość = {{...}}" -> 1170
export function infoboxHeight(text) {
  // liczba, po której jest koniec pola, „m”, przypis albo szablon (literówki jak „124o” odpadają)
  const m = /\|\s*wysokość\s*=\s*([0-9][0-9 .,]*?)\s*(?=m\b|<|\||\{|\n|$)/i.exec(text);
  if (!m) return null;
  const v = parseFloat(m[1].replace(/\s/g, "").replace(",", "."));
  return isFinite(v) && v > 100 && v < 3000 ? Math.round(v) : null;
}

// "|współrzędne = 49°15′04″N 19°55′39.4″E" -> { lat, lon }
export function infoboxCoords(text) {
  const m = /\|\s*współrzędne\s*=\s*([^\n]*)/i.exec(text);
  return m ? parseDms(m[1]) : null;
}

const DMS_PART = /(\d+(?:[.,]\d+)?)\s*°\s*(?:(\d+(?:[.,]\d+)?)\s*[′']\s*)?(?:(\d+(?:[.,]\d+)?)\s*(?:″|''|")\s*)?([NSEW])/.source;
const DMS = new RegExp(DMS_PART + "[\\s,]*" + DMS_PART);

export function parseDms(s) {
  const m = DMS.exec(String(s).replace(/&nbsp;/g, " "));
  if (!m) return null;
  const val = (d, mi, se, h) => {
    const n = (x) => (x ? parseFloat(x.replace(",", ".")) : 0);
    const v = n(d) + n(mi) / 60 + n(se) / 3600;
    return h === "S" || h === "W" ? -v : v;
  };
  const a = val(m[1], m[2], m[3], m[4]);
  const b = val(m[5], m[6], m[7], m[8]);
  return /[NS]/.test(m[4]) ? { lat: a, lon: b } : { lat: b, lon: a };
}

const MIRRORS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://overpass.private.coffee/api/interpreter",
];

async function overpass(query) {
  for (let i = 0; i < 12; i++) {
    const url = MIRRORS[i % MIRRORS.length];
    try {
      const r = await fetch(url, { method: "POST", headers: { ...UA, "Content-Type": "application/x-www-form-urlencoded" }, body: "data=" + encodeURIComponent(query) });
      const text = await r.text();
      if (r.ok && text.startsWith("{")) return JSON.parse(text);
      console.error("Overpass " + url + ": " + r.status);
    } catch (e) {
      console.error("Overpass " + url + ": " + e.message);
    }
    await sleep(5000 * (i + 1));
  }
  throw new Error("Overpass niedostępny");
}

const R = 6371000;
const rad = (d) => (d * Math.PI) / 180;
export function dist(a, b) {
  const dLat = rad(b.lat - a.lat);
  const dLon = rad(b.lon - a.lon);
  const x = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
}

// "Kiczora (Beskid Wyspowy)" -> "kiczora"
export function normName(s) {
  return String(s || "")
    .replace(/\s*\(.*\)\s*$/, "")
    .toLowerCase()
    .replace(/[–—-]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function osmNames(tags) {
  const names = [tags.name, tags["name:pl"], tags.alt_name, tags.old_name, tags.official_name]
    .filter(Boolean)
    .flatMap((n) => n.split(/\s*[/;]\s*/));
  return names.map(normName);
}

// Dopasowanie strony Wikipedii do węzła OSM: wikidata, potem nazwa w promieniu 1,5 km
export function matchOsm(page, nodes) {
  if (page.wikidata) {
    const byWd = nodes.find((n) => n.tags.wikidata === page.wikidata);
    if (byWd) return { node: byWd, how: "wikidata" };
  }
  if (page.lat === null) return null;
  const name = normName(page.title);
  let best = null;
  for (const n of nodes) {
    if (!osmNames(n.tags).includes(name)) continue;
    const d = dist(page, n);
    if (d < 1500 && (!best || d < best.d)) best = { node: n, d };
  }
  return best ? { node: best.node, how: "nazwa" } : null;
}

const osmEle = (tags) => {
  const v = parseFloat(String(tags.ele || "").replace(",", "."));
  return isFinite(v) ? Math.round(v) : null;
};

async function main() {
  const osm = await cached("osm-peaks.json", () =>
    overpass(`[out:json][timeout:180];node["natural"="peak"]["name"](${BBOX.join(",")});out body;`)
  );
  const nodes = osm.elements;
  console.log("węzłów OSM z nazwą:", nodes.length);

  // Szczyty KGP (stałe id) - zaczynamy od nich, pasma dopisują się do ich grup
  const peaks = KGP.map((p) => ({ ...p, groups: ["kgp"] }));
  const byOsm = new Map(peaks.map((p) => [p.osm, p]));
  const report = { wiki: 0, noCoords: [], wikiCoords: [], abroad: [] };

  for (const g of GROUPS.filter((x) => x.category)) {
    const titles = await cached("cat-" + g.id + ".json", () => categoryMembers(g.category));
    const info = await cached("pages-" + g.id + ".json", () => pageInfo(titles));
    for (const title of titles) {
      const page = info[title];
      // Strony o całych pasmach, nie o wierzchołkach
      if (!page || /^Pasmo |\(pasmo\)/.test(title)) continue;
      report.wiki++;
      const m = matchOsm(page, nodes);
      if (!m && page.lat === null) {
        report.noCoords.push(g.id + ": " + title);
        continue;
      }
      const node = m && m.node;
      const existing = node ? byOsm.get(node.id) : null;
      if (existing) {
        if (!existing.groups.includes(g.id)) existing.groups.push(g.id);
        continue;
      }
      const name = page.title.replace(/\s*\(.*\)\s*$/, "");
      const p = {
        id: node ? "o" + node.id : "w" + page.pageid,
        name,
        h: page.h || (node ? osmEle(node.tags) : null),
        lat: node ? node.lat : page.lat,
        lon: node ? node.lon : page.lon,
        range: g.name,
        groups: [g.id],
        ...(node ? { osm: node.id } : {}),
        wiki: page.title,
      };
      if (!node) report.wikiCoords.push(g.id + ": " + title);
      if (/słowacj/i.test(page.country) && !/polsk/i.test(page.country)) report.abroad.push(g.id + ": " + title);
      peaks.push(p);
      if (node) byOsm.set(node.id, p);
    }
  }

  // Ten sam szczyt z dwóch źródeł (np. strona bez dopasowania OSM obok węzła) - zostaje jeden
  const kept = [];
  for (const p of peaks) {
    const twin = kept.find((q) => normName(q.name) === normName(p.name) && dist(p, q) < 300);
    if (twin) {
      p.groups.forEach((g) => twin.groups.includes(g) || twin.groups.push(g));
      continue;
    }
    kept.push(p);
  }

  // Promień rozpoznania: połowa odległości do najbliższego innego wierzchołka (max RADIUS)
  for (const p of kept) {
    let nearest = Infinity;
    for (const q of kept) if (q !== p) nearest = Math.min(nearest, dist(p, q));
    const r = Math.max(MIN_RADIUS, Math.min(RADIUS, Math.floor(nearest / 2)));
    if (r < RADIUS) p.r = r;
  }

  const groups = GROUPS.map(({ id, name, short }) => ({
    id,
    name,
    short,
    counted: kept.filter((p) => p.groups.includes(id) && !p.variantOf).length,
  }));
  const out = {
    version: 1,
    generated: new Date().toISOString().slice(0, 10),
    sources: [
      "Korona Gór Polski: lista Klubu Zdobywców KGP (Wikipedia „Korona Gór Polski”, CC BY-SA 4.0)",
      "Szczyty pasm: kategorie polskiej Wikipedii (" + GROUPS.filter((g) => g.category).map((g) => g.category).join(", ") + "), CC BY-SA 4.0",
      "Współrzędne: OpenStreetMap natural=peak (© współtwórcy OpenStreetMap, ODbL)",
    ],
    groups,
    peaks: kept,
  };
  fs.writeFileSync(path.join(ROOT, "data", "peaks.json"), JSON.stringify(out, null, 1) + "\n");
  console.log("grupy:", groups.map((g) => g.id + " " + g.counted).join(", "));
  console.log("szczytów razem:", kept.length, "| stron Wikipedii:", report.wiki);
  console.log("bez OSM (współrzędne z Wikipedii):", report.wikiCoords.length, report.wikiCoords.join("; "));
  console.log("pominięte bez współrzędnych:", report.noCoords.length, report.noCoords.join("; "));
  console.log("Słowacja wg infoboksu:", report.abroad.length, report.abroad.join("; "));
  console.log("ze zmniejszonym promieniem:", kept.filter((p) => p.r).length);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
