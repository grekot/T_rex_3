// Próba 0b: budzik za 30 s → usługa → powiadomienie „Zobacz to” → przycisk „Pokaż” otwiera ekran zdjęcia
// jednym z trzech sposobów (A/B/C). Wyniki (który sposób otworzył ekran) zapisuje ekran zdjęcia.
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { set } from "@zos/alarm";
import { notify } from "@zos/notification";
import { getPackageInfo } from "@zos/app";
import { buttonProps } from "../../../utils/ui";
import { loadPhotos, loadOpenLog } from "../../../utils/store";
import { haveIds } from "../../../utils/photos";
import {
  METHODS,
  DIRECT,
  TEST_DELAY_S,
  NOTIFY_SERVICE,
  PHOTO_PAGE,
  testAlarmParam,
  directAlarmParam,
  notificationFor,
  openLogLines,
  clock,
} from "../../../utils/notify";
import {
  TITLE_STYLE,
  STATUS_STYLE,
  NOW_RECT,
  BOTTOM_SPACER,
  methodRect,
} from "zosLoader:./index.page.[pf].layout.js";

Page({
  state: {
    status: null,
    note: "",
  },

  build() {
    hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);
    this.state.status = hmUI.createWidget(hmUI.widget.TEXT, STATUS_STYLE);
    hmUI.createWidget(
      hmUI.widget.BUTTON,
      buttonProps(methodRect(0), "D: samo zdjęcie (za " + TEST_DELAY_S + " s)", "primary", () => this.schedule(DIRECT), px(22))
    );
    METHODS.forEach((m, i) => {
      hmUI.createWidget(
        hmUI.widget.BUTTON,
        buttonProps(methodRect(i + 1), "Sposób " + m + " (za " + TEST_DELAY_S + " s)", "secondary", () => this.schedule(m), px(22))
      );
    });
    hmUI.createWidget(hmUI.widget.BUTTON, buttonProps(NOW_RECT, "Od razu (C)", "secondary", () => this.now(), px(20)));
    hmUI.createWidget(hmUI.widget.FILL_RECT, BOTTOM_SPACER);
    this.render();
  },

  onResume() {
    this.render();
  },

  render() {
    const s = this.state;
    if (!s.status) return;
    const ids = haveIds(loadPhotos());
    const lines = [s.note || "Zdjęć na zegarku: " + ids.length + ". Wybierz sposób, wyjdź z aplikacji i czekaj."]
      .concat(openLogLines(loadOpenLog()));
    s.status.setProperty(hmUI.prop.TEXT, lines.join("\n"));
  },

  // Prawdziwa droga: budzik systemowy uruchamia usługę (A/B/C) albo wprost ekran zdjęcia (D)
  // także przy zamkniętej aplikacji
  schedule(method) {
    const s = this.state;
    const ids = haveIds(loadPhotos());
    const direct = method === DIRECT;
    try {
      const id = set({
        appid: getPackageInfo().appId,
        url: direct ? PHOTO_PAGE : NOTIFY_SERVICE,
        delay: TEST_DELAY_S,
        param: direct ? directAlarmParam(ids, Math.random) : testAlarmParam(method, ids, Math.random),
      });
      const hint = direct ? " Wyjdź i opuść rękę (ekran zgaśnie)." : " Wyjdź z aplikacji.";
      s.note = id
        ? "Sposób " + method + ": budzik " + id + " na " + clock(Date.now() + TEST_DELAY_S * 1000) + "." + hint
        : "Sposób " + method + ": system nie ustawił budzika (0).";
    } catch (e) {
      s.note = "Sposób " + method + ": błąd budzika: " + String((e && e.message) || e);
    }
    this.render();
  },

  // Bez budzika: samo powiadomienie (gdy budzik nie zadziała, to oddziela oba problemy)
  now() {
    const s = this.state;
    try {
      const id = notify(notificationFor(testAlarmParam("C", haveIds(loadPhotos()), Math.random), Math.random));
      s.note = id ? "Powiadomienie wysłane (" + id + ")." : "System odrzucił powiadomienie (0).";
    } catch (e) {
      s.note = "Błąd powiadomienia: " + String((e && e.message) || e);
    }
    this.render();
  },
});
