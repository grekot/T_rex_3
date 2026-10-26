// Panel: pobranie zdjęć z telefonu (most 127.0.0.1) z pomiarem rozmiaru i czasu, podgląd zdjęć
// i ustawienia losowego pokazywania. Każdy start aplikacji uzupełnia plan budzików i sam pobiera
// wszystkie nowe zdjęcia z puli telefonu (stare, które z niej wypadły, kasuje).
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { push } from "@zos/router";
import { BasePage } from "@zeppos/zml/base-page";
import { stayInApp, keepScreenOn, releaseScreen, boostBrightness, restoreBrightness } from "../../../utils/screen";
import { buttonProps } from "../../../utils/ui";
import { loadPhotos, savePhoto, loadVariant, saveVariant, downloadedFiles, clearPhotos, loadPlan, loadSettings } from "../../../utils/store";
import { shownPhotos, haveIds } from "../../../utils/photos";
import { srcVariants, pickSrc } from "../../../utils/paths";
import { summaryLines, photoInfoLines } from "../../../utils/format";
import { describeEvent, describeStart, errText } from "../../../utils/events";
import { nextLine } from "../../../utils/schedule";
import { refreshPlan, localOffsetMin } from "../../../utils/alarms";
import { receiveFile, cleanupAfterSync } from "../../../utils/syncflow";
import { setTop, isTop, onReturn } from "../../../utils/pages";
import {
  TITLE_STYLE,
  STATUS_STYLE,
  SYNC_RECT,
  SHOW_RECT,
  TEST_RECT,
  CLEAR_RECT,
  SETTINGS_RECT,
  PHOTO_PROPS,
  BACK_RECT,
  VARIANT_RECT,
  INFO_BG_PROPS,
  INFO_STYLE,
} from "zosLoader:./index.page.[pf].layout.js";

// Ile linii statusu mieści się nad przyciskami
const MAX_LOG = 4;
// Pobieranie zaczyna się samo chwilę po otwarciu (panel już widać)
const AUTO_SYNC_MS = 800;
// Po powrocie z ustawień przebudowa panelu dopiero, gdy ustawienia znikną z ekranu
const RETURN_DELAY_MS = 300;

// Przebudowa ekranu poza obsługą kliknięcia (usuwanie widżetu w jego własnym zdarzeniu bywa ryzykowne)
function later(fn) {
  setTimeout(fn, 10);
}

