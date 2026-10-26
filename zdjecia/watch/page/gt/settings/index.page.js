// Ustawienia losowego pokazywania zdjęć: włącz/wyłącz, ile razy dziennie, w jakich godzinach, jasność
// i czym odsłania się zdjęcie (uniesienie ręki lub stuknięcie albo tylko stuknięcie).
// Po zmianie plan budzików liczony jest od nowa (stare anulowane, nowe ustawione); na dole najbliższe
// pokazy i próba „za 1 min”, żeby nie czekać godzinami.
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { buttonProps } from "../../../utils/ui";
import { loadSettings, saveSettings, loadPlan, loadShown } from "../../../utils/store";
import { adjust, hourText, brightText, revealText, planLines, whenText, clockText, TEST_DELAY_S } from "../../../utils/schedule";
import { refreshPlan, scheduleTest, localOffsetMin } from "../../../utils/alarms";
import { setTop, returnTo } from "../../../utils/pages";
import {
  TITLE_STYLE,
  toggleBg,
  toggleText,
  rowLabel,
  minusRect,
  plusRect,
  rowValue,
  REVEAL_LABEL_STYLE,
  revealBg,
  revealValue,
  STATUS_STYLE,
  TEST_RECT,
  BOTTOM_SPACER,
} from "zosLoader:./index.page.[pf].layout.js";

// Plan przeliczamy chwilę po ostatniej zmianie (kilka stuknięć w „+” = jedno przeliczenie)
const APPLY_DELAY_MS = 1200;

const ROWS = [
  { field: "perDay", label: "Ile razy dziennie", text: (s) => String(s.perDay) },
  { field: "from", label: "Od godziny", text: (s) => hourText(s.from) },
  { field: "to", label: "Do godziny", text: (s) => hourText(s.to) },
  { field: "bright", label: "Jasność przy zdjęciu", text: (s) => brightText(s.bright), always: true },
];

function errText(e) {
  return String((e && e.message) || e);
}

Page({
  state: {},

  onInit() {
    Object.assign(this.state, {
      settings: loadSettings(),
      toggle: null,
      values: [],
      reveal: null,
      status: null,
      timer: null,
      note: "",
    });
  },

  build() {
    const s = this.state;
    setTop("settings");
    hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);

    const bg = hmUI.createWidget(hmUI.widget.FILL_RECT, toggleBg(s.settings.on));
    const text = hmUI.createWidget(hmUI.widget.TEXT, toggleText(s.settings.on));
    [bg, text].forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, () => this.change("on", 0)));
    s.toggle = { bg, text };

    ROWS.forEach((row, i) => {
      hmUI.createWidget(hmUI.widget.TEXT, rowLabel(i, row.label));
      hmUI.createWidget(hmUI.widget.BUTTON, buttonProps(minusRect(i), "-", "secondary", () => this.change(row.field, -1), px(40)));
      s.values.push(hmUI.createWidget(hmUI.widget.TEXT, rowValue(i, row.text(s.settings), row.always || s.settings.on)));
      hmUI.createWidget(hmUI.widget.BUTTON, buttonProps(plusRect(i), "+", "secondary", () => this.change(row.field, 1), px(40)));
    });

    hmUI.createWidget(hmUI.widget.TEXT, REVEAL_LABEL_STYLE);
    const revealBack = hmUI.createWidget(hmUI.widget.FILL_RECT, revealBg());
    s.reveal = hmUI.createWidget(hmUI.widget.TEXT, revealValue(revealText(s.settings.reveal)));
    [revealBack, s.reveal].forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, () => this.change("reveal", 1)));

    s.status = hmUI.createWidget(hmUI.widget.TEXT, STATUS_STYLE);
    hmUI.createWidget(
      hmUI.widget.BUTTON,
      buttonProps(TEST_RECT, "Próba za " + Math.round(TEST_DELAY_S / 60) + " min", "secondary", () => this.test(), px(22))
    );
    hmUI.createWidget(hmUI.widget.FILL_RECT, BOTTOM_SPACER);
    this.renderStatus();
  },

  onResume() {
    this.renderStatus();
  },

  // Wyjście przed przeliczeniem - przeliczamy od razu
  onDestroy() {
    if (this.state.timer) this.apply(false);
    // Ustawienia otwiera tylko panel - wracamy do niego (panel dokończy zaległą przebudowę)
    returnTo("home");
  },

  change(field, delta) {
    const s = this.state;
    s.settings = adjust(s.settings, field, delta);
    saveSettings(s.settings);
    this.renderSettings();
    // Jasność i odsłanianie nie zmieniają planu pokazów
    if (field === "bright" || field === "reveal") return;
    s.note = "";
    if (s.timer) clearTimeout(s.timer);
    s.timer = setTimeout(() => this.apply(true), APPLY_DELAY_MS);
    this.renderStatus("Przeliczam plan...");
  },

  apply(render) {
    const s = this.state;
    if (s.timer) clearTimeout(s.timer);
    s.timer = null;
    try {
      refreshPlan();
    } catch (e) {
      s.note = "Błąd planu: " + errText(e);
    }
    if (render) this.renderStatus();
  },

  test() {
    const s = this.state;
    if (s.timer) this.apply(false);
    try {
      const item = scheduleTest();
      s.note = item.alarm
        ? "Próba o " + clockText(item.at, localOffsetMin()) + ". Wyjdź z aplikacji i opuść rękę."
        : "System nie ustawił budzika próby.";
    } catch (e) {
      s.note = "Błąd próby: " + errText(e);
    }
    this.renderStatus();
  },

  renderSettings() {
    const s = this.state;
    const on = s.settings.on;
    s.toggle.bg.setProperty(hmUI.prop.MORE, toggleBg(on));
    s.toggle.text.setProperty(hmUI.prop.MORE, toggleText(on));
    ROWS.forEach((row, i) => s.values[i].setProperty(hmUI.prop.MORE, rowValue(i, row.text(s.settings), row.always || on)));
    s.reveal.setProperty(hmUI.prop.MORE, revealValue(revealText(s.settings.reveal)));
  },

  renderStatus(pending) {
    const s = this.state;
    if (!s.status) return;
    const now = Date.now();
    const tz = localOffsetMin();
    let lines = pending ? [pending] : planLines(loadPlan(), now, tz);
    const shown = loadShown();
    if (shown.length) lines = lines.concat(["Ostatnio: " + whenText(shown[shown.length - 1].at, now, tz)]);
    if (s.note) lines = lines.concat([s.note]);
    s.status.setProperty(hmUI.prop.MORE, { ...STATUS_STYLE, text: lines.join("\n") });
  },
});
