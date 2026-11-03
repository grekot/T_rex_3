// `node test/btframes.test.mjs` - SHA-256/HMAC i ramki Bluetooth (API.md pkt 15.2) na wektorach
// z SmartTermostatOLED/docs/BTNODE_GATT_WEKTORY.md (te same bajty sprawdza hub: hub/test/test_remote)
import assert from "node:assert/strict";
import { createHash, createHmac } from "node:crypto";
import { sha256, hmacSha256, hexToBytes, bytesToHex } from "../utils/sha256.js";
import { commandFrame, stateFrame, decodeAck, decodeState, frameType, R_OK, R_COUNTER, F_CLOUD, F_CFGVER, S_ONLINE, S_NO_VALUE } from "../utils/btframes.js";

// --- SHA-256 / HMAC: porównanie z node:crypto i RFC 4231 ---
for (const len of [0, 1, 3, 55, 56, 63, 64, 65, 100, 200]) {
  const data = Uint8Array.from({ length: len }, (_, i) => (i * 37 + 11) & 0xff);
  assert.equal(bytesToHex(sha256(data)), createHash("sha256").update(data).digest("hex"), "sha256 dł. " + len);
  for (const klen of [0, 16, 32, 64, 80]) {
    const key = Uint8Array.from({ length: klen }, (_, i) => (i * 13 + 5) & 0xff);
    assert.equal(bytesToHex(hmacSha256(key, data)), createHmac("sha256", key).update(data).digest("hex"), `hmac ${klen}/${len}`);
  }
}
// RFC 4231, test 2 ("Jefe")
assert.equal(
  bytesToHex(hmacSha256(new TextEncoder().encode("Jefe"), new TextEncoder().encode("what do ya want for nothing?"))),
  "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
);
assert.deepEqual(Array.from(hexToBytes("00ff10")), [0, 255, 16]);

// --- wektory ramek ---
const KEY = hexToBytes("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f");
const SLOT = 3;
const hex = (b) => bytesToHex(b);

// Zegarek -> hub
// 0x01: MAC z bajtów ramki + cfgVer listy (2 B, niewysyłany) - API.md 15.2 od 7097c77. Wektory w BTNODE_GATT_WEKTORY.md
// są jeszcze sprzed tej zmiany (sesja btnode-hub je aktualizuje) - do tego czasu sprawdzenie niezależnym HMAC z node:crypto.
const macOf = (bytes) => createHmac("sha256", Buffer.from(KEY)).update(Buffer.from(bytes)).digest().subarray(0, 8).toString("hex");
for (const [ctr, index, value, cfgVer, body] of [
  [1000, 2, 2150, 4, "010103000003e80200000866"],
  [1001, 0, 1, 4, "010103000003e90000000001"],
  [1002, 5, -250, 0x1234, "010103000003ea05ffffff06"],
]) {
  const f = hex(commandFrame(KEY, SLOT, ctr, index, value, cfgVer));
  assert.equal(f.slice(0, 24), body);
  assert.equal(f.slice(24), macOf([...hexToBytes(body), cfgVer >> 8, cfgVer & 0xff]), "MAC z cfgVer " + cfgVer);
}
assert.notEqual(hex(commandFrame(KEY, SLOT, 1000, 2, 2150, 4)), hex(commandFrame(KEY, SLOT, 1000, 2, 2150, 5)), "inna lista - inny MAC");
assert.equal(hex(stateFrame(KEY, SLOT, 1003, 4, 0, 5)), "010203000003eb00040005595a983940061d98");
assert.equal(commandFrame(KEY, SLOT, 1, 0, 0).length, 20, "ramka polecenia 20 B");
assert.equal(stateFrame(KEY, SLOT, 1, 0, 0, 0).length, 19);

// Hub -> zegarek: potwierdzenia
const ACK_OK = "018103000003e80000000866ec7f053cb33f9d89";
assert.deepEqual(decodeAck(KEY, SLOT, hexToBytes(ACK_OK)), { counter: 1000, result: R_OK, value: 2150 });
assert.deepEqual(decodeAck(KEY, SLOT, hexToBytes("018103000003e903000005dcbae332a651a3ac36")), {
  counter: 1001,
  result: R_COUNTER,
  value: 1500,
});
const badMac = hexToBytes(ACK_OK);
assert.equal(badMac.length, 20, "0x81 bez indeksu - 20 B (API.md 15.2)");
badMac[19] ^= 1;
assert.equal(decodeAck(KEY, SLOT, badMac), null, "zły MAC");
assert.equal(decodeAck(KEY, 4, hexToBytes(ACK_OK)), null, "inny slot");
assert.equal(decodeAck(KEY, SLOT, hexToBytes("018103000003e8000200000866c79f9116664e3ebf")), null, "dawna ramka 21 B");
assert.equal(decodeAck(KEY, SLOT, hexToBytes("0181030000")), null, "za krótka");

// Stan: dwie części + koniec
const state = decodeState(KEY, SLOT, [
  hexToBytes("0182030001000008660100000001010000000000"),
  hexToBytes("01820301000000000300000000"),
  hexToBytes("018303000003eb020004015eefe31e226f825b"),
]);
assert.deepEqual(state, {
  counter: 1003,
  cfgVer: 4,
  flags: F_CLOUD,
  points: [
    { status: S_ONLINE, value: 2150 },
    { status: S_ONLINE, value: 1 },
    { status: S_ONLINE, value: 0 },
    { status: 0, value: 0 },
    { status: S_ONLINE | S_NO_VALUE, value: 0 },
  ],
});
// cfgVer inne: sama 0x83 z flagą 2
assert.deepEqual(decodeState(KEY, SLOT, [hexToBytes("018303000003eb00000503dbfa01b6e99c49ef")]), {
  counter: 1003,
  cfgVer: 5,
  flags: F_CLOUD | F_CFGVER,
  points: [],
});
// podmieniona część albo zła kolejność - odrzucone
const part0 = hexToBytes("0182030001000008660100000001010000000000");
part0[6] ^= 1;
assert.equal(decodeState(KEY, SLOT, [part0, hexToBytes("01820301000000000300000000"), hexToBytes("018303000003eb020004015eefe31e226f825b")]), null);
assert.equal(
  decodeState(KEY, SLOT, [hexToBytes("01820301000000000300000000"), hexToBytes("0182030001000008660100000001010000000000"), hexToBytes("018303000003eb020004015eefe31e226f825b")]),
  null
);
assert.equal(decodeState(KEY, SLOT, [hexToBytes("018303000003eb020004015eefe31e226f825b")]), null, "brak części");
assert.equal(frameType(hexToBytes("0182030001")), 0x82);
assert.equal(frameType(hexToBytes("5001")), null);

console.log("btframes.test.mjs: OK");
