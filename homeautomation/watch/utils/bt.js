// Wspólne połączenie z hubem przez Bluetooth (API.md pkt 15) dla pulpitu i ekranu termostatu: jedno na uruchomienie
// aplikacji, w globalData. Stan z odczytów zbierany w jednym miejscu (btState), strony słuchają przez onBt.
// Bez połączenia albo bez konfiguracji wszystko idzie przez chmurę, jak wcześniej.
// Transport (utils/bttransport.js z biblioteką BLE) podaje pulpit - ekran termostatu go nie dołącza.
import { createBtLink } from "./btlink.js";
import { btDevices, pointIndex, encodeValue, decodeValue, cmdKeyOf } from "./btpoints.js";
import { R_OK, R_FORBIDDEN, R_VALUE } from "./btframes.js";
import { btStorage } from "./btstore.js";

export const BT_FRESH_MS = 15000; // stan z Bluetooth starszy niż tyle nie jest już aktualny (odczyt co 5 s)

function gd() {
  try {
    return getApp()._options.globalData;
  } catch (e) {
    return null;
  }
}

const sigOf = (cfg) => JSON.stringify(cfg);

function emit(g) {
  (g.btListeners || []).slice().forEach((fn) => {
    try {
      fn();
    } catch (e) {}
  });
}

// Uruchamia połączenie dla konfiguracji z telefonu (albo z pamięci zegarka); nowa konfiguracja = nowa lista punktów.
// null zatrzymuje połączenie (zegarek nie ma już pilota). makeTransport - utils/bttransport.js createBleTransport.
export function ensureBt(cfg, makeTransport) {
  const g = gd();
  if (!g) return null;
  if (!cfg) {
    stopBt();
    return null;
  }
  const sig = sigOf(cfg);
  if (g.bt) {
    if (g.btSig !== sig) {
      g.btSig = sig;
      g.btState = {};
      g.bt.setConfig(cfg);
      emit(g);
    }
    return g.bt;
  }
  // tools/smoke.mjs podstawia tu atrapę huba
  const transport = (g.btTransportFactory || makeTransport)();
  const link = createBtLink({ cfg, transport, storage: g.btStorage || btStorage });
  g.bt = link;
  g.btSig = sig;
  g.btState = {};
  g.btAt = 0;
  link.on("state", (s) => {
    const part = btDevices(link.config(), s.from, s.points);
    Object.keys(part).forEach((id) => {
      const prev = s.from > 0 ? g.btState[id] : null; // urządzenie może mieć punkty w obu ramkach odczytu
      g.btState[id] = {
        online: part[id].online || !!(prev && prev.online),
        values: { ...((prev && prev.values) || {}), ...part[id].values },
      };
    });
    g.btAt = Date.now();
    emit(g);
  });
  link.on("status", () => emit(g));
  link.start();
  return link;
}

export function stopBt() {
  const g = gd();
  if (!g || !g.bt) return;
  try {
    g.bt.stop();
  } catch (e) {}
  g.bt = null;
  g.btSig = null;
  g.btState = {};
  g.btAt = 0;
  emit(g);
}

// Słuchanie zmian stanu i połączenia; zwraca funkcję wypisującą
export function onBt(fn) {
  const g = gd();
  if (!g) return () => {};
  g.btListeners = g.btListeners || [];
  g.btListeners.push(fn);
  return () => {
    const i = g.btListeners.indexOf(fn);
    if (i !== -1) g.btListeners.splice(i, 1);
  };
}

// Aktualny stan z Bluetooth { urządzenie: { online, values } } albo null (brak połączenia / stary odczyt)
export function btState(now) {
  const g = gd();
  if (!g || !g.bt || !g.bt.status().ready || !g.btAt) return null;
  if ((now || Date.now()) - g.btAt > BT_FRESH_MS) return null;
  return g.btState || null;
}

// Źródło stanu do ikony przy tytule: "bt" | "cloud" | "none"
export function stateSource(cloudOk, now) {
  if (btState(now)) return "bt";
  return cloudOk ? "cloud" : "none";
}

// Polecenie jednego punktu przez Bluetooth (pkt 15.4). arg - id sceny dla runScene.
// -> null: brak połączenia albo punktu na liście pilota - zwykła droga przez chmurę;
//    { done: true }: hub potwierdził (wynik 0), stan z potwierdzenia już w btState;
//    { error: "..." }: hub odmówił (2 - uprawnienia, 6 - zła wartość) - chmura też odmówi;
//    { cmdKey }: brak potwierdzenia albo wynik 1/4/5 - to samo polecenie przez chmurę z tym kluczem.
export async function btSend(device, point, value, arg) {
  const g = gd();
  const link = g && g.bt;
  if (!link || !link.canCommand()) return null;
  const cfg = link.config();
  const i = pointIndex(cfg, device, point, arg);
  if (i === -1) return null;
  const raw = encodeValue(cfg.points[i], value);
  if (raw === null) return null;
  const r = await link.command(i, raw);
  if (!r) return null;
  if (r.result === R_OK) {
    const p = cfg.points[i];
    const v = decodeValue(p, r.value);
    if (v !== null && g.btState) {
      const d = g.btState[device] || { online: true, values: {} };
      g.btState[device] = { online: true, values: { ...d.values, [point]: v } };
      emit(g);
    }
    return { done: true };
  }
  if (r.result === R_FORBIDDEN) return { error: "Brak uprawnień" };
  if (r.result === R_VALUE) return { error: "Zła wartość" };
  return { cmdKey: cmdKeyOf(cfg, r.counter) };
}
