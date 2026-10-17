// Nazwy i identyfikatory miejsc - czyste funkcje, testy w test/points.test.mjs.

export const PRESET_NAMES = ["Auto", "Rower", "Namiot", "Hotel", "Dom"];

// Identyfikator jak w Firestore (20 znaków) - nowe miejsca dostają go już na zegarku
const ID_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

export function newId(rnd = Math.random) {
  let id = "";
  for (let i = 0; i < 20; i++) id += ID_CHARS.charAt(Math.floor(rnd() * ID_CHARS.length));
  return id;
}

export function cleanName(name) {
  return String(name || "")
    .trim()
    .replace(/\s+/g, " ")
    .slice(0, 40);
}

// "Punkt 1", "Punkt 2", ... - pierwszy wolny numer
export function defaultName(places) {
  const taken = {};
  places.forEach((p) => {
    taken[String(p.name).toLowerCase()] = true;
  });
  let i = 1;
  while (taken["punkt " + i]) i++;
  return "Punkt " + i;
}
