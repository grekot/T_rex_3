// Side Service - działa w aplikacji Zepp na telefonie.
// Pobiera listę zdjęć z mostu lokalnego (aplikacja „Zdjęcia” na tym samym telefonie), a potem każde nowe zdjęcie:
// pobiera PNG → konwertuje do formatu zegarka (image.convert) → przesyła przez Bluetooth (TransferFile).
// Każdy krok mierzy czas i raportuje zegarkowi przez this.call(), bo to jest etap próbny.
import { BaseSideService, convertLib } from "@zeppos/zml/base-side";
import {
  BRIDGE_URL,
  TEST_IMAGE_URL,
  TEST_IMAGE_ID,
  parseManifest,
  photosToFetch,
  watchFileName,
  photoUrl,
} from "../utils/sync";

const TRANSFER_TIMEOUT_MS = 10 * 60 * 1000;

let busy = false;

function errText(e) {
  if (!e) return "nieznany błąd";
  if (typeof e === "string") return e;
  return e.message || JSON.stringify(e);
}

AppSideService(
  BaseSideService({
    onInit() {},
    onRun() {},
    onDestroy() {},

    onRequest(req, res) {
      const p = req.params || {};
      if (req.method === "SYNC") return this.startSync(p.have || [], Number(p.max) || 0, res);
      if (req.method === "TEST_NET") return this.startTestNet(res);
      res("nieznana metoda: " + req.method);
    },

    // max > 0: najwyżej tyle nowych zdjęć (zdjęcie wyskoczyło samo - krótko); 0: wszystkie nowe
    async startSync(have, max, res) {
      if (busy) return res(null, { ok: false, step: "busy", error: "przesyłanie już trwa" });
      const t0 = Date.now();
      let photos;
      try {
        const r = await this.fetch({ url: BRIDGE_URL + "/manifest.json", method: "GET", timeout: 8000 });
        if (r.status && r.status !== 200) throw new Error("HTTP " + r.status);
        photos = parseManifest(r.body);
      } catch (e) {
        return res(null, { ok: false, step: "manifest", error: errText(e), url: BRIDGE_URL });
      }
      const todo = photosToFetch(photos, have, max);
      // pool: cała pula telefonu - zegarek skasuje zdjęcia, które z niej wypadły
      res(null, {
        ok: true,
        total: photos.length,
        todo: todo.length,
        manifestMs: Date.now() - t0,
        pool: photos.map((p) => p.id),
      });
      this.runQueue(
        todo.map((p) => ({ id: p.id, url: photoUrl(p.id), png: p.size, taken: p.taken, caption: p.caption }))
      );
    },

    startTestNet(res) {
      if (busy) return res(null, { ok: false, step: "busy", error: "przesyłanie już trwa" });
      res(null, { ok: true, total: 1, todo: 1, manifestMs: 0 });
      this.runQueue([{ id: TEST_IMAGE_ID, url: TEST_IMAGE_URL, png: 0, taken: 0, test: true }]);
    },

    async runQueue(items) {
      busy = true;
      const t0 = Date.now();
      let sent = 0;
      for (let i = 0; i < items.length; i++) {
        const ok = await this.processOne(items[i], i, items.length);
        if (ok) sent++;
      }
      busy = false;
      this.call({ type: "DONE", sent, count: items.length, ms: Date.now() - t0 });
    },

    async processOne(item, index, count) {
      const name = watchFileName(item.id);
      const path = "data://download/" + name;
      const info = { id: item.id, name, index, count };
      let step = "download";
      try {
        this.call({ type: "STEP", ...info, step });
        let t = Date.now();
        const dl = await this.downloadAsync(item.url, path);
        const dlMs = Date.now() - t;
        const downloaded = dl.filePath || dl.tempFilePath || path;

        step = "convert";
        this.call({ type: "STEP", ...info, step, dlMs });
        t = Date.now();
        const cv = await convertLib.convert({ filePath: downloaded, targetFilePath: path });
        const cvMs = Date.now() - t;
        const conv = cv && cv.options ? cv.options.size : undefined;
        const converted = (cv && cv.targetFilePath) || path;

        step = "send";
        this.call({ type: "STEP", ...info, step, dlMs, cvMs, conv });
        t = Date.now();
        await this.sendAsync(converted, {
          id: item.id,
          name,
          png: item.png || dl.size,
          conv,
          dlMs,
          cvMs,
          taken: item.taken,
          caption: item.caption || "",
          test: !!item.test,
        });
        this.call({ type: "SENT", ...info, dlMs, cvMs, conv, txMs: Date.now() - t });
        return true;
      } catch (e) {
        this.call({ type: "FAIL", ...info, step, error: errText(e) });
        return false;
      }
    },

    downloadAsync(url, filePath) {
      return new Promise((resolve, reject) => {
        let task;
        try {
          task = this.download(url, { timeout: 60000, filePath });
        } catch (e) {
          return reject(e);
        }
        if (!task) return reject(new Error("download() nie zwrócił zadania"));
        let size;
        task.onProgress = (ev) => {
          if (ev && ev.total) size = ev.total;
        };
        task.onSuccess = (ev) => {
          const res = ev || {};
          if (res.statusCode && res.statusCode !== 200) return reject(new Error("HTTP " + res.statusCode));
          resolve({ ...res, size });
        };
        task.onFail = (ev) => reject(new Error("pobieranie: kod " + (ev && ev.code) + " " + ((ev && ev.message) || "")));
      });
    },

    sendAsync(filePath, params) {
      return new Promise((resolve, reject) => {
        let task;
        try {
          task = this.sendFile(filePath, params);
        } catch (e) {
          return reject(e);
        }
        if (!task) return reject(new Error("sendFile() nie zwrócił zadania"));
        const timer = setTimeout(() => reject(new Error("przesyłanie trwa ponad 10 min")), TRANSFER_TIMEOUT_MS);
        const finish = (state) => {
          if (state === "transferred") {
            clearTimeout(timer);
            resolve();
          } else if (state === "error" || state === "canceled") {
            clearTimeout(timer);
            reject(new Error("przesyłanie: " + state));
          }
        };
        task.on("change", (ev) => finish(ev && ev.data ? ev.data.readyState : task.readyState));
        // Postęp co 10%, żeby wiadomości nie zabierały Bluetootha samemu plikowi
        let lastPct = -10;
        task.on("progress", (ev) => {
          const d = (ev && ev.data) || {};
          if (!d.fileSize) return;
          const pct = Math.floor((d.loadedSize * 100) / d.fileSize);
          if (pct < lastPct + 10 && pct < 100) return;
          lastPct = pct;
          this.call({ type: "PROGRESS", id: params.id, pct, total: d.fileSize });
        });
      });
    },
  })
);
