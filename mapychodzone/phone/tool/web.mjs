// Wersja przeglądarkowa MapyChodzone: dane regionów i lokalny serwer testowy.
//
//   node tool/web.mjs dane <katalog-z-danymi>   kopiuje katalog.json, styl.json i pliki regionów
//                                                do build/web/dane (po `flutter build web`)
//   node tool/web.mjs serwer [port]              serwuje build/web na http://localhost:<port>/
//
// Pliki danych to wynik repozytorium mapychodzone-dane (np. ..\..\..\mapychodzone-dane\build)
// albo pobrane zasoby wydania dane-RRRR-MM-DD. Na Firebase Hosting trafia cały build/web.
// Serwer obsługuje nagłówek Range, bo PMTiles czyta paczkę mapy kawałkami (jak Firebase Hosting).
import { createHash } from 'node:crypto';
import { copyFileSync, createReadStream, existsSync, mkdirSync, readFileSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const WEB = resolve(fileURLToPath(new URL('../build/web', import.meta.url)));
const TYPY = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.json': 'application/json',
  '.geojson': 'application/geo+json',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.pbf': 'application/x-protobuf',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.pmtiles': 'application/vnd.pmtiles',
};

function sha256(plik) {
  return createHash('sha256').update(readFileSync(plik)).digest('hex');
}

function dane(zrodlo) {
  if (!zrodlo) throw new Error('Podaj katalog z danymi (katalog.json, styl.json, pliki regionów)');
  if (!existsSync(join(WEB, 'index.html'))) throw new Error('Najpierw: flutter build web --release');
  const katalog = JSON.parse(readFileSync(join(zrodlo, 'katalog.json'), 'utf8'));
  const cel = join(WEB, 'dane');
  mkdirSync(cel, { recursive: true });
  const pliki = [katalog.styl];
  for (const r of katalog.regiony) pliki.push(r.mapa, r.szlaki, ...[r.punkty, r.poziomice, r.teren, r.przeszkody].filter(Boolean));
  for (const p of pliki) {
    const z = join(zrodlo, p.plik);
    if (statSync(z).size !== p.rozmiar || sha256(z) !== p.sha256) throw new Error(`Plik ${p.plik} nie zgadza się z katalogiem`);
    const c = join(cel, p.plik);
    if (!existsSync(c) || statSync(c).size !== p.rozmiar || sha256(c) !== p.sha256) copyFileSync(z, c);
    console.log(`  ${p.plik} (${(p.rozmiar / 1e6).toFixed(1)} MB)`);
  }
  copyFileSync(join(zrodlo, 'katalog.json'), join(cel, 'katalog.json'));
  console.log(`Dane ${katalog.wydanie}: ${katalog.regiony.map((r) => r.id).join(', ')} -> ${cel}`);
}

function serwer(port = 8090) {
  createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    let plik = normalize(resolve(WEB, '.' + decodeURIComponent(url.pathname)));
    if (plik === WEB || (existsSync(plik) && statSync(plik).isDirectory())) plik = join(plik, 'index.html');
    if (!(plik + sep).startsWith(WEB + sep) || !existsSync(plik)) {
      res.writeHead(404);
      return res.end('brak');
    }
    const rozmiar = statSync(plik).size;
    const typ = TYPY[extname(plik)] || 'application/octet-stream';
    const zakres = /bytes=(\d+)-(\d*)/.exec(req.headers.range || '');
    if (zakres) {
      const od = Number(zakres[1]);
      const doo = zakres[2] ? Math.min(Number(zakres[2]), rozmiar - 1) : rozmiar - 1;
      res.writeHead(206, {
        'Content-Type': typ,
        'Content-Range': `bytes ${od}-${doo}/${rozmiar}`,
        'Content-Length': doo - od + 1,
        'Accept-Ranges': 'bytes',
      });
      return createReadStream(plik, { start: od, end: doo }).pipe(res);
    }
    res.writeHead(200, { 'Content-Type': typ, 'Content-Length': rozmiar, 'Accept-Ranges': 'bytes' });
    createReadStream(plik).pipe(res);
  }).listen(port, () => console.log(`MapyChodzone (web): http://localhost:${port}/`));
}

const [polecenie, arg] = process.argv.slice(2);
if (polecenie === 'dane') dane(arg);
else if (polecenie === 'serwer') serwer(arg ? Number(arg) : undefined);
else console.log('Użycie: node tool/web.mjs dane <katalog> | serwer [port]');
