// Ekran zdjęcia otwierany wprost przez budzik systemowy (sposób D). Zdjęcie bierze z worka (bez powtórek,
// dopóki nie pokażą się wszystkie), krótko wibruje i po AUTO_CLOSE_S wraca do tarczy, chyba że ktoś stuknie
// (pierwsze stuknięcie = zostań, kolejne = następne zdjęcie z worka). Od razu uzupełnia plan budzików.
import * as hmUI from "@zos/ui";
import { home } from "@zos/router";
import { Vibrator, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { setPageBrightTime } from "@zos/display";
import { loadPhotos, loadVariant, loadBag, saveBag, noteShown } from "../../../utils/store";
import { shownPhotos, readParams } from "../../../utils/photos";
import { pickSrc } from "../../../utils/paths";
import { takenText } from "../../../utils/format";
import { drawFromBag, AUTO_CLOSE_S } from "../../../utils/schedule";
import { refreshPlan } from "../../../utils/alarms";
import { PHOTO_PROPS, INFO_BG_PROPS, INFO_STYLE, EMPTY_STYLE } from "zosLoader:./index.page.[pf].layout.js";

// Plan uzupełniamy chwilę po otwarciu, żeby zdjęcie pojawiło się bez czekania na budziki
const PLAN_DELAY_MS = 300;

function appLaunchParams() {
  try {
    return readParams(getApp()._options.globalData.launch);
  } catch (e) {
    return {};
  }
}

// Następne zdjęcie z worka (worek od razu zapisany); null, gdy na zegarku nie ma zdjęć
function nextPhoto(wanted) {
  const photos = shownPhotos(loadPhotos());
  const pick = drawFromBag(loadBag(), photos.map((p) => p.id), Math.random, wanted);
  if (!pick.id) return null;
  saveBag(pick.bag);
  return photos.filter((p) => p.id === pick.id)[0] || null;
}

Page({
  state: {
    launch: {},
    img: null,
    info: null,
    current: null,
    closeTimer: null,
    planTimer: null,
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

    if (!photo) {
      hmUI.createWidget(hmUI.widget.TEXT, {
        ...EMPTY_STYLE,
        text: "Na zegarku nie ma jeszcze zdjęć - pobierz je z telefonu.",
      });
      this.autoClose();
      return;
    }
    s.current = photo;
    s.img = hmUI.createWidget(hmUI.widget.IMG, { ...PHOTO_PROPS, src: pickSrc(photo, loadVariant()) });
    s.img.addEventListener(hmUI.event.CLICK_UP, () => this.next());
    hmUI.createWidget(hmUI.widget.FILL_RECT, INFO_BG_PROPS);
    s.info = hmUI.createWidget(hmUI.widget.TEXT, { ...INFO_STYLE, text: "Stuknij, by zostać" });
    this.vibrate();
    this.autoClose();
  },

  onDestroy() {
    const s = this.state;
    if (s.closeTimer) clearTimeout(s.closeTimer);
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

  // Ekran świeci do zamknięcia, potem tarcza
  autoClose() {
    const s = this.state;
    try {
      setPageBrightTime({ brightTime: (AUTO_CLOSE_S + 2) * 1000 });
    } catch (e) {}
    s.closeTimer = setTimeout(() => {
      s.closeTimer = null;
      home();
    }, AUTO_CLOSE_S * 1000);
  },

  next() {
    const s = this.state;
    // Pierwsze stuknięcie po samoczynnym otwarciu: zostajemy przy tym zdjęciu
    if (s.closeTimer) {
      clearTimeout(s.closeTimer);
      s.closeTimer = null;
      try {
        setPageBrightTime({ brightTime: 60000 });
      } catch (e) {}
      s.info.setProperty(hmUI.prop.TEXT, takenText(s.current.taken) || " ");
      return;
    }
    const photo = nextPhoto();
    if (!photo || photo.id === s.current.id) return;
    s.current = photo;
    s.img.setProperty(hmUI.prop.SRC, pickSrc(photo, loadVariant()));
    s.info.setProperty(hmUI.prop.TEXT, takenText(photo.taken) || " ");
  },
});
