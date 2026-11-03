// `node test/btlink.test.mjs` - połączenie z hubem przez btnode (API.md pkt 15.2-15.4) na atrapie huba:
// gotowość po pierwszym stanie, odczyt co chwilę, polecenia, wyniki 3/4, brak odpowiedzi, rozłączenie
import assert from "node:assert/strict";
import { createBtLink, nextCounter } from "../utils/btlink.js";
import { normalizeBle } from "../utils/btpoints.js";
import { createFakeHub, fakeTransport } from "./fakehub.mjs";

const KEY = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const until = async (cond, ms = 2000) => {
  const end = Date.now() + ms;
  while (!cond()) {
    if (Date.now() > end) throw new Error("czas minął");
    await wait(5);
  }
};
const TIMING = { stateEvery: 60, ackWait: 80, stateWait: 80, readyWait: 300, readyRetry: 40, retryPause: 10, reconnect: 100 };

function memStore(counter = 0) {
  const s = { counter, mac: null, saves: 0 };
  return {
    s,
    loadCounter: () => s.counter,
    saveCounter: (n) => {
      s.counter = n;
      s.saves++;
    },
    loadMac: () => s.mac,
    saveMac: (m) => {
      s.mac = m;
    },
  };
}

const cfg = normalizeBle({
  id: "zegarek-1",
  slot: 3,
  key: KEY,
  cfgVer: 4,
  points: [
    { device: "termostat-a", point: "temp" },
    { device: "termostat-a", point: "target" },
    { device: "swiatlo-1", point: "on2" },
  ],
});

// --- licznik ---
const T0 = 1700000000000 + 1000 * 100; // 1000 dziesiątych sekundy po epoce licznika
assert.equal(nextCounter(0, T0), 1000, "po reinstalacji od czasu");
assert.equal(nextCounter(5000, T0), 5001, "zapisany większy - +1");
assert.equal(nextCounter(0, 0), 1, "zegar sprzed epoki");

