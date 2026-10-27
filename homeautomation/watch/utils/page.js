// Wspólne dla stron: żądania do Side Service, komunikaty, która strona jest na wierzchu.
import * as hmUI from "@zos/ui";
import { showToast } from "@zos/interaction";

const REQUEST_TIMEOUT_MS = 15000;

function globalData() {
  try {
    return getApp()._options.globalData;
  } catch (e) {
    return null;
  }
}

// Żądanie do Side Service z własnym limitem czasu (BasePage.request zawsze czeka 60 s)
export function ask(page, data) {
  const g = globalData();
  if (g && g.messaging) return g.messaging.request(data, { timeout: REQUEST_TIMEOUT_MS });
  return page.request(data);
}

// Strona pod inną (otwartą przez push) nie może tworzyć widżetów - pojawiłyby się na tej z wierzchu.
// Strony zapisują tu swoją nazwę przy otwarciu i oddają wierzch przy zamknięciu.
export function setTop(name) {
  const g = globalData();
  if (g) g.top = name;
}

export function isTop(name) {
  const g = globalData();
  return !g || !g.top || g.top === name;
}

export function onTap(widgets, handler) {
  widgets.forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, handler));
}

export function toast(text) {
  try {
    showToast({ content: text });
  } catch (e) {}
}

export function parseParams(params) {
  try {
    return typeof params === "string" ? JSON.parse(params) : params || {};
  } catch (e) {
    return {};
  }
}
