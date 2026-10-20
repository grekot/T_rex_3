// Pobieranie szczytów (natural=peak) z OpenStreetMap przez Overpass API, kawałkami
// z pamięcią podręczną na dysku. Bez zależności - Node 18+ (wbudowany fetch).
//
// Surowe odpowiedzi Overpass trzymamy POZA projektem (domyślnie w katalogu tymczasowym),
// bo zeus pakuje cały folder projektu do .zab.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export const OVERPASS_URLS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.private.coffee/api/interpreter",
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
];

export const DEFAULT_CACHE = path.join(os.tmpdir(), "szczyty-osm-cache");

// Prostokąt [south, west, north, east] -> kawałki po `step` stopni
export function splitBbox([s, w, n, e], step) {
  const out = [];
  for (let lat = s; lat < n - 1e-9; lat += step) {
    for (let lon = w; lon < e - 1e-9; lon += step) {
      out.push([lat, lon, Math.min(lat + step, n), Math.min(lon + step, e)].map((v) => +v.toFixed(4)));
    }
  }
  return out;
}

// Zapytanie: wszystkie szczyty z wysokością (także bez nazwy - potrzebne do liczenia izolacji)
export function peakQuery(bbox, timeout = 180) {
  return `[out:json][timeout:${timeout}];node["natural"="peak"]["ele"](${bbox.join(",")});out body;`;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchOnce(url, query) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", "User-Agent": "szczyty-zeppos-tool/1.0" },
    body: "data=" + encodeURIComponent(query),
    signal: AbortSignal.timeout(240000),
  });
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
  const json = await res.json();
  if (json.remark && /runtime error|timed out/i.test(json.remark)) throw new Error(`${url}: ${json.remark}`);
  return json;
}

// Pobiera jeden kawałek (albo bierze z pamięci podręcznej); zwraca listę elementów OSM
export async function fetchChunk(bbox, { cache = DEFAULT_CACHE, log = console.log, refresh = false } = {}) {
  fs.mkdirSync(cache, { recursive: true });
  const file = path.join(cache, `peaks_${bbox.join("_")}.json`);
  if (!refresh && fs.existsSync(file)) return JSON.parse(fs.readFileSync(file, "utf8")).elements;
  const query = peakQuery(bbox);
  let lastErr;
  // serwery bywają przeciążone (502/504) - kolejne serwery i rosnące przerwy, do ~20 min
  for (let attempt = 0; attempt < 16; attempt++) {
    const url = OVERPASS_URLS[attempt % OVERPASS_URLS.length];
    try {
      const json = await fetchOnce(url, query);
      fs.writeFileSync(file, JSON.stringify(json));
      log(`  ${bbox.join(",")}: ${json.elements.length} szczytów (${new URL(url).host})`);
      return json.elements;
    } catch (e) {
      lastErr = e;
      log(`  ${bbox.join(",")}: ${e.message} - ponawiam`);
      await sleep(Math.min(120000, 5000 * 2 ** Math.floor(attempt / OVERPASS_URLS.length)));
    }
  }
  throw lastErr;
}

export async function fetchPeaks(bbox, { step = 2, ...opts } = {}) {
  const all = new Map();
  for (const chunk of splitBbox(bbox, step)) {
    for (const el of await fetchChunk(chunk, opts)) all.set(el.id, el);
  }
  return [...all.values()];
}
