// Połączenie zegarka z hubem przez węzeł btnode (API.md pkt 15.2-15.4): łączenie w tle, odczyt stanu co 5 s,
// polecenia z oknem 500 ms, licznik ramek, wyniki 0-6. Bez API zegarka - transport i zapis licznika są wstrzykiwane
// (utils/bttransport.js na zegarku, atrapa huba w testach: test/btlink.test.mjs, tools/smoke.mjs).
//
// transport: { open(lastMac) -> Promise<{ mac }>, write(Uint8Array), close(), onFrame(cb), onClose(cb) }
// storage:   { loadCounter() -> number, saveCounter(n), loadMac() -> string|null, saveMac(mac) }
import { commandFrame, stateFrame, decodeAck, decodeState, frameType, T_ACK, T_PART, T_END, MAX_COUNT, R_COUNTER, R_CFGVER, F_CFGVER } from "./btframes.js";
import { hexToBytes } from "./sha256.js";

export const STATE_EVERY_MS = 5000;
export const ACK_WAIT_MS = 500; // brak potwierdzenia -> droga przez chmurę (pkt 15.4)
export const STATE_WAIT_MS = 2000;
export const READY_WAIT_MS = 2500; // po połączeniu: powiadomienia działają dopiero po zapisie CCCD
export const READY_RETRY_MS = 300;
export const OPEN_TRIES = 3; // jak w BT proba: połączenie, które nie powstało, ponawiamy od razu
export const RETRY_PAUSE_MS = 200;
export const RECONNECT_MS = 8000; // po nieudanych próbach albo rozłączeniu
export const STATE_FAILS = 3; // tyle odczytów bez odpowiedzi z rzędu = połączenie martwe

// Licznik: zapisany + 1, ale nie mniejszy niż czas (dziesiąte sekundy od 2023-11) - po reinstalacji
// zegarek zwykle startuje powyżej ostatniego licznika huba i nie traci pierwszego polecenia na wynik 3.
const EPOCH_MS = 1700000000000;
export function nextCounter(stored, nowMs) {
  const byTime = Math.max(0, Math.floor((nowMs - EPOCH_MS) / 100));
  return (Math.max((stored >>> 0) + 1, byTime) >>> 0) || 1;
}

const DEFAULTS = {
  stateEvery: STATE_EVERY_MS,
  ackWait: ACK_WAIT_MS,
  stateWait: STATE_WAIT_MS,
  readyWait: READY_WAIT_MS,
  readyRetry: READY_RETRY_MS,
  retryPause: RETRY_PAUSE_MS,
  reconnect: RECONNECT_MS,
};

