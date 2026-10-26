// Która strona aplikacji jest na wierzchu. Strona w tle nie może tworzyć widżetów: trafiłyby na ekran
// strony z wierzchu (panel przebudowany w tle po odebraniu zdjęcia rysował się na ustawieniach).
// Stan w globalData aplikacji, wspólny dla wszystkich stron.

function globalData() {
  try {
    return getApp()._options.globalData;
  } catch (e) {
    return null;
  }
}

export function getTop() {
  const d = globalData();
  return (d && d.top) || "";
}

export function setTop(name) {
  const d = globalData();
  if (d) d.top = name;
}

// Nieznany stan (brak globalData) traktujemy jak „na wierzchu”, żeby panel nie przestał się odświeżać
export function isTop(name) {
  const top = getTop();
  return !top || top === name;
}

// Powrót do strony: ta, która była na wierzchu, przy zamknięciu woła powiadomienie zapisane przez stronę pod spodem
export function onReturn(name, fn) {
  const d = globalData();
  if (!d) return;
  d.onReturn = d.onReturn || {};
  d.onReturn[name] = fn;
}

export function returnTo(name) {
  setTop(name);
  const d = globalData();
  const fn = d && d.onReturn && d.onReturn[name];
  if (fn) {
    try {
      fn();
    } catch (e) {}
  }
}
