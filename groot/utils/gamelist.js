// Lista minigier: nazwy, grupy w menu, gry do próśb i gry przy akcjach.
// Klucz = folder strony (page/gt/<id>/index.page).

export const GAME_GROUPS = [
  { name: "Ruch ręką", games: ["simon", "catch", "eggroll", "aim", "balance", "reflex", "fishing", "throw", "runner", "tree", "dig", "balloon", "dive"] },
  { name: "Spokój i ćwiczenia", games: ["rock", "calm", "race", "warmup"] },
  { name: "Kompas i barometr", games: ["forage", "climb"] },
  { name: "Na spacer (GPS)", games: ["trip", "marks"] },
  { name: "Bez ruchu", games: ["guess"] },
];

export const GAME_NAMES = {
  simon: "Powtórz ruch",
  catch: "Łapanie owoców",
  eggroll: "Labirynt żołędzia",
  aim: "Celowanie",
  balance: "Balans na kłodzie",
  reflex: "Refleks",
  fishing: "Wędkowanie",
  throw: "Rzut piłką",
  runner: "Skoki",
  tree: "Potrząśnij drzewem",
  dig: "Wykopywanie żołędzi",
  balloon: "Balon",
  rock: "Kołysanie do snu",
  calm: "Medytacja",
  race: "Wyścig",
  warmup: "Rozgrzewka",
  forage: "Szukanie wody",
  climb: "Wspinaczka",
  dive: "Nurkowanie",
  trip: "Wyprawa",
  marks: "Znaczenie terenu",
  guess: "Lewo czy prawo?",
};

// Zadania spacerowe (klucz w s.walks)
export const WALK_GAMES = { climb: "climb", trip: "trip", marks: "marks" };

// O te gry Groot sam prosi (krótkie, bez spaceru i bez eksperymentów)
export const REQUEST_GAMES = ["simon", "catch", "eggroll", "aim", "balance", "reflex", "fishing", "throw", "runner", "tree", "balloon", "rock", "calm", "race", "forage", "guess"];

// Gra o premię po akcji: przekąska, sprzątanie, lekarstwo
export const ACTION_GAMES = {
  snack: { game: "catch", label: "Łapanie owoców" },
  clean: { game: "dig", label: "Zakopywanie" },
  medicine: { game: "aim", label: "Celowanie opryskiem" },
};

export function gamePage(id) {
  return "page/gt/" + id + "/index.page";
}
