// Ekran zdjęcia otwierany z powiadomienia „Zobacz to” (A/B/C) albo wprost przez budzik (D).
// Zapisuje, którym sposobem go otwarto. Przy D: krótka wibracja i powrót do tarczy po AUTO_CLOSE_S,
// chyba że ktoś stuknie (pierwsze stuknięcie = zostań, kolejne = następne losowe zdjęcie).
import * as hmUI from "@zos/ui";
import { home } from "@zos/router";
import { Vibrator, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { setPageBrightTime } from "@zos/display";
import { loadPhotos, loadVariant, logOpen } from "../../../utils/store";
import { shownPhotos, readParams } from "../../../utils/photos";
import { pickSrc } from "../../../utils/paths";
import { pickPhoto, takenText, DIRECT, AUTO_CLOSE_S } from "../../../utils/notify";
import { PHOTO_PROPS, INFO_BG_PROPS, INFO_STYLE, EMPTY_STYLE } from "zosLoader:./index.page.[pf].layout.js";

function appLaunchParams() {
  try {
    return readParams(getApp()._options.globalData.launch);
  } catch (e) {
    return {};
  }
}

Page({
  state: {
    launch: {},
    img: null,
    info: null,
    current: null,
    closeTimer: null,
  },

  onInit(params) {
    this.state.launch = readParams(params);
  },

  build() {
    const s = this.state;
    // Parametr przychodzi do strony albo do app.js (zależnie od sposobu otwarcia)
    const fromApp = appLaunchParams();
    const launch = s.launch.m ? s.launch : fromApp;
    const method = launch.m || "?";
    logOpen(method);

    const photos = shownPhotos(loadPhotos());
    const photo = pickPhoto(photos, launch.id, Math.random);
    if (!photo) {
      hmUI.createWidget(hmUI.widget.TEXT, {
        ...EMPTY_STYLE,
        text: "Otwarto sposobem " + method + ".\nNa zegarku nie ma jeszcze zdjęć - pobierz je z telefonu.",
      });
      return;
    }
    s.img = hmUI.createWidget(hmUI.widget.IMG, { ...PHOTO_PROPS, src: pickSrc(photo, loadVariant()) });
    s.img.addEventListener(hmUI.event.CLICK_UP, () => this.next());
    hmUI.createWidget(hmUI.widget.FILL_RECT, INFO_BG_PROPS);
    s.info = hmUI.createWidget(hmUI.widget.TEXT, INFO_STYLE);
    s.current = photo;
    const when = takenText(photo.taken);
    if (method === DIRECT) {
      this.popUp();
      s.info.setProperty(hmUI.prop.TEXT, "Stuknij, by zostać");
    } else {
      s.info.setProperty(hmUI.prop.TEXT, "Sposób " + method + (when ? " · " + when : ""));
    }
  },

  // Zdjęcie samo wyskoczyło: delikatna wibracja, ekran świeci do zamknięcia, potem tarcza
  popUp() {
    const s = this.state;
    try {
      setPageBrightTime({ brightTime: (AUTO_CLOSE_S + 2) * 1000 });
    } catch (e) {}
    try {
      const v = new Vibrator();
      v.setMode(VIBRATOR_SCENE_NOTIFICATION);
      v.start();
    } catch (e) {}
    s.closeTimer = setTimeout(() => {
      s.closeTimer = null;
      home();
    }, AUTO_CLOSE_S * 1000);
  },

  onDestroy() {
    const s = this.state;
    if (s.closeTimer) clearTimeout(s.closeTimer);
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
      const when = takenText(s.current.taken);
      s.info.setProperty(hmUI.prop.TEXT, "Sposób D" + (when ? " · " + when : ""));
      return;
    }
    const photos = shownPhotos(loadPhotos());
    if (photos.length < 2) return;
    let photo = s.current;
    while (photo.id === s.current.id) photo = pickPhoto(photos, "", Math.random);
    s.current = photo;
    s.img.setProperty(hmUI.prop.SRC, pickSrc(photo, loadVariant()));
    const when = takenText(photo.taken);
    s.info.setProperty(hmUI.prop.TEXT, when || " ");
  },
});
