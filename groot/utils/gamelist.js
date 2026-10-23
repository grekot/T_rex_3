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
  simon: "Taniec Groota",
  catch: "Części dla Rocketa",
  eggroll: "Pilotaż Milano",
  aim: "Strzała Yondu",
  balance: "Balans na belce",
  reflex: "Refleks",
  fishing: "Ryby na Knowhere",
  throw: "Rzut Orbem",
  runner: "Ucieczka przed Abiliskiem",
  tree: "Potrząśnij drzewem",
  dig: "Płetwa Yondu",
  balloon: "Bomba Rocketa",
  rock: "Kołysanie do snu",
  calm: "Medytacja z Mantis",
  race: "Wyścig z Rocketem",
  warmup: "Trening z Draxem",
  forage: "Łapanie sygnału",
  climb: "Wspinaczka",
  dive: "Kamień Nieskończoności",
  trip: "Wyprawa po Orb",
  marks: "Nadajniki",
  guess: "Lewo czy prawo?",
};

// Zadania spacerowe (klucz w s.walks)
export const WALK_GAMES = { climb: "climb", trip: "trip", marks: "marks" };

// O te gry Groot sam prosi (krótkie, bez spaceru i bez eksperymentów)
export const REQUEST_GAMES = ["simon", "catch", "eggroll", "aim", "balance", "reflex", "fishing", "throw", "runner", "tree", "balloon", "rock", "calm", "race", "forage", "guess"];

// Gra o premię po akcji: nawóz/lody, grabienie, oprysk
export const ACTION_GAMES = {
  snack: { game: "catch", label: "Części dla Rocketa" },
  clean: { game: "dig", label: "Płetwa Yondu" },
  medicine: { game: "aim", label: "Strzała Yondu" },
};

export function gamePage(id) {
  return "page/gt/" + id + "/index.page";
}