Page(
  BasePage({
    state: {
      widgets: [],
      status: null,
      mode: "panel",
      index: 0,
      log: [],
      current: "",
      busy: false,
      planLine: "",
      pool: [],
      // Coś przyszło, kiedy panel był pod inną stroną - przebudować po powrocie
      stale: false,
    },

    build() {
      setTop("home");
      onReturn("home", () => this.backHere());
      stayInApp();
      restoreBrightness();
      try {
        refreshPlan();
      } catch (e) {}
      this.state.planLine = this.planLine();
      this.state.log = this.storedLines();
      this.showPanel();
      setTimeout(() => this.startSync(), AUTO_SYNC_MS);
    },

    // Powrót z ustawień: świeża linia planu
    onResume() {
      this.state.planLine = this.planLine();
      this.renderStatus();
    },

    onDestroy() {
      releaseScreen();
      restoreBrightness();
    },

    // Powrót z ustawień (woła je przy zamknięciu): świeża linia planu i zaległa przebudowa panelu
    backHere() {
      const s = this.state;
      s.planLine = this.planLine();
      this.renderStatus();
      if (s.stale) setTimeout(() => this.panelChanged(), RETURN_DELAY_MS);
    },

    // Panel zmienił się w tle (odebrane zdjęcie, koniec pobierania). Przebudowa tworzy widżety, więc tylko
    // wtedy, gdy panel jest na wierzchu - inaczej przyciski panelu narysowałyby się na ustawieniach.
    panelChanged() {
      const s = this.state;
      if (s.mode !== "panel") return;
      if (!isTop("home")) {
        s.stale = true;
        return;
      }
      s.stale = false;
      later(() => {
        if (s.mode !== "panel") return;
        if (isTop("home")) this.showPanel();
        else s.stale = true;
      });
    },

    planLine() {
      return nextLine(loadPlan(), Date.now(), localOffsetMin());
    },

    storedLines() {
      const photos = loadPhotos();
      const files = downloadedFiles();
      return [
        "Na zegarku: " + shownPhotos(photos).length + " zdj. (pliki: " + (files ? files.length : "?") + ")",
      ].concat(summaryLines(photos));
    },

    // --- widżety ---

    add(type, props) {
      const w = hmUI.createWidget(type, props);
      this.state.widgets.push(w);
      return w;
    },

    clearScreen() {
      const s = this.state;
      s.widgets.forEach((w) => {
        try {
          hmUI.deleteWidget(w);
        } catch (e) {}
      });
      s.widgets = [];
      s.status = null;
    },

    showPanel() {
      const s = this.state;
      restoreBrightness();
      this.clearScreen();
      s.mode = "panel";
      const count = shownPhotos(loadPhotos()).length;
      this.add(hmUI.widget.TEXT, TITLE_STYLE);
      s.status = this.add(hmUI.widget.TEXT, STATUS_STYLE);
      this.add(hmUI.widget.BUTTON, buttonProps(SYNC_RECT, "Pobierz z telefonu", "primary", () => this.startSync()));
      this.add(
        hmUI.widget.BUTTON,
        buttonProps(SHOW_RECT, "Pokaż zdjęcia (" + count + ")", "secondary", () => later(() => this.showPhoto(0)))
      );
      this.add(hmUI.widget.BUTTON, buttonProps(TEST_RECT, "Test sieci", "secondary", () => this.startTestNet(), px(20)));
      this.add(hmUI.widget.BUTTON, buttonProps(CLEAR_RECT, "Wyczyść", "danger", () => later(() => this.clearAll()), px(20)));
      this.add(
        hmUI.widget.BUTTON,
        buttonProps(SETTINGS_RECT, "Ustawienia", "secondary", () => this.openSettings(), px(20))
      );
      this.renderStatus();
    },

    openSettings() {
      // Od tej chwili panel jest pod spodem (zanim ustawienia same to zapiszą)
      setTop("settings");
      push({ url: "page/gt/settings/index.page" });
    },

    showPhoto(index) {
      const s = this.state;
      const photos = shownPhotos(loadPhotos());
      if (!photos.length) {
        this.log("Brak zdjęć na zegarku");
        return;
      }
      if (index >= photos.length) {
        this.showPanel();
        return;
      }
      s.index = index;
      const p = photos[index];
      const variant = loadVariant();
      const variants = srcVariants(p);
      const src = pickSrc(p, variant);
      this.clearScreen();
      s.mode = "photo";
      boostBrightness(loadSettings().bright);
      const img = this.add(hmUI.widget.IMG, { ...PHOTO_PROPS, src });
      img.addEventListener(hmUI.event.CLICK_UP, () => later(() => this.showPhoto(s.index + 1)));
      this.add(hmUI.widget.FILL_RECT, INFO_BG_PROPS);
      this.add(hmUI.widget.TEXT, {
        ...INFO_STYLE,
        text: photoInfoLines(p, index, photos.length).concat(["src: " + src]).join("\n"),
      });
      this.add(hmUI.widget.BUTTON, buttonProps(BACK_RECT, "Panel", "secondary", () => later(() => this.showPanel()), px(20)));
      this.add(
        hmUI.widget.BUTTON,
        buttonProps(
          VARIANT_RECT,
          "ścieżka " + ((variant % variants.length) + 1) + "/" + variants.length,
          "secondary",
          () =>
            later(() => {
              saveVariant(loadVariant() + 1);
              this.showPhoto(s.index);
            }),
          px(20)
        )
      );
    },

    // --- status ---

    renderStatus() {
      const s = this.state;
      if (!s.status) return;
      // Podczas przesyłania linia planu ustępuje miejsca postępowi
      const lines = (s.planLine && !s.busy ? [s.planLine] : []).concat(s.log.slice(-MAX_LOG));
      if (s.current) lines.push(s.current);
      s.status.setProperty(hmUI.prop.TEXT, lines.join("\n"));
    },

    log(line) {
      const s = this.state;
      s.log.push(line);
      if (s.log.length > 20) s.log.shift();
      this.renderStatus();
    },

    // --- przesyłanie ---

    startSync() {
      this.begin("Łączę z telefonem...", { method: "SYNC", params: { have: haveIds(loadPhotos()), max: 0 } });
    },

    startTestNet() {
      this.begin("Test: obrazek z internetu...", { method: "TEST_NET", params: {} });
    },

    begin(text, request) {
      const s = this.state;
      if (s.busy) return;
      s.busy = true;
      keepScreenOn();
      s.log = [];
      s.current = text;
      this.renderStatus();
      this.request(request)
        .then((res) => {
          s.current = "";
          this.log(describeStart(res));
          if (res && res.ok) s.pool = res.pool || [];
          if (res && res.ok && !res.todo) this.cleanup();
          if (!res || !res.ok || !res.todo) this.finish();
        })
        .catch((e) => {
          s.current = "";
          this.log("Brak odpowiedzi z telefonu: " + errText(e));
          this.finish();
        });
    },

    finish() {
      this.state.busy = false;
      releaseScreen();
    },

    // Komunikaty z Side Service: kolejne kroki, postęp, wyniki pomiarów
    onCall(ev) {
      if (!ev || !ev.type) return;
      const s = this.state;
      const d = describeEvent(ev);
      if (d.photo) savePhoto(d.photo);
      if (d.current !== undefined) s.current = d.current;
      if (d.log) this.log(d.log);
      else this.renderStatus();
      if (d.done) {
        this.cleanup();
        this.finish();
        summaryLines(loadPhotos()).forEach((line) => this.log(line));
        this.panelChanged();
      }
    },

    // Zdjęcia, które wypadły z puli telefonu (tylko nadmiar ponad jej wielkość)
    cleanup() {
      const removed = cleanupAfterSync(this.state.pool);
      if (removed) this.log("Usunięto starych zdjęć: " + removed);
    },

    // Plik przysłany przez Side Service (TransferFile)
    onReceivedFile(file) {
      receiveFile(
        file,
        () => this.panelChanged(),
        (id, state) => this.log("Błąd odbioru " + id + ": " + state)
      );
    },

    clearAll() {
      clearPhotos();
      this.state.log = ["Wyczyszczono."].concat(this.storedLines());
      this.showPanel();
    },
  })
);