// --- normalny przebieg ---
{
  const hub = createFakeHub({ keyHex: KEY, slot: 3, cfgVer: 4, values: [{ status: 1, value: 2143 }, { status: 1, value: 2100 }, { status: 1, value: 0 }] });
  const tr = fakeTransport(hub);
  tr.failOpen = 1; // pierwsza próba połączenia nie wychodzi
  hub.mute = 2; // dwa pierwsze odczyty giną (powiadomienia jeszcze nie działają)
  const store = memStore(0);
  const link = createBtLink({ cfg, transport: tr, storage: store, timing: TIMING });
  const states = [];
  link.on("state", (s) => states.push(s));
  assert.equal(await link.command(1, 2150), null, "przed połączeniem - od razu do chmury");
  link.start();
  await until(() => link.status().ready);
  assert.equal(tr.opened, 2, "ponowienie po nieudanym łączeniu");
  assert.equal(store.s.mac, "AA:BB:CC:00:11:22", "zapamiętany adres");
  assert.ok(states.length >= 1);
  assert.deepEqual(states[0].points, [{ status: 1, value: 2143 }, { status: 1, value: 2100 }, { status: 1, value: 0 }]);
  assert.equal(states[0].cloud, true);
  // odczyt co chwilę
  const before = states.length;
  await wait(200);
  assert.ok(states.length > before, "kolejne odczyty");

  // polecenie: wynik 0 z nową wartością
  const r = await link.command(1, 2150);
  assert.equal(r.result, 0);
  assert.equal(r.value, 2150);
  assert.ok(r.counter > 0);
  assert.deepEqual(hub.commands.at(-1), { ctr: r.counter, index: 1, value: 2150 });
  assert.equal(store.s.counter, Math.max(store.s.counter, r.counter), "licznik zapisany");

  // brak potwierdzenia w oknie -> result null z licznikiem (do cmdKey)
  hub.drop = true;
  const lost = await link.command(2, 1);
  assert.deepEqual(Object.keys(lost).sort(), ["counter", "result"]);
  assert.equal(lost.result, null);
  hub.drop = false;

  // licznik za mały (np. po reinstalacji): hub podaje swój, zegarek powtarza od niego
  hub.last = store.s.counter + 1000;
  const again = await link.command(2, 1);
  assert.equal(again.result, 0, "powtórka po wyniku 3");
  assert.equal(again.counter, hub.last);
  assert.ok(hub.commands.some((c) => c.index === 2 && c.value === 1));

  // cfgVer inne w hubie: odczyt zgłasza nieaktualną listę, polecenia przestają iść przez BLE
  hub.cfgVer = 5;
  await until(() => link.status().cfgStale);
  assert.equal(link.canCommand(), false);
  assert.equal(await link.command(2, 0), null);
  // nowa lista z telefonu
  link.setConfig({ ...cfg, cfgVer: 5 });
  await until(() => !link.status().cfgStale && link.canCommand());

  // polecenie ze starą listą: cfgVer w HMAC (pkt 15.2) - hub odrzuca wynikiem 1, odczyt stanu pokazuje inną listę
  hub.cfgVer = 6;
  const old = await link.command(2, 1);
  assert.equal(old.result, 1);
  await until(() => link.status().cfgStale);
  assert.equal(link.status().keyBad, false, "inna lista to nie zły klucz");
  link.setConfig({ ...cfg, cfgVer: 6 });
  await until(() => link.canCommand());
  assert.equal((await link.command(2, 1)).result, 0, "z nową listą działa");

  // wynik 1 przy tej samej liście: klucz nieważny - polecenia już tylko przez chmurę
  hub.badKey = true;
  assert.equal((await link.command(2, 0)).result, 1);
  await until(() => link.status().keyBad);
  assert.equal(link.status().cfgStale, false);
  assert.equal(link.canCommand(), false);
  assert.equal(await link.command(2, 0), null);
  hub.badKey = false;
  link.setConfig({ ...cfg, cfgVer: 6 }); // nowy klucz z telefonu
  assert.equal(link.status().keyBad, false);
  await until(() => link.canCommand());

  // rozłączenie -> ponowne łączenie
  const opened = tr.opened;
  tr.disconnect();
  assert.equal(link.status().ready, false);
  await until(() => link.status().ready && tr.opened > opened, 3000);
  link.stop();
  assert.equal(link.status().ready, false);
}

// --- hub nie odpowiada: kilka nieudanych odczytów z rzędu = połączenie zamykane i ponawiane ---
{
  const hub = createFakeHub({ keyHex: KEY, slot: 3, cfgVer: 4, values: [{ status: 1, value: 1 }, { status: 1, value: 1 }, { status: 1, value: 1 }] });
  const tr = fakeTransport(hub);
  const link = createBtLink({ cfg, transport: tr, storage: memStore(0), timing: TIMING });
  link.start();
  await until(() => link.status().ready);
  hub.drop = true;
  await until(() => !link.status().ready, 3000);
  assert.ok(tr.closed >= 1);
  hub.drop = false;
  await until(() => link.status().ready, 3000);
  link.stop();
}

// --- więcej niż 32 punkty: kilka odczytów ---
{
  const many = normalizeBle({ id: "z", slot: 3, key: KEY, cfgVer: 1, points: Array.from({ length: 40 }, (_, i) => ({ device: "d" + i, point: "on" })) });
  const hub = createFakeHub({ keyHex: KEY, slot: 3, cfgVer: 1, values: Array.from({ length: 40 }, (_, i) => ({ status: 1, value: i % 2 })) });
  const link = createBtLink({ cfg: many, transport: fakeTransport(hub), storage: memStore(0), timing: TIMING });
  const got = [];
  link.on("state", (s) => got.push([s.from, s.points.length]));
  link.start();
  await until(() => got.length >= 2);
  assert.deepEqual(got.slice(0, 2), [
    [0, 32],
    [32, 8],
  ]);
  link.stop();
}

console.log("btlink.test.mjs: OK");
