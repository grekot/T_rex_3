// Transport BLE zegarka do węzła btnode (`HA-BT`) na bibliotece easy-ble - tak jak w aplikacji pomiarowej
// homeautomation/bt-proba (czasy i ponawianie stamtąd). Interfejs jak w utils/btlink.js:
// { open(lastMac) -> Promise<{ mac }>, write(Uint8Array), close(), onFrame(cb), onClose(cb) }
import { BLEMaster } from "@silver-zepp/easy-ble";

const DEVICE_NAME = "HA-BT";
const SERVICE_UUID = "FFA0";
const CMD_UUID = "FFA1";
const EVT_UUID = "FFA2";
const CCCD_UUID = "2902";

const SCAN_TIMEOUT_MS = 8000;
const SCAN_PICK_MS = 1000; // po pierwszym znalezionym węźle jeszcze tyle zbieramy, żeby wybrać najsilniejszy
const CONNECT_TIMEOUT_MS = 8000;
const PROFILE_TIMEOUT_MS = 2500; // zwykle ok. 950 ms; dłużej = połączenie nie powstało (pomiar BT proba)

function timeout(promise, ms, what) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(what)), ms);
    promise.then(
      (v) => {
        clearTimeout(timer);
        resolve(v);
      },
      (e) => {
        clearTimeout(timer);
        reject(e);
      }
    );
  });
}

export function createBleTransport() {
  let ble = null;
  let connected = false;
  let badMac = null; // ostatnio zapamiętany węzeł nie odpowiedział - następnym razem skan
  let frameCb = () => {};
  let closeCb = () => {};

  // Skan: węzły HA-BT, po pierwszym jeszcze SCAN_PICK_MS i wybór najsilniejszego (kilka węzłów dla zasięgu)
  function scanStrongest(m) {
    return timeout(
      new Promise((resolve, reject) => {
        let best = null;
        let picking = false;
        const started = m.startScan(
          (d) => {
            if (!d || d.dev_name !== DEVICE_NAME) return;
            const rssi = typeof d.rssi === "number" ? d.rssi : -999;
            if (!best || rssi > best.rssi) best = { mac: d.dev_addr, rssi };
            if (picking) return;
            picking = true;
            setTimeout(() => {
              try {
                m.stopScan();
              } catch (e) {}
              resolve(best.mac);
            }, SCAN_PICK_MS);
          },
          { allow_duplicates: true, throttle_interval: 200 }
        );
        if (!started) reject(new Error("skan nie ruszył"));
      }),
      SCAN_TIMEOUT_MS,
      "nie znaleziono " + DEVICE_NAME
    );
  }

  function connect(m, mac) {
    return timeout(
      new Promise((resolve, reject) => {
        let up = false;
        m.connect(mac, (r) => {
          if (r && r.connected) {
            up = true;
            resolve();
          } else if (up || connected) {
            // zerwane po zestawieniu
            if (ble === m && connected) {
              connected = false;
              closeCb();
            }
          } else {
            reject(new Error("łączenie: " + (r && r.status)));
          }
        });
      }),
      CONNECT_TIMEOUT_MS,
      "łączenie: brak odpowiedzi"
    );
  }

  function prepare(m) {
    const services = {};
    services[SERVICE_UUID] = {};
    services[SERVICE_UUID][CMD_UUID] = [];
    services[SERVICE_UUID][EVT_UUID] = [CCCD_UUID];
    const profile = m.generateProfileObject(services);
    return timeout(
      new Promise((resolve, reject) => {
        m.startListener(profile, (r) => (r && r.success ? resolve() : reject(new Error("profil: " + (r && r.message)))));
      }),
      PROFILE_TIMEOUT_MS,
      "profil: brak odpowiedzi"
    );
  }

  const t = {
    async open(lastMac) {
      t.close();
      const m = new BLEMaster();
      ble = m;
      let mac = lastMac && lastMac !== badMac ? lastMac : null;
      if (!mac) mac = await scanStrongest(m);
      try {
        await connect(m, mac);
        await prepare(m);
      } catch (e) {
        badMac = mac;
        throw e;
      }
      badMac = null;
      m.on.charaNotification((uuid, data, length) => {
        if (ble !== m) return;
        const bytes = new Uint8Array(data);
        frameCb(length && length < bytes.length ? bytes.slice(0, length) : bytes);
      });
      // Bez tego zdarzenia kolejka biblioteki czeka na koniec zapisu CCCD pełne 5 s i blokuje kolejne zapisy
      m.on.descWriteComplete(() => {});
      m.write.enableCharaNotifications(EVT_UUID, true);
      connected = true;
      return { mac };
    },
    write(bytes) {
      if (!ble || !connected) throw new Error("brak połączenia");
      const buf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length);
      ble.write.characteristic(CMD_UUID, buf, true); // bez odpowiedzi - jak w BT proba (zapis -> powiadomienie ok. 95 ms)
    },
    close() {
      connected = false;
      const m = ble;
      ble = null;
      if (!m) return;
      try {
        m.quit();
      } catch (e) {}
    },
    onFrame(cb) {
      frameCb = cb;
    },
    onClose(cb) {
      closeCb = cb;
    },
  };
  return t;
}
