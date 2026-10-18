// Pamięć zegarka: przerwana partia (żeby wrócić do niej po wyjściu z aplikacji) i rekordy.
import { LocalStorage } from "@zos/storage";
import { restoreGame } from "./mines.js";

const storage = new LocalStorage();
const GAME_KEY = "saper_game";
const STATS_KEY = "saper_stats";

function read(key) {
  try {
    return storage.getItem(key) || "";
  } catch (e) {
    return "";
  }
}

function write(key, value) {
  try {
    storage.setItem(key, JSON.stringify(value));
  } catch (e) {}
}

export function loadGame() {
  const raw = read(GAME_KEY);
  return raw ? restoreGame(raw) : null;
}

export function saveGame(game) {
  write(GAME_KEY, game);
}

export function clearGame() {
  try {
    storage.removeItem(GAME_KEY);
  } catch (e) {}
}

export function loadStats() {
  try {
    const stats = JSON.parse(read(STATS_KEY) || "{}");
    return stats && typeof stats === "object" ? stats : {};
  } catch (e) {
    return {};
  }
}

export function saveStats(stats) {
  write(STATS_KEY, stats);
}
