// Ekran zdjęcia otwierany wprost przez budzik systemowy (sposób D). Najpierw tylko zapowiedź: wibracja i
// "Zobacz to" przy zwykłej jasności. Zdjęcie odsłania się dopiero po uniesieniu ręki albo stuknięciu (w ustawieniach
// można zostawić tylko stuknięcie) - wtedy ekran świeci mocniej. Opuszczenie ręki albo podwójne stuknięcie gasi
// zdjęcie i wraca do tarczy
// (pojedyncze stuknięcie = następne zdjęcie). Bez reakcji zapowiedź znika po TEASER_S, zdjęcie po PHOTO_MAX_S.
// Zdjęcie: najpierw świeżo dociągnięte (niespodzianka), potem worek bez powtórek. Wylosowane i wczytane od razu,
// pod zapowiedzią (odsłonięcie bez czekania), ale w worku zapisane dopiero przy odsłonięciu - nieobejrzane
// nie przepada. Od razu uzupełnia plan budzików.
// W tle dociąga z telefonu najwyżej DRIP_MAX nowych zdjęć i kasuje te, które wypadły z puli - po zgaszeniu
// zdjęcia ekran czeka na to (czarny) najwyżej DRIP_TIMEOUT_S, a nowe zdjęcie pokaże się przy kolejnym wyskoczeniu.
import * as hmUI from "@zos/ui";
import { home } from "@zos/router";
import { Vibrator, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { setPageBrightTime } from "@zos/display";
import { BasePage } from "@zeppos/zml/base-page";
import { loadPhotos, loadVariant, loadBag, saveBag, noteShown, loadSettings } from "../../../utils/store";
import { shownPhotos, readParams, haveIds, freshPick } from "../../../utils/photos";
import { pickSrc } from "../../../utils/paths";
import { takenText } from "../../../utils/format";
import { drawFromBag, wristReveals, TEASER_S, PHOTO_MAX_S } from "../../../utils/schedule";
import { refreshPlan } from "../../../utils/alarms";
import { receiveFile, cleanupAfterSync } from "../../../utils/syncflow";
import { keepScreenOn, releaseScreen, boostBrightness, restoreBrightness } from "../../../utils/screen";
import { tapState, tap, TAP_DOUBLE_MS } from "../../../utils/wrist";
import { watchWrist, stopWrist } from "../../../utils/motion";
import { getTop, setTop, returnTo } from "../../../utils/pages";
import {
  PHOTO_PROPS,
  INFO_BG_PROPS,
  INFO_STYLE,
  EMPTY_STYLE,
  TEASER_BG_PROPS,
  TEASER_RING_PROPS,
  TEASER_TITLE_STYLE,
  TEASER_HINT_STYLE,
} from "zosLoader:./index.page.[pf].layout.js";

// Plan uzupełniamy chwilę po otwarciu, żeby zapowiedź pojawiła się bez czekania na budziki
const PLAN_DELAY_MS = 300;
// Synchronizację zaczynamy, gdy zapowiedź już jest na ekranie
const SYNC_DELAY_MS = 800;
// Ile nowych zdjęć dociągnąć przy jednym wyskoczeniu i jak długo najwyżej na to czekać
const DRIP_MAX = 2;
const DRIP_TIMEOUT_S = 60;
// Stuknięcia tuż po odsłonięciu to jeszcze to samo stuknięcie / podwójne stuknięcie w zapowiedź
const TAP_GUARD_MS = 500;

function appLaunchParams() {
  try {
    return readParams(getApp()._options.globalData.launch);
  } catch (e) {
    return {};
  }
}

// Losowanie: wskazane, świeżo dociągnięte albo z worka; { photo, bag } bez zapisu worka, null = brak zdjęć
function choosePhoto(wanted) {
  const list = loadPhotos();
  const photos = shownPhotos(list);
  const bag = loadBag();
  const pick = drawFromBag(bag, photos.map((p) => p.id), Math.random, wanted || freshPick(list, bag.used, Date.now()));
  const photo = pick.id ? photos.filter((p) => p.id === pick.id)[0] : null;
  return photo ? { photo, bag: pick.bag } : null;
}

// Następne zdjęcie z od razu zapisanym workiem
function nextPhoto(wanted) {
  const pick = choosePhoto(wanted);
  if (!pick) return null;
  saveBag(pick.bag);
  return pick.photo;
}

function stillThere(photo) {
  return shownPhotos(loadPhotos()).some((p) => p.id === photo.id);
}

function label(photo) {
  return photo.caption || takenText(photo.taken) || " ";
}

function hide(w) {
  if (!w) return;
  try {
    w.setProperty(hmUI.prop.VISIBLE, false);
  } catch (e) {}
}

Page(
  BasePage({
    state: {
      launch: {},
      // "teaser" (zapowiedź) -> "photo" (odsłonięte) -> "off" (zgaszone, ewentualnie czeka na synchronizację)
      phase: "",
      // Zdjęcie przygotowane pod zapowiedzią: { photo, bag }
      prepared: null,
      teaser: [],
      img: null,
      infoBg: null,
      info: null,
      status: null,
      current: null,
      shownAt: 0,
      taps: null,
      tapTimer: null,
      closeTimer: null,
      planTimer: null,
      syncTimer: null,
      wrist: null,
      // Czy uniesienie ręki odsłania zdjęcie (ustawienie „Odsłanianie zdjęcia”)
      wristReveal: true,
      syncing: false,
      pool: [],
      // Strona, nad którą budzik otworzył zdjęcie (gdy aplikacja była otwarta)
      prevTop: "",
    },

    onInit(params) {
      this.state.launch = readParams(params);
    },

    build() {
      const s = this.state;
      // Parametr budzika przychodzi do strony albo do app.js (zależnie od tego, czy aplikacja już działała)
      const launch = s.launch.m ? s.launch : appLaunchParams();
      s.prevTop = getTop();
      setTop("photo");
      noteShown({ id: launch.id || "", m: launch.m || "?" });
      // Gdyby poprzednie zdjęcie nie przywróciło jasności - przywrócić; zapowiedź świeci zwyczajnie
      restoreBrightness();
      keepScreenOn();
      s.planTimer = setTimeout(() => this.updatePlan(), PLAN_DELAY_MS);
      s.syncTimer = setTimeout(() => this.dripSync(), SYNC_DELAY_MS);
      s.taps = tapState();
      s.wristReveal = wristReveals(loadSettings());

      s.prepared = choosePhoto(launch.id);
      if (!s.prepared) {
        s.phase = "off";
        s.status = hmUI.createWidget(hmUI.widget.TEXT, {
          ...EMPTY_STYLE,
          text: "Na zegarku nie ma jeszcze zdjęć - pobieram z telefonu...",
        });
        this.closeAfter(TEASER_S);
        return;
      }

      // Zdjęcie od razu na ekranie, przykryte zapowiedzią (widżety tworzone później są na wierzchu)
      this.createPhoto(s.prepared.photo);
      this.showTeaser();
    },

    onDestroy() {
      const s = this.state;
      this.clearTimers();
      if (s.syncTimer) clearTimeout(s.syncTimer);
      stopWrist(s.wrist);
      s.wrist = null;
      releaseScreen();
      restoreBrightness();
      returnTo(s.prevTop);
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

    clearTimers() {
      const s = this.state;
      if (s.closeTimer) clearTimeout(s.closeTimer);
      if (s.tapTimer) clearTimeout(s.tapTimer);
      s.closeTimer = null;
      s.tapTimer = null;
    },

    closeAfter(seconds) {
      const s = this.state;
      if (s.closeTimer) clearTimeout(s.closeTimer);
      s.closeTimer = setTimeout(() => {
        s.closeTimer = null;
        this.goOff();
      }, seconds * 1000);
    },

    // --- zapowiedź ---

    showTeaser() {
      const s = this.state;
      s.phase = "teaser";
      const onTap = () => this.reveal();
      s.teaser = [
        hmUI.createWidget(hmUI.widget.FILL_RECT, TEASER_BG_PROPS),
        hmUI.createWidget(hmUI.widget.ARC, TEASER_RING_PROPS),
        hmUI.createWidget(hmUI.widget.TEXT, TEASER_TITLE_STYLE),
        hmUI.createWidget(hmUI.widget.TEXT, {
          ...TEASER_HINT_STYLE,
          text: s.wristReveal ? TEASER_HINT_STYLE.text : "stuknij, aby zobaczyć",
        }),
      ];
      s.teaser.forEach((w) => {
        try {
          w.addEventListener(hmUI.event.CLICK_UP, onTap);
        } catch (e) {}
      });
      // Ręka obserwowana zawsze: nawet przy „tylko stuknięcie” jej opuszczenie gasi odsłonięte zdjęcie
      s.wrist = watchWrist((ev) => this.onWrist(ev));
      this.vibrate();
      this.closeAfter(TEASER_S);
    },

    onWrist(ev) {
      const s = this.state;
      if (ev === "up" && s.phase === "teaser" && s.wristReveal) this.reveal();
      else if (ev === "down" && s.phase === "photo") this.goOff();
    },

    createPhoto(photo) {
      const s = this.state;
      s.current = photo;
      s.img = hmUI.createWidget(hmUI.widget.IMG, { ...PHOTO_PROPS, src: pickSrc(photo, loadVariant()) });
      s.img.addEventListener(hmUI.event.CLICK_UP, () => this.onPhotoTap());
      s.infoBg = hmUI.createWidget(hmUI.widget.FILL_RECT, INFO_BG_PROPS);
      s.info = hmUI.createWidget(hmUI.widget.TEXT, { ...INFO_STYLE, text: label(photo) });
    },

    showPhoto(photo) {
      const s = this.state;
      s.current = photo;
      s.img.setProperty(hmUI.prop.SRC, pickSrc(photo, loadVariant()));
      s.info.setProperty(hmUI.prop.TEXT, label(photo));
    },

    // Uniesienie ręki (jeśli włączone) albo stuknięcie: mocniejsze podświetlenie, zapowiedź znika, pod nią jest już zdjęcie
    reveal() {
      const s = this.state;
      if (s.phase !== "teaser") return;
      // Dociąganie w tle mogło w międzyczasie skasować przygotowane zdjęcie - wtedy losujemy jeszcze raz
      if (!stillThere(s.prepared.photo)) {
        const again = choosePhoto();
        if (!again) {
          this.goOff();
          return;
        }
        s.prepared = again;
        this.showPhoto(again.photo);
      }
      // Dopiero teraz zdjęcie liczy się jako pokazane
      saveBag(s.prepared.bag);
      s.phase = "photo";
      s.shownAt = Date.now();
      boostBrightness(loadSettings().bright);
      s.teaser.forEach(hide);
      try {
        setPageBrightTime({ brightTime: (PHOTO_MAX_S + 2) * 1000 });
      } catch (e) {}
      this.closeAfter(PHOTO_MAX_S);
    },

    // Pojedyncze stuknięcie = następne zdjęcie (po odczekaniu, czy nie będzie drugiego), podwójne = zgaś
    onPhotoTap() {
      const s = this.state;
      if (s.phase !== "photo") return;
      const now = Date.now();
      if (now - s.shownAt < TAP_GUARD_MS) return;
      if (tap(s.taps, now) === "double") {
        if (s.tapTimer) clearTimeout(s.tapTimer);
        s.tapTimer = null;
        this.goOff();
        return;
      }
      if (s.tapTimer) clearTimeout(s.tapTimer);
      s.tapTimer = setTimeout(() => {
        s.tapTimer = null;
        this.next();
      }, TAP_DOUBLE_MS + 50);
    },

    next() {
      const s = this.state;
      if (s.phase !== "photo" || !s.current) return;
      const photo = nextPhoto();
      if (!photo || photo.id === s.current.id) return;
      this.showPhoto(photo);
      // Oglądamy dalej - liczenie do samoczynnego zgaszenia od nowa
      this.closeAfter(PHOTO_MAX_S);
    },

    // Zdjęcie gaśnie: jasność wraca, powrót do tarczy (albo czarny ekran do końca dociągania zdjęć)
    goOff() {
      const s = this.state;
      if (s.phase === "off" && s.status) {
        if (!s.syncing) home();
        return;
      }
      s.phase = "off";
      this.clearTimers();
      stopWrist(s.wrist);
      s.wrist = null;
      [s.img, s.infoBg, s.info].concat(s.teaser).forEach(hide);
      restoreBrightness();
      if (!s.syncing) {
        home();
        return;
      }
      s.status = hmUI.createWidget(hmUI.widget.TEXT, { ...EMPTY_STYLE, text: "Dociągam nowe zdjęcia..." });
    },

    // Zdjęcie samo wyskoczyło: delikatna wibracja
    vibrate() {
      try {
        const v = new Vibrator();
        v.setMode(VIBRATOR_SCENE_NOTIFICATION);
        v.start();
      } catch (e) {}
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
          // Bezpiecznik: nie czekamy w nieskończoność na Bluetooth
          setTimeout(() => this.syncFinished(), DRIP_TIMEOUT_S * 1000);
        })
        .catch(() => {});
    },

    syncFinished() {
      const s = this.state;
      if (!s.syncing) return;
      s.syncing = false;
      try {
        cleanupAfterSync(s.pool);
      } catch (e) {}
      if (s.phase === "off") home();
    },

    // Komunikaty z Side Service - tu liczy się tylko koniec przesyłania
    onCall(ev) {
      if (ev && ev.type === "DONE") this.syncFinished();
    },

    onReceivedFile(file) {
      receiveFile(file);
    },
  })
);
