// "Jestem Groot." - po stuknięciu w Groota dymek, a po chwili tłumaczenie Rocketa: co Groot
// naprawdę mówi. Najpierw to, czego potrzebuje (jak napis na dole ekranu), a gdy nic mu nie
// trzeba - coś w stylu etapu (maluch słodki, nastolatek obrażony, dorosły dojrzały).
// Czysta logika, testy w test/rocket.test.mjs. Teksty krótkie: dwa wiersze na ekranie zegarka.

import { stageOf, potted, activeRequest, localMinute, isSleepy } from "./pet.js";
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
  const i = pick ? pick(lines.length) : 0;
  return lines[Math.max(0, Math.min(lines.length - 1, i))];
}
