// "Jestem Groot." - po stuknięciu w Groota dymek, a po chwili tłumaczenie Rocketa: co Groot
// naprawdę mówi. Najpierw to, czego potrzebuje (jak napis na dole ekranu), a gdy nic mu nie
// trzeba - coś w stylu etapu (maluch słodki, nastolatek obrażony, dorosły dojrzały).
// Czysta logika, testy w test/galaxy.test.mjs. Teksty krótkie: dwa wiersze na ekranie zegarka.

import { stageOf, potted, activeRequest, localMinute, isSleepy, needsAttention } from "./pet.js";
import { GAME_NAMES } from "./gamelist.js";

export const GROOT = "Jestem Groot.";

export const CHATTER = {
  baby: ["Rocket: mówi, że cię lubi", "Rocket: chce tańczyć", "Rocket: pyta, co to za guzik"],
  child: ["Rocket: chce na spacer", "Rocket: mówi, że jesteś jego kumplem", "Rocket: pyta, czy może nacisnąć guzik"],
  teen: ["Rocket: mówi „zostaw mnie, gram”", "Rocket: mówi, że to nudne", "Rocket: każe ci wyjść z pokoju"],
  adult: ["Rocket: „My jesteśmy Groot”", "Rocket: mówi, że cię kocha. Serio", "Rocket: mówi, że jest z ciebie dumny"],
};

// Tłumaczenie Rocketa; pick(n) zwraca indeks 0..n-1 (losowy na zegarku, stały w testach)
export function rocketSays(s, tz, pick) {
  if (s.gone || stageOf(s) === "egg") return "";
  if (s.asleep) return "Rocket: śpi, nie budź go";
  if (s.sick) return "Rocket: swędzi go kora. Mszyce";
  if (s.hunger === 0) return potted(s) ? "Rocket: mówi, że chce pić" : "Rocket: brakuje mu słońca";
  if (s.happy === 0) return "Rocket: smutno mu. Pobaw się z nim";
  if (s.whim) return "Rocket: marudzi bez powodu. Zgań go";
  if (s.poops) return "Rocket: mówi, że tu bałagan";
  if (isSleepy(localMinute(s.t, tz))) return "Rocket: mówi, że chce spać";
  const req = activeRequest(s);
  if (req && req.kind === "ask") return "Rocket: chce grać w " + GAME_NAMES[req.game];
  const lines = CHATTER[stageOf(s)] || CHATTER.child;
  return choose(lines, pick);
}

function choose(list, pick) {
  const i = pick ? pick(list.length) : 0;
  return list[Math.max(0, Math.min(list.length - 1, i))];
}

// --- zaczepki: Groot sam się odzywa, gdy aplikacja jest otwarta -------------------------
// Co chwilę (strona główna, CHAT_MS) Groot mówi „Jestem Groot.”, a Rocket tłumaczy:
// zaprasza do gry (dymek do stuknięcia), opowiada dowcip (pytanie, potem puenta), chwali,
// mówi o podróży Milano albo o porze dnia. Gdy czegoś mu trzeba - tylko o tym.

export const CHAT_MS = [20000, 40000]; // odstęp między zaczepkami
export const INVITE_MS = 20000; // tyle dymek zaproszenia czeka na stuknięcie

// Pytanie i puenta - krótkie, po dwa wiersze na ekranie
export const JOKES = [
  ["Jak drzewo wysyła wiadomość?", "Liściem!"],
  ["Jak się nazywa smutne drzewo?", "Płacząca wierzba."],
  ["Co drzewo pije na śniadanie?", "Sok z brzozy."],
  ["Dlaczego Groot nie lubi pił?", "Bo piłują mu nerwy."],
  ["Ulubiony przedmiot Groota w szkole?", "Gałęzie matematyki."],
  ["Co mówi drzewo jesienią?", "Lecę z liśćmi, wrócę wiosną!"],
  ["Ile drzew trzeba, by wkręcić żarówkę?", "Żadnego. Wolą fotosyntezę."],
  ["Co mówi drzewo na suchy żart?", "Ale drętwy!"],
  ["Dlaczego Groot nie gra w chowanego?", "Bo zawsze wyrasta jak spod ziemi."],
  ["Co Groot mówi przez telefon?", "„Jestem Groot.” Tak, to wciąż ja."],
  ["Czemu Rocket przegrywa z Grootem w berka?", "Bo Groot ma długie gałęzie."],
  ["Jak Groot zamawia pizzę?", "Z korą. Znaczy z kukurydzą."],
];

