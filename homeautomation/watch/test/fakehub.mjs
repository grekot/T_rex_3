// Atrapa huba z węzłem btnode do testów (Node): odpowiada na ramki zegarka jak hub (API.md pkt 15.2),
// z budową ramek 0x81 / 0x82 / 0x83 jak w SmartTermostatOLED hub/lib/HubCore/src/RemoteFrame.cpp.
import { hmacSha256, hexToBytes } from "../utils/sha256.js";

const put32 = (a, v) => a.push((v >>> 24) & 0xff, (v >>> 16) & 0xff, (v >>> 8) & 0xff, v & 0xff);
const get32 = (f, i) => ((f[i] << 24) | (f[i + 1] << 16) | (f[i + 2] << 8) | f[i + 3]) | 0;
const mac8 = (key, bytes) => Array.from(hmacSha256(key, bytes)).slice(0, 8);

export function ackFrame(key, slot, reqCounter, result, value) {
  const a = [1, 0x81, slot];
  put32(a, reqCounter >>> 0);
  a.push(result);
  put32(a, value | 0);
  return Uint8Array.from(a.concat(mac8(key, a)));
}

export function stateFrames(key, slot, reqCounter, cfgVer, flags, points) {
  const out = [];
  const stream = [];
  if (!(flags & 2)) points.forEach((p) => {
    stream.push(p.status);
    put32(stream, p.value | 0);
  });
  let signedBytes = [];
  for (let off = 0, part = 0; off < stream.length; off += 16, part++) {
    const f = [1, 0x82, slot, part].concat(stream.slice(off, off + 16));
    signedBytes = signedBytes.concat(f);
    out.push(Uint8Array.from(f));
  }
  const end = [1, 0x83, slot];
  put32(end, reqCounter >>> 0);
  end.push(out.length, (cfgVer >> 8) & 0xff, cfgVer & 0xff, flags);
  signedBytes = signedBytes.concat(end);
  out.push(Uint8Array.from(end.concat(mac8(key, signedBytes))));
  return out;
}

// Hub: stan punktów (values[i] = {status, value}), ostatni licznik, cfgVer; send(frame) = powiadomienie do zegarka.
// Opcje: drop (gubi odpowiedzi), delayMs, notifyReady (ile pierwszych ramek po połączeniu przepada - CCCD).
export function createFakeHub({ keyHex, slot, cfgVer, values, onCommand }) {
  const key = hexToBytes(keyHex);
  const hub = {
    key,
    slot,
    cfgVer,
    values,
    last: 0,
    flags: 1,
    frames: [],
    commands: [],
    drop: false,
    mute: 0,
    receive(f, send) {
      hub.frames.push(f);
      if (hub.drop) return;
      if (hub.mute > 0) {
        hub.mute--;
        return;
      }
      // węzeł odsyła echo każdego zapisu, który nie zaczyna się wersją protokołu (sprawdzenie CCCD przez 0x50)
      if (f[0] !== 1) return send(Uint8Array.from(f));
      if (f[0] !== 1 || f[2] !== slot) return;
      const ctr = get32(f, 3) >>> 0;
      const body = Array.from(f).slice(0, f.length - 8);
      // polecenie: HMAC także z cfgVer listy (niewysyłany) - hub liczy ze swoim
      const signedBody = f[1] === 0x01 ? body.concat([(hub.cfgVer >> 8) & 0xff, hub.cfgVer & 0xff]) : body;
      const ok = !(f[1] === 0x01 && hub.badKey) && mac8(key, signedBody).every((b, i) => b === f[f.length - 8 + i]);
      if (f[1] === 0x01) {
        const index = f[7];
        const value = get32(f, 8);
        if (!ok) return send(ackFrame(key, slot, ctr, 1, 0));
        if (ctr <= hub.last) return send(ackFrame(key, slot, ctr, 3, hub.last));
        hub.last = ctr;
        hub.commands.push({ ctr, index, value });
        const r = onCommand ? onCommand(index, value) : { result: 0, value };
        if (r.result === 0 && hub.values[index]) hub.values[index] = { status: 1, value: r.value };
        return send(ackFrame(key, slot, ctr, r.result, r.value));
      }
      if (f[1] === 0x02 && ok) {
        if (ctr <= hub.last) return;
        hub.last = ctr;
        const want = (f[7] << 8) | f[8];
        const from = f[9];
        const count = f[10];
        if (want !== hub.cfgVer) return stateFrames(key, slot, ctr, hub.cfgVer, hub.flags | 2, []).forEach(send);
        stateFrames(key, slot, ctr, hub.cfgVer, hub.flags, hub.values.slice(from, from + count)).forEach(send);
      }
    },
  };
  return hub;
}

// Transport zegarka podłączony do atrapy (zamiast easy-ble). opts.defer - własne odroczenie odbioru i odpowiedzi
// (tools/smoke.mjs ma sztuczny zegar, więc odpowiedzi idą przez mikrozadania)
export function fakeTransport(hub, opts = {}) {
  const toHub = opts.defer || ((fn) => setImmediate(fn));
  const toWatch = opts.defer || ((fn) => setTimeout(fn, opts.latencyMs || 1));
  let frameCb = () => {};
  let closeCb = () => {};
  const t = {
    opened: 0,
    closed: 0,
    connected: false,
    failOpen: opts.failOpen || 0,
    async open(lastMac) {
      t.opened++;
      t.lastMacTried = lastMac;
      if (t.failOpen > 0) {
        t.failOpen--;
        throw new Error("laczenie");
      }
      t.connected = true;
      return { mac: "AA:BB:CC:00:11:22" };
    },
    write(f) {
      if (!t.connected) throw new Error("brak polaczenia");
      const copy = Uint8Array.from(f);
      toHub(() => hub.receive(copy, (resp) => t.connected && toWatch(() => frameCb(resp))));
    },
    close() {
      t.closed++;
      t.connected = false;
    },
    onFrame(cb) {
      frameCb = cb;
    },
    onClose(cb) {
      closeCb = cb;
    },
    disconnect() {
      t.connected = false;
      closeCb();
    },
  };
  return t;
}
