// Poranne ważenie: ekran startuje od ostatniego pomiaru, − / + zmienia o 0,1 kg
// (przytrzymanie powtarza coraz szybciej, przyciski zegarka góra/dół też działają),
// ZAPISZ zapisuje dzisiejszy pomiar. Stuknięcie w wykres otwiera historię.
// Po zalogowaniu (ustawienia w aplikacji Zepp) pomiary synchronizują się z telefonem
// przy otwarciu i po każdym zapisie (waga/SYNC.md).
import * as hmUI from "@zos/ui";
import { push } from "@zos/router";
import { onKey, offKey, KEY_UP, KEY_DOWN, KEY_EVENT_CLICK, showToast } from "@zos/interaction";
import { setWakeUpRelaunch } from "@zos/display";
import { Vibrator, VIBRATOR_SCENE_SHORT_MIDDLE } from "@zos/sensor";
import { BasePage } from "@zeppos/zml/base-page";
import {
  stepW,
  formatKg,
  shortDate,
  entryFor,
  startValue,
  series,
  average,
  changeInfo,
  barHeights,
  repeatDelay,
} from "../../../utils/weight";
import { loadData, saveToday, todayKey } from "../../../utils/store";
import { syncNow } from "../../../utils/sync";
import {
  DATE_STYLE,
  SYNC_STYLE,
  VALUE_STYLE,
  UNIT_STYLE,
  MINUS_BTN,
  PLUS_BTN,
  CHANGE_STYLE,
  AVG_STYLE,
  CHART_DAYS,
  CHART,
  BAR_MIN_H,
  CHART_HIT,
  barRect,
  gapRect,
  SAVE_BG,
  SAVE_STYLE,
  COLOR_TEXT,
  COLOR_GREY,
  COLOR_DIM,
  COLOR_ORANGE,
  COLOR_GREEN,
  COLOR_RED,
  COLOR_PILL,
  COLOR_PILL_DOWN,
  COLOR_BUTTON,
} from "zosLoader:./index.page.[pf].layout.js";

const HISTORY_PAGE = "page/gt/history/index.page";
const MAX_REPEATS = 300; // bezpiecznik, gdyby puszczenie palca nie dotarło
const DAY_POLL_MS = 30000; // ekran otwarty przez północ

function onTap(widgets, handler) {
  widgets.forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, handler));
}

