// Ekran zdjęcia otwierany wprost przez budzik systemowy (sposób D). Najpierw świeżo dociągnięte zdjęcie
// (niespodzianka), potem worek bez powtórek; krótko wibruje i po AUTO_CLOSE_S wraca do tarczy, chyba że ktoś
// stuknie (pierwsze stuknięcie = zostań, kolejne = następne zdjęcie z worka). Od razu uzupełnia plan budzików.
// W tle dociąga z telefonu najwyżej DRIP_MAX nowych zdjęć i kasuje te, które wypadły z puli - ekran
// czeka na to najwyżej DRIP_TIMEOUT_S, a nowe zdjęcie pokaże się przy kolejnym wyskoczeniu.
import * as hmUI from "@zos/ui";
import { home } from "@zos/router";
import { Vibrator, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { setPageBrightTime } from "@zos/display";
import { BasePage } from "@zeppos/zml/base-page";
import { loadPhotos, loadVariant, loadBag, saveBag, noteShown } from "../../../utils/store";
import { shownPhotos, readParams, haveIds, freshPick } from "../../../utils/photos";
import { pickSrc } from "../../../utils/paths";
import { takenText } from "../../../utils/format";
import { drawFromBag, AUTO_CLOSE_S } from "../../../utils/schedule";
import { refreshPlan } from "../../../utils/alarms";
import { receiveFile, cleanupAfterSync } from "../../../utils/syncflow";
import { keepScreenOn, releaseScreen } from "../../../utils/screen";
import { PHOTO_PROPS, INFO_BG_PROPS, INFO_STYLE, EMPTY_STYLE } from "zosLoader:./index.page.[pf].layout.js";

// Plan uzupełniamy chwilę po otwarciu, żeby zdjęcie pojawiło się bez czekania na budziki
const PLAN_DELAY_MS = 300;
// Synchronizację zaczynamy, gdy zdjęcie już jest na ekranie
const SYNC_DELAY_MS = 800;
// Ile nowych zdjęć dociągnąć przy jednym wyskoczeniu i jak długo najwyżej na to czekać
const DRIP_MAX = 2;
const DRIP_TIMEOUT_S = 60;

function appLaunchParams() {
  try {
    return readParams(getApp()._options.globalData.launch);
  } catch (e) {
    return {};
  }
}

// Następne zdjęcie: wskazane, świeżo dociągnięte albo z worka (worek od razu zapisany); null = brak zdjęć
function nextPhoto(wanted) {
  const list = loadPhotos();
  const photos = shownPhotos(list);
  const bag = loadBag();
  const pick = drawFromBag(bag, photos.map((p) => p.id), Math.random, wanted || freshPick(list, bag.used, Date.now()));
  if (!pick.id) return null;
  saveBag(pick.bag);
  return photos.filter((p) => p.id === pick.id)[0] || null;
}

function label(photo) {
  return photo.caption || takenText(photo.taken) || " ";
}

Page(
  BasePage({
    state: {
      launch: {},
      img: null,
      info: null,
      current: null,
      closeTimer: null,
      planTimer: null,
      syncTimer: null,
      stay: false,
      syncing: false,
      wantClose: false,
      pool: [],
    },

    onInit(params) {
      this.state.launch = readParams(params);
    },

    build() {
      const s = this.state;
      // Parametr budzika przychodzi do strony albo do app.js (zależnie od tego, czy aplikacja już działała)
      const launch = s.launch.m ? s.launch : appLaunchParams();
      const photo = nextPhoto(launch.id);
      noteShown({ id: photo ? photo.id : "", m: launch.m || "?" });
      s.planTimer = setTimeout(() => this.updatePlan(), PLAN_DELAY_MS);
      s.syncTimer = setTimeout(() => this.dripSync(), SYNC_DELAY_MS);

      if (!photo) {
        hmUI.createWidget(hmUI.widget.TEXT, {
          ...EMPTY_STYLE,
          text: "Na zegarku nie ma jeszcze zdjęć - pobieram z telefonu...",
        });
        this.autoClose();
        return;
      }
      s.current = photo;
      s.img = hmUI.createWidget(hmUI.widget.IMG, { ...PHOTO_PROPS, src: pickSrc(photo, loadVariant()) });
      s.img.addEventListener(hmUI.event.CLICK_UP, () => this.next());
      hmUI.createWidget(hmUI.widget.FILL_RECT, INFO_BG_PROPS);
      s.info = hmUI.createWidget(hmUI.widget.TEXT, {
        ...INFO_STYLE,
        text: photo.caption ? photo.caption : "Stuknij, by zostać",
      });
      this.vibrate();
      this.autoClose();
    },

    onDestroy() {
      const s = this.state;
      if (s.closeTimer) clearTimeout(s.closeTimer);
      if (s.syncTimer) clearTimeout(s.syncTimer);
      if (s.syncing) releaseScreen();
      // Zamknięte, zanim plan się uzupełnił - robimy to teraz
      if (s.planTimer) {
        clearTimeout(s.planTimer);
        this.updatePlan();
      }
    },

    updatePlan() {
      this.state.planTimer = null;
      try {
        refreshPlan();
      } catch (e) {}
    },

    // Zdjęcie samo wyskoczyło: delikatna wibracja
    vibrate() {
      try {
        const v = new Vibrator();
        v.setMode(VIBRATOR_SCENE_NOTIFICATION);
        v.start();
      } catch (e) {}
    },

    // Ekran świeci do zamknięcia, potem tarcza (chyba że trwa dociąganie zdjęć - wtedy po nim)
    autoClose() {
      const s = this.state;
      try {
        setPageBrightTime({ brightTime: (AUTO_CLOSE_S + 2) * 1000 });
      } catch (e) {}
      s.closeTimer = setTimeout(() => {
        s.closeTimer = null;
        s.wantClose = true;
        this.closeWhenIdle();
      }, AUTO_CLOSE_S * 1000);
    },

    closeWhenIdle() {
      const s = this.state;
      if (s.stay || !s.wantClose || s.syncing) return;
      home();
    },

    // --- dociąganie nowych zdjęć z telefonu ---

    dripSync() {
      const s = this.state;
      s.syncTimer = null;
      this.request({ method: "SYNC", params: { have: haveIds(loadPhotos()), max: DRIP_MAX } })
        .then((res) => {
          if (!res || !res.ok) return;
          s.pool = res.pool || [];
          if (!res.todo) {
            cleanupAfterSync(s.pool);
            return;
          }
          s.syncing = true;
          keepScreenOn();
          if (s.info && !s.stay) s.info.setProperty(hmUI.prop.TEXT, "Dociągam nowe zdjęcia...");
          // Bezpiecznik: nie czekamy w nieskończoność na Bluetooth
          setTimeout(() => this.syncFinished(), DRIP_TIMEOUT_S * 1000);
        })
        .catch(() => {});
    },

    syncFinished() {
      const s = this.state;
      if (!s.syncing) return;
      s.syncing = false;
      releaseScreen();
      try {
        cleanupAfterSync(s.pool);
      } catch (e) {}
      this.closeWhenIdle();
    },

    // Komunikaty z Side Service - tu liczy się tylko koniec przesyłania
    onCall(ev) {
      if (ev && ev.type === "DONE") this.syncFinished();
    },

    onReceivedFile(file) {
      receiveFile(file);
    },

    next() {
      const s = this.state;
      if (!s.current) return;
      // Pierwsze stuknięcie po samoczynnym otwarciu: zostajemy przy tym zdjęciu
      if (!s.stay) {
        s.stay = true;
        if (s.closeTimer) {
          clearTimeout(s.closeTimer);
          s.closeTimer = null;
        }
        try {
          setPageBrightTime({ brightTime: 60000 });
        } catch (e) {}
        s.info.setProperty(hmUI.prop.TEXT, label(s.current));
        return;
      }
      const photo = nextPhoto();
      if (!photo || photo.id === s.current.id) return;
      s.current = photo;
      s.img.setProperty(hmUI.prop.SRC, pickSrc(photo, loadVariant()));
      s.info.setProperty(hmUI.prop.TEXT, label(photo));
    },
  })
);