export function createBtLink(opts) {
  const T = { ...DEFAULTS, ...(opts.timing || {}) }; // testy skracają czasy
  const transport = opts.transport;
  const storage = opts.storage;
  const now = opts.now || (() => Date.now());
  const later = opts.setTimeout || setTimeout;
  const cancel = opts.clearTimeout || clearTimeout;
  const listeners = { state: [], status: [] };

  let cfg = opts.cfg;
  let key = hexToBytes(cfg.key);
  let counter = storage.loadCounter() >>> 0;
  let running = false;
  let ready = false;
  let opening = false;
  let cfgStale = false;
  let cloud = null; // flaga z 0x83: hub ma internet
  let stateFails = 0;
  let lastState = 0;
  let timer = null;
  let pending = null; // { type: "state", counter, parts, resolve } | { type: "ack", counter, resolve }
  let queue = Promise.resolve();

  const emit = (kind, arg) => listeners[kind].forEach((fn) => fn(arg));
  const status = () => ({ ready, cfgStale, cloud, lastState, connecting: opening });
  const changed = () => emit("status", status());

  function take() {
    counter = nextCounter(counter, now());
    storage.saveCounter(counter);
    return counter;
  }

  transport.onFrame((f) => {
    const t = frameType(f);
    const p = pending;
    if (!p) return;
    if (t === T_ACK && p.type === "ack") {
      const a = decodeAck(key, cfg.slot, f);
      if (a && a.counter === p.counter) p.resolve(a);
    } else if (t === T_PART && p.type === "state") {
      p.parts.push(f);
    } else if (t === T_END && p.type === "state") {
      const s = decodeState(key, cfg.slot, p.parts.concat([f]));
      if (s && s.counter === p.counter) p.resolve(s);
      else p.parts = [];
    }
  });

  transport.onClose(() => {
    if (!ready && !opening) return;
    drop("rozłączono");
  });

  function drop() {
    ready = false;
    if (pending) pending.resolve(null);
    try {
      transport.close();
    } catch (e) {}
    changed();
    if (running) schedule(T.reconnect);
  }

  // Jedna ramka na raz: odpowiedź (0x81 albo części + 0x83) -> wynik albo null po czasie
  function exchange(type, frame, ctr, waitMs) {
    const run = () =>
      new Promise((resolve) => {
        let done = false;
        const finish = (v) => {
          if (done) return;
          done = true;
          cancel(t);
          if (pending && pending.counter === ctr) pending = null;
          resolve(v);
        };
        const t = later(() => finish(null), waitMs);
        pending = { type, counter: ctr, parts: [], resolve: finish };
        try {
          transport.write(frame);
        } catch (e) {
          finish(null);
        }
      });
    const p = queue.then(run, run);
    queue = p.then(
      () => null,
      () => null
    );
    return p;
  }

  // Stan wszystkich punktów (po 32 w ramce) -> true, gdy hub odpowiedział
  async function readState(waitMs) {
    const n = cfg.points.length;
    let any = false;
    for (let from = 0; from < Math.max(n, 1); from += MAX_COUNT) {
      const count = Math.min(MAX_COUNT, n - from);
      const ctr = take();
      const s = await exchange("state", stateFrame(key, cfg.slot, ctr, cfg.cfgVer, from, Math.max(count, 0)), ctr, waitMs || T.stateWait);
      if (!s) return any;
      any = true;
      cloud = !!(s.flags & 0x01);
      if (s.flags & F_CFGVER) {
        if (!cfgStale) {
          cfgStale = true;
          changed();
        }
        return true;
      }
      if (cfgStale) {
        cfgStale = false;
        changed();
      }
      lastState = now();
      emit("state", { from, points: s.points, cloud });
    }
    return any;
  }

  async function open() {
    opening = true;
    changed();
    for (let tries = 1; tries <= OPEN_TRIES && running; tries++) {
      try {
        const r = await transport.open(storage.loadMac());
        // gotowość = pierwsza odpowiedź huba na odczyt stanu (ponawiany, aż zadziałają powiadomienia)
        const end = now() + T.readyWait;
        let ok = false;
        while (!ok && running && now() < end) ok = await readState(T.readyRetry);
        if (ok) {
          if (r && r.mac) storage.saveMac(r.mac);
          opening = false;
          ready = true;
          stateFails = 0;
          changed();
          return true;
        }
      } catch (e) {}
      try {
        transport.close();
      } catch (e) {}
      await new Promise((res) => later(res, T.retryPause));
    }
    opening = false;
    changed();
    return false;
  }

  function schedule(ms) {
    if (timer) cancel(timer);
    timer = later(tick, ms);
  }

  async function tick() {
    timer = null;
    if (!running) return;
    if (!ready) {
      if (!opening) {
        const ok = await open();
        schedule(ok ? T.stateEvery : T.reconnect);
      }
      return;
    }
    const ok = await readState();
    if (!running) return;
    if (ok) stateFails = 0;
    else if (++stateFails >= STATE_FAILS) return drop();
    schedule(T.stateEvery);
  }

  return {
    start() {
      if (running) return;
      running = true;
      schedule(0);
    },
    stop() {
      running = false;
      if (timer) cancel(timer);
      timer = null;
      ready = false;
      if (pending) pending.resolve(null);
      try {
        transport.close();
      } catch (e) {}
    },
    // Nowa lista punktów / klucz z telefonu
    setConfig(next) {
      const keyChanged = next.key !== cfg.key || next.slot !== cfg.slot;
      cfg = next;
      key = hexToBytes(cfg.key);
      cfgStale = false;
      if (keyChanged && ready) drop();
      changed();
    },
    config: () => cfg,
    status,
    canCommand: () => ready && !cfgStale,
    // Polecenie przez BLE -> { result, value, counter } albo { result: null, counter } (brak potwierdzenia);
    // null, gdy nie ma połączenia. Wynik 3: licznik od huba i jedna powtórka.
    async command(index, value) {
      if (!ready || cfgStale) return null;
      let ctr = take();
      let a = await exchange("ack", commandFrame(key, cfg.slot, ctr, index, value), ctr, T.ackWait);
      if (a && a.result === R_COUNTER) {
        counter = a.value >>> 0;
        storage.saveCounter(counter);
        ctr = take();
        a = await exchange("ack", commandFrame(key, cfg.slot, ctr, index, value), ctr, T.ackWait);
      }
      if (a && a.result === R_CFGVER && !cfgStale) {
        cfgStale = true;
        changed();
      }
      return a ? { result: a.result, value: a.value, counter: ctr } : { result: null, counter: ctr };
    },
    on(kind, fn) {
      listeners[kind].push(fn);
      return () => {
        const i = listeners[kind].indexOf(fn);
        if (i !== -1) listeners[kind].splice(i, 1);
      };
    },
  };
}