export const PRAISE = [
  "Rocket: mówi, że jesteś jego ulubionym człowiekiem",
  "Rocket: dziękuje, że o niego dbasz",
  "Rocket: mówi, że dziś świetnie ci idzie",
  "Rocket: chce ci przybić piątkę. Gałęzią",
];

// Zaprasza do jednej z tych gier (bez spacerów - te trwają godzinami)
export const INVITE_GAMES = ["defend", "mix", "simon", "catch", "eggroll", "aim", "balance", "reflex", "fishing", "throw", "runner", "tree", "balloon", "guess"];

function timeLine(m) {
  if (m >= 7 * 60 + 30 && m < 10 * 60) return "Rocket: mówi dzień dobry! Rozgrzewka?";
  if (m >= 12 * 60 && m < 14 * 60) return "Rocket: mówi, że pora na słońce";
  if (m >= 17 * 60 && m < 20 * 60) return "Rocket: pyta, co dziś robiłeś";
  return "";
}

// trip = tripInfo(s) z utils/galaxy.js (albo null)
function tripLine(trip) {
  if (!trip) return "";
  if (trip.visiting) return "Rocket: podoba mu się na planecie " + trip.visiting;
  const left = trip.next.need - trip.progress;
  return "Rocket: jeszcze " + left + " kroków do " + trip.next.name + ". Spacer?";
}

// Jedna zaczepka: { lines: [teksty po kolei], invite: id gry albo null }.
// rnd() w [0, 1) - Math.random na zegarku, stały ciąg w testach
export function chatter(s, tz, rnd, trip) {
  const r = rnd || (() => 0);
  const pick = (n) => Math.floor(r() * n);
  const need = rocketSays(s, tz, () => 0);
  if (!need) return { lines: [], invite: null };
  // potrzeba, sen albo prośba o grę - tylko o tym (gadanie etapu = nic mu nie trzeba)
  if (CHATTER_ALL.indexOf(need) < 0) return { lines: [GROOT, need], invite: null };
  const x = r();
  if (x < 0.3) {
    const game = INVITE_GAMES[pick(INVITE_GAMES.length)];
    return { lines: [GROOT, "Rocket: chce zagrać w " + GAME_NAMES[game] + ". Stuknij dymek!"], invite: game };
  }
  if (x < 0.55) {
    const j = JOKES[pick(JOKES.length)];
    return { lines: [GROOT, "Rocket: zna kawał. " + j[0], j[1]], invite: null };
  }
  if (x < 0.65) return { lines: [GROOT, choose(PRAISE, pick)], invite: null };
  if (x < 0.78) {
    const t = tripLine(trip);
    if (t) return { lines: [GROOT, t], invite: null };
  }
  if (x < 0.88) {
    const t = timeLine(localMinute(s.t, tz));
    if (t) return { lines: [GROOT, t], invite: null };
  }
  return { lines: [GROOT, rocketSays(s, tz, pick)], invite: null };
}

const CHATTER_ALL = [].concat(CHATTER.baby, CHATTER.child, CHATTER.teen, CHATTER.adult);

// Powitanie po otwarciu aplikacji po dłuższej przerwie (gap = ms od ostatniej wizyty).
// Tylko gdy nic mu nie trzeba - inaczej na ekranie od razu ma być potrzeba ("Ziewa…").
export function greeting(s, gap, tz) {
  if (s.gone || stageOf(s) === "egg" || s.asleep || !(gap > 0)) return [];
  if (needsAttention(s) || isSleepy(localMinute(s.t, tz))) return [];
  if (gap >= 12 * 3600000) return [GROOT + " " + GROOT, "Rocket: tęsknił za tobą!"];
  if (gap >= 4 * 3600000) return [GROOT, "Rocket: cieszy się, że wróciłeś"];
  return [];
}
