// Ekran główny: ile szczytów zdobyto, karta GPS (najbliższy niezdobyty albo „Jesteś na szczycie!”
// z przyciskiem Zaliczam), postęp list (KGP, pasma, własne), „Dodaj szczyt tutaj”, stan telefonu.
import * as hmUI from "@zos/ui";
import { push } from "@zos/router";
import { showToast } from "@zos/interaction";
import { scrollTo } from "@zos/page";
import { px } from "@zos/utils";
import { BasePage } from "@zeppos/zml/base-page";
import { GROUPS, MY_GROUP, allPeaks } from "../../../utils/peaks";
import { bearing, formatDistance, cardinal } from "../../../utils/geo";
import {
  progress,
  totalClimbed,
  nearestUnclimbed,
  createSummitWatcher,
  climbOf,
  todayKey,
  formatDate,
  peakLine,
} from "../../../utils/korona";
import { loadClimbs, loadCustom, stamp, saveClimb, isDirty } from "../../../utils/store";
import { syncNow } from "../../../utils/sync";
import { startGps } from "../../../utils/sensors";
import { setupScreen, vibrate } from "../../../utils/device";
import { button, setText, onTap, COLOR_WHITE, COLOR_GREY, COLOR_GREEN, COLOR_ORANGE } from "../../../utils/ui";
import {
  TITLE_STYLE,
  COUNT_STYLE,
  COUNT_SUB_STYLE,
  CARD_BG,
  CARD_LINE1,
  CARD_LINE2,
  ACTION_RECT,
  rowY,
  rowBg,
  rowName,
  rowCount,
  rowBarTrack,
  rowBarFill,
  addRect,
  syncStyle,
  bottomSpacer,
} from "zosLoader:./index.page.[pf].layout.js";

const PEAK_PAGE = "page/gt/peak/index.page";
const GROUP_PAGE = "page/gt/group/index.page";
const NEAREST_PAGE = "page/gt/nearest/index.page";
const ADD_PAGE = "page/gt/add/index.page";
const STAMP_POLL_MS = 1000; // po powrocie z innych ekranów
const SYNC_RETRY_MS = 60000; // ponowna próba wysłania, gdy telefon był niedostępny

function plural(n) {
  if (n === 1) return "zdobyty szczyt";
  const d = n % 10;
  const t = n % 100;
  return d >= 2 && d <= 4 && (t < 12 || t > 14) ? "zdobyte szczyty" : "zdobytych szczytów";
}

