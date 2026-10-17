// Ustawienia na zegarku: wygaszanie po opuszczeniu ręki, ręczna synchronizacja, konto.
import * as hmUI from "@zos/ui";
import { showToast } from "@zos/interaction";
import { px } from "@zos/utils";
import { BasePage } from "@zeppos/zml/base-page";
import { loadData, loadPending, loadSettings, saveSettings, sync } from "../../../utils/store";
import { syncStatus } from "../../../utils/format";
import { button, wideRect } from "../../../utils/ui";
import {
  DEVICE_WIDTH,
  TITLE_STYLE,
  TOGGLE_BG,
  TOGGLE_LABEL,
  pillProps,
  knobProps,
  infoStyle,
  INFO_Y,
  SYNC_Y,
  ACCOUNT_Y,
} from "zosLoader:./index.page.[pf].layout.js";

Page(
  BasePage({
    state: {
      pill: null,
      knob: null,
      account: null,
    },

    build() {
      const s = this.state;
      const on = loadSettings().keepOnWristDrop;
      hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);

      const bg = hmUI.createWidget(hmUI.widget.FILL_RECT, TOGGLE_BG);
      const label = hmUI.createWidget(hmUI.widget.TEXT, TOGGLE_LABEL);
      s.pill = hmUI.createWidget(hmUI.widget.FILL_RECT, pillProps(on));
      s.knob = hmUI.createWidget(hmUI.widget.CIRCLE, knobProps(on));
      [bg, label, s.pill, s.knob].forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, () => this.toggleWrist()));

      hmUI.createWidget(
        hmUI.widget.TEXT,
        infoStyle(
          INFO_Y,
          px(88),
          "Działa na ekranie listy. Ekran i tak zgaśnie po minucie bez dotyku. Zużywa więcej baterii."
        )
      );

      button(wideRect(SYNC_Y, DEVICE_WIDTH), "Synchronizuj teraz", "secondary", () => this.syncNow());
      s.account = hmUI.createWidget(hmUI.widget.TEXT, infoStyle(ACCOUNT_Y, px(80), ""));
      this.renderAccount();
    },

    toggleWrist() {
      const s = this.state;
      const settings = loadSettings();
      settings.keepOnWristDrop = !settings.keepOnWristDrop;
      saveSettings(settings);
      s.pill.setProperty(hmUI.prop.MORE, pillProps(settings.keepOnWristDrop));
      s.knob.setProperty(hmUI.prop.MORE, knobProps(settings.keepOnWristDrop));
    },

    syncNow() {
      showToast({ content: "Synchronizacja..." });
      sync(this, (r) => {
        if (r.ok) showToast({ content: "Zsynchronizowano" });
        else if (r.offline) showToast({ content: "Brak połączenia z telefonem" });
        else showToast({ content: r.error || "Błąd synchronizacji" });
        this.renderAccount();
      });
    },

    renderAccount() {
      const data = loadData();
      const lines = [];
      lines.push(data.email ? "Konto: " + data.email : "Konto: zaloguj się w aplikacji Zepp");
      const status = syncStatus(data.fetchedAt, loadPending().length, false);
      if (status) lines.push(status);
      this.state.account.setProperty(hmUI.prop.MORE, { ...infoStyle(ACCOUNT_Y, px(80), lines.join("\n")) });
    },
  })
);
