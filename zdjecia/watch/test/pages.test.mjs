// `node test/pages.test.mjs` - która strona jest na wierzchu (panel w tle nie rysuje na ustawieniach)
import assert from "node:assert/strict";
import { getTop, setTop, isTop, onReturn, returnTo } from "../utils/pages.js";

// Bez aplikacji (brak getApp) - wszystko „na wierzchu”, nic się nie wywraca
assert.equal(getTop(), "");
assert.equal(isTop("home"), true);
setTop("home");
returnTo("home");

const globalData = {};
globalThis.getApp = () => ({ _options: { globalData } });

assert.equal(isTop("home"), true, "nieznany stan = na wierzchu");
setTop("home");
assert.equal(isTop("home"), true);
let back = 0;
onReturn("home", () => back++);

// Panel otwiera ustawienia
setTop("settings");
assert.equal(isTop("home"), false);
assert.equal(isTop("settings"), true);

// Ustawienia zamknięte - powrót do panelu z powiadomieniem
returnTo("home");
assert.equal(getTop(), "home");
assert.equal(back, 1);

// Zdjęcie z budzika nad panelem i powrót; zdjęcie bez aplikacji pod spodem
setTop("photo");
assert.equal(isTop("home"), false);
returnTo("home");
assert.equal(back, 2);
setTop("photo");
returnTo("");
assert.equal(isTop("home"), true);
assert.equal(back, 2);

// Błąd w powiadomieniu nie wywraca zamykanej strony
onReturn("home", () => {
  throw new Error("x");
});
returnTo("home");
assert.equal(getTop(), "home");

console.log("pages OK");