Page(
  BasePage({
    state: {},

    build() {
      const s = this.state;
      s.fix = null;
      s.summit = null;
      s.watcher = createSummitWatcher();
      s.action = null;
      s.actionKey = "";
      s.rows = [];
      s.lastSyncTry = 0;
      setupScreen(30000);

      hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);
      s.count = hmUI.createWidget(hmUI.widget.TEXT, COUNT_STYLE);
      s.countSub = hmUI.createWidget(hmUI.widget.TEXT, COUNT_SUB_STYLE);

      const cardBg = hmUI.createWidget(hmUI.widget.FILL_RECT, CARD_BG);
      s.line1 = hmUI.createWidget(hmUI.widget.TEXT, CARD_LINE1);
      s.line2 = hmUI.createWidget(hmUI.widget.TEXT, CARD_LINE2);
      onTap([cardBg, s.line1, s.line2], () => this.cardTapped());

      GROUPS.forEach((group, i) => {
        const y = rowY(i);
        const row = {
          group,
          y,
          bg: hmUI.createWidget(hmUI.widget.FILL_RECT, rowBg(y)),
          name: hmUI.createWidget(hmUI.widget.TEXT, { ...rowName(y), text: group.name }),
          count: hmUI.createWidget(hmUI.widget.TEXT, rowCount(y)),
          track: hmUI.createWidget(hmUI.widget.FILL_RECT, rowBarTrack(y)),
        };
        row.fill = hmUI.createWidget(hmUI.widget.FILL_RECT, rowBarFill(y, 0, 1));
        onTap([row.bg, row.name, row.count], () => push({ url: GROUP_PAGE, params: JSON.stringify({ g: group.id }) }));
        s.rows.push(row);
      });
      let y = rowY(GROUPS.length) + px(6);
      button(addRect(y), "+ Dodaj szczyt tutaj", "secondary", () => push({ url: ADD_PAGE }), px(24));
      y += px(70);
      s.syncY = y;
      s.syncText = hmUI.createWidget(hmUI.widget.TEXT, syncStyle(y));
      hmUI.createWidget(hmUI.widget.FILL_RECT, bottomSpacer(y + px(56)));

      this.refresh();
      s.stampTimer = setInterval(() => {
        if (stamp() !== s.stamp) this.refresh();
        else if (isDirty() && Date.now() - s.lastSyncTry > SYNC_RETRY_MS) this.sync();
      }, STAMP_POLL_MS);

      s.gps = startGps((fix) => {
        s.fix = fix || s.fix;
        const r = s.watcher.update(fix, s.peaks);
        s.summit = r.peak;
        if (r.entered) this.onSummit();
        this.renderCard();
      });
    },

    onDestroy() {
      const s = this.state;
      if (s.stampTimer) clearInterval(s.stampTimer);
      if (s.gps) s.gps.stop();
    },

    // Telefon dał znać, że w ustawieniach zalogowano się - wyślij od razu
    onCall(req) {
      if (req && req.type === "LOGGED_IN") this.sync();
    },

    refresh() {
      const s = this.state;
      s.stamp = stamp();
      s.climbs = loadClimbs();
      s.custom = loadCustom();
      s.peaks = allPeaks(s.custom);
      const total = totalClimbed(s.climbs, s.custom);
      setText(s.count, COUNT_STYLE, String(total));
      setText(s.countSub, COUNT_SUB_STYLE, plural(total));
      s.rows.forEach((row) => {
        const p = progress(row.group.id, s.climbs, s.custom);
        const mine = row.group.id === MY_GROUP;
        setText(row.count, rowCount(row.y), mine ? String(p.done) : p.done + " / " + p.total, p.complete ? COLOR_GREEN : COLOR_GREY);
        row.fill.setProperty(hmUI.prop.MORE, rowBarFill(row.y, p.done, p.total || 1));
        row.fill.setProperty(hmUI.prop.VISIBLE, !mine && p.done > 0);
        row.track.setProperty(hmUI.prop.VISIBLE, !mine);
      });
      this.renderCard();
      this.sync();
    },

    sync() {
      const s = this.state;
      s.lastSyncTry = Date.now();
      syncNow(this, (r) => {
        if (r.busy) return;
        if (r.restored) {
          try {
            showToast({ content: "Przywrócono zdobycia z telefonu" });
          } catch (e) {}
          this.refresh();
          return;
        }
        if (r.nothing && s.syncShown) return;
        s.syncShown = true;
        let msg = "Telefon: zapisano";
        if (r.needsLogin) msg = "Telefon: zaloguj się w aplikacji Zepp → Korona → ustawienia";
        else if (r.offline) msg = "Telefon: brak połączenia, wyślę później";
        else if (!r.ok) msg = "Telefon: " + (r.error || "błąd");
        else if (r.nothing) msg = "Telefon: wszystko wysłane";
        setText(s.syncText, syncStyle(s.syncY), msg);
      });
    },

    renderCard() {
      const s = this.state;
      if (!s.line1) return;
      if (s.summit) {
        const c = climbOf(s.summit.id, s.climbs, s.custom);
        setText(s.line1, CARD_LINE1, "Jesteś na szczycie!", COLOR_GREEN);
        setText(s.line2, CARD_LINE2, s.summit.name + " · " + peakLine(s.summit) + (c ? " · zdobyty " + formatDate(c.d) : ""), COLOR_WHITE);
        this.setAction(c ? "details" : "climb");
        return;
      }
      if (!s.fix) {
        setText(s.line1, CARD_LINE1, "Szukam GPS...", COLOR_ORANGE);
        setText(s.line2, CARD_LINE2, "Szczyt zaliczysz, gdy otworzysz aplikację na wierzchołku", COLOR_GREY);
        this.setAction("nearest");
        return;
      }
      const near = nearestUnclimbed(s.fix, s.climbs, null, 1)[0];
      if (!near) {
        setText(s.line1, CARD_LINE1, "Wszystko zdobyte!", COLOR_GREEN);
        setText(s.line2, CARD_LINE2, "Każdy szczyt ze wszystkich list", COLOR_GREY);
        this.setAction("none");
        return;
      }
      const b = bearing(s.fix.lat, s.fix.lon, near.peak.lat, near.peak.lon);
      setText(s.line1, CARD_LINE1, "Najbliższy: " + near.peak.name, COLOR_WHITE);
      setText(s.line2, CARD_LINE2, formatDistance(near.distance) + " · " + cardinal(b) + " · " + near.peak.range, COLOR_GREY);
      this.setAction("nearest");
    },

    // Przycisk pod kartą - tworzony na nowo tylko przy zmianie rodzaju
    setAction(key) {
      const s = this.state;
      if (s.actionKey === key) return;
      s.actionKey = key;
      if (s.action) hmUI.deleteWidget(s.action);
      s.action = null;
      if (key === "climb") s.action = button(ACTION_RECT, "Zaliczam", "success", () => this.climb(), px(30));
      if (key === "details") s.action = button(ACTION_RECT, "Szczegóły", "secondary", () => this.cardTapped());
      if (key === "nearest") s.action = button(ACTION_RECT, "Najbliższe ›", "primary", () => this.cardTapped());
    },

    cardTapped() {
      const s = this.state;
      if (s.summit) push({ url: PEAK_PAGE, params: JSON.stringify({ id: s.summit.id }) });
      else if (s.actionKey !== "none") push({ url: NEAREST_PAGE });
    },

    onSummit() {
      vibrate();
      try {
        scrollTo({ y: 0 });
      } catch (e) {}
    },

    climb() {
      const s = this.state;
      if (!s.summit) return;
      const name = s.summit.name;
      saveClimb(s.summit.id, todayKey(Date.now()), true);
      try {
        showToast({ content: "Zaliczone: " + name });
      } catch (e) {}
      this.refresh();
    },
  })
);