Page(
  BasePage({
    state: {},

    build() {
      const s = this.state;
      try {
        setWakeUpRelaunch({ relaunch: true });
      } catch (e) {}

      s.date = hmUI.createWidget(hmUI.widget.TEXT, DATE_STYLE);
      s.syncText = hmUI.createWidget(hmUI.widget.TEXT, SYNC_STYLE);
      s.value = hmUI.createWidget(hmUI.widget.TEXT, VALUE_STYLE);
      hmUI.createWidget(hmUI.widget.TEXT, UNIT_STYLE);
      s.minus = this.buildButton(MINUS_BTN, -1);
      s.plus = this.buildButton(PLUS_BTN, 1);
      s.change = hmUI.createWidget(hmUI.widget.TEXT, CHANGE_STYLE);
      s.avg = hmUI.createWidget(hmUI.widget.TEXT, AVG_STYLE);

      const hit = hmUI.createWidget(hmUI.widget.FILL_RECT, CHART_HIT);
      s.bars = [];
      for (let i = 0; i < CHART_DAYS; i++) {
        s.bars.push(hmUI.createWidget(hmUI.widget.FILL_RECT, { ...gapRect(i), color: COLOR_DIM }));
      }
      onTap([hit, ...s.bars], () => {
        if (Date.now() - (s.pushedAt || 0) < 1000) return;
        s.pushedAt = Date.now();
        this.stopHold();
        push({ url: HISTORY_PAGE });
      });

      s.saveBg = hmUI.createWidget(hmUI.widget.FILL_RECT, SAVE_BG);
      s.saveText = hmUI.createWidget(hmUI.widget.TEXT, SAVE_STYLE);
      onTap([s.saveBg, s.saveText], () => this.save());

      this.reload();
      s.dayTimer = setInterval(() => {
        if (todayKey() !== s.today && !s.holding) this.reload();
      }, DAY_POLL_MS);

      try {
        onKey({
          callback: (key, event) => {
            if (key !== KEY_UP && key !== KEY_DOWN) return false;
            if (event === KEY_EVENT_CLICK) this.step(key === KEY_UP ? 1 : -1);
            return true;
          },
        });
        s.keyHooked = true;
      } catch (e) {}

      this.sync();
    },

    // Telefon dał znać, że w ustawieniach zalogowano się - synchronizuj od razu
    onCall(req) {
      if (req && req.type === "LOGGED_IN") this.sync();
    },

    sync() {
      const s = this.state;
      syncNow(this, (r) => {
        if (s.destroyed) return;
        if (r.changed) this.applyRemote();
        let msg = "";
        if (r.needsLogin) msg = "Zaloguj: Zepp → Waga → ustawienia";
        else if (r.offline) msg = "Telefon niedostępny";
        else if (!r.ok && !r.notConfigured) msg = "Synchronizacja: " + (r.error || "błąd");
        s.syncText.setProperty(hmUI.prop.TEXT, msg);
      });
    },

    // Z telefonu przyszły zmiany (poprawka, usunięcie, pomiar z innego dnia). Wagę na ekranie
    // podmieniamy tylko, gdy użytkownik jej właśnie nie zmienia.
    applyRemote() {
      const s = this.state;
      if (todayKey() !== s.today) return this.reload();
      const untouched = !s.holding && s.current === startValue(s.data, s.today);
      s.data = loadData();
      if (untouched) s.current = startValue(s.data, s.today);
      this.render();
    },

    onDestroy() {
      const s = this.state;
      s.destroyed = true;
      this.stopHold();
      if (s.dayTimer) clearInterval(s.dayTimer);
      if (s.keyHooked) {
        try {
          offKey();
        } catch (e) {}
      }
      try {
        if (s.vibrator) s.vibrator.stop();
      } catch (e) {}
    },

    // Przycisk −/+: krok od razu przy dotknięciu, przytrzymanie powtarza
    buildButton(spec, dir) {
      const circle = hmUI.createWidget(hmUI.widget.CIRCLE, spec.circle);
      const text = hmUI.createWidget(hmUI.widget.TEXT, spec.text);
      const btn = { circle, text, spec };
      [circle, text].forEach((w) => {
        w.addEventListener(hmUI.event.CLICK_DOWN, () => this.startHold(btn, dir));
        w.addEventListener(hmUI.event.CLICK_UP, () => this.stopHold());
        w.addEventListener(hmUI.event.MOVE_OUT, () => this.stopHold());
      });
      return btn;
    },

    startHold(btn, dir) {
      const s = this.state;
      // to samo dotknięcie może przyjść z koła i z napisu na nim
      const now = Date.now();
      if (s.holding && s.holding.btn === btn && now - s.holding.at < 150) return;
      this.stopHold();
      s.holding = { btn, dir, n: 0, at: now };
      btn.circle.setProperty(hmUI.prop.MORE, { ...btn.spec.circle, color: COLOR_PILL_DOWN });
      this.step(dir);
      this.scheduleRepeat();
    },

    scheduleRepeat() {
      const s = this.state;
      const h = s.holding;
      if (!h) return;
      h.n++;
      s.holdTimer = setTimeout(() => {
        s.holdTimer = null;
        if (!s.holding || h.n > MAX_REPEATS) return this.stopHold();
        const before = s.current;
        this.step(h.dir);
        if (s.current === before) return this.stopHold(); // granica zakresu
        this.scheduleRepeat();
      }, repeatDelay(h.n));
    },

    stopHold() {
      const s = this.state;
      if (s.holdTimer) clearTimeout(s.holdTimer);
      s.holdTimer = null;
      if (s.holding) {
        const btn = s.holding.btn;
        btn.circle.setProperty(hmUI.prop.MORE, { ...btn.spec.circle, color: COLOR_PILL });
      }
      s.holding = null;
    },

    step(dir) {
      const s = this.state;
      const next = stepW(s.current, dir);
      if (next === s.current) return;
      s.current = next;
      this.render();
    },

    // Dane z pliku + dzisiejszy dzień -> ekran (start, po zapisie, po północy)
    reload() {
      const s = this.state;
      s.today = todayKey();
      s.data = loadData();
      s.current = startValue(s.data, s.today);
      s.date.setProperty(hmUI.prop.TEXT, shortDate(s.today));
      this.render();
    },

    render() {
      const s = this.state;
      const saved = entryFor(s.data, s.today);
      const dirty = !saved || saved.w !== s.current;

      s.value.setProperty(hmUI.prop.MORE, { ...VALUE_STYLE, text: formatKg(s.current), color: dirty ? COLOR_TEXT : COLOR_GREEN });

      const ch = changeInfo(s.data, s.today, s.current);
      const chColor = !ch || ch.sign === 0 ? COLOR_GREY : ch.sign < 0 ? COLOR_GREEN : COLOR_RED;
      s.change.setProperty(hmUI.prop.MORE, { ...CHANGE_STYLE, text: ch ? ch.text : "pierwszy pomiar", color: chColor });

      const values = series(s.data, s.today, CHART_DAYS, s.current);
      const avg = average(values.slice(-7));
      s.avg.setProperty(hmUI.prop.TEXT, avg === null ? "" : "średnia 7 dni: " + formatKg(avg) + " kg");

      const heights = barHeights(values, CHART.h, BAR_MIN_H, 20);
      s.bars.forEach((bar, i) => {
        const h = heights[i];
        const today = i === CHART_DAYS - 1;
        const rect = h === null ? gapRect(i) : barRect(i, h);
        const color = h === null ? COLOR_DIM : today ? COLOR_ORANGE : COLOR_GREY;
        bar.setProperty(hmUI.prop.MORE, { ...rect, color });
      });

      s.saveBg.setProperty(hmUI.prop.MORE, { ...SAVE_BG, color: dirty ? COLOR_BUTTON : COLOR_PILL });
      s.saveText.setProperty(hmUI.prop.MORE, {
        ...SAVE_STYLE,
        text: dirty ? (saved ? "POPRAW" : "ZAPISZ") : "ZAPISANO",
        color: dirty ? COLOR_TEXT : COLOR_GREEN,
      });
    },

    save() {
      const s = this.state;
      this.stopHold();
      const saved = entryFor(s.data, s.today);
      if (saved && saved.w === s.current) return;
      // dzień liczymy w chwili zapisu (ekran mógł wisieć przez północ)
      if (todayKey() !== s.today) {
        const w = s.current;
        this.reload();
        s.current = w;
      }
      const data = saveToday(s.current);
      if (!data) {
        try {
          showToast({ content: "Nie udało się zapisać" });
        } catch (e) {}
        return;
      }
      s.data = data;
      this.render();
      this.sync();
      try {
        if (!s.vibrator) s.vibrator = new Vibrator();
        s.vibrator.stop();
        s.vibrator.setMode(VIBRATOR_SCENE_SHORT_MIDDLE);
        s.vibrator.start();
      } catch (e) {}
    },

    // Powrót z historii - nic się tam nie zmienia, ale dzień mógł minąć
    onResume() {
      const s = this.state;
      if (s.today && todayKey() !== s.today) this.reload();
    },
  })
);
