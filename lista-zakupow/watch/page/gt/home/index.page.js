import * as hmUI from "@zos/ui";
import { push } from "@zos/router";
import { log as Logger, px } from "@zos/utils";
import { BasePage } from "@zeppos/zml/base-page";
import { counts } from "../../../utils/shopping";
import { syncStatus, shorten } from "../../../utils/format";
import { loadData, loadPending, viewLists, sync, saveIncoming } from "../../../utils/store";
import { stayInApp } from "../../../utils/screen";
import { button, wideRect } from "../../../utils/ui";
import {
  DEVICE_WIDTH,
  TITLE_STYLE,
  STATUS_STYLE,
  MESSAGE_STYLE,
  rowRect,
  rowBgProps,
  rowNameStyle,
  rowCountStyle,
  rowDoneIconProps,
  bottomSpacerProps,
  COLOR_GREY,
  COLOR_ORANGE,
} from "zosLoader:./index.page.[pf].layout.js";

const logger = Logger.getLogger("zakupy-home");

// Co tyle sprawdzamy, czy dane w pamięci zegarka się zmieniły (np. po powrocie z ekranu listy)
const WATCH_MS = 2000;
// Niewysłane zmiany (np. brak zasięgu) próbujemy wysłać ponownie co tyle
const RETRY_MS = 15000;

function snapshot(lists, pending) {
  return JSON.stringify([lists.map((l) => [l.id, l.name, counts(l)]), pending, loadData().fetchedAt]);
}

Page(
  BasePage({
    state: {
      status: null,
      rowWidgets: [],
      offline: false,
      problem: "",
      shown: "",
      timer: null,
      lastSyncAt: 0,
    },

    build() {
      const s = this.state;
      stayInApp();
      const title = hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);
      title.addEventListener(hmUI.event.CLICK_UP, () => this.refresh());
      s.status = hmUI.createWidget(hmUI.widget.TEXT, STATUS_STYLE);
      s.status.addEventListener(hmUI.event.CLICK_UP, () => this.refresh());
      this.render();
      this.refresh();
      // Po powrocie z innego ekranu dane mogły się zmienić - przerysuj, jeśli tak
      s.timer = setInterval(() => {
        if (snapshot(viewLists(), loadPending().length) !== s.shown) this.render();
        if (loadPending().length && Date.now() - s.lastSyncAt > RETRY_MS) this.refresh();
      }, WATCH_MS);
    },

    // Telefon przysłał listy sam (np. zaraz po zalogowaniu w ustawieniach)
    onCall(req) {
      if (req && req.type === "DATA") {
        saveIncoming(req.result);
        this.state.problem = "";
        this.render();
      }
    },

    refresh() {
      this.state.lastSyncAt = Date.now();
      this.setStatus("synchronizacja...", COLOR_GREY);
      sync(this, (r) => {
        const s = this.state;
        s.offline = !!r.offline;
        s.problem = r.ok || r.offline ? "" : r.error || "Błąd synchronizacji";
        if (r.needsLogin) s.problem = "Zaloguj się: aplikacja Zepp → zegarek → Zakupy → ustawienia";
        this.render();
      });
    },

    render() {
      const s = this.state;
      s.rowWidgets.forEach((w) => hmUI.deleteWidget(w));
      s.rowWidgets = [];

      const lists = viewLists();
      const pending = loadPending().length;
      s.shown = snapshot(lists, pending);
      if (s.problem) {
        this.setStatus(shorten(s.problem, 40), COLOR_ORANGE);
      } else {
        this.setStatus(syncStatus(loadData().fetchedAt, pending, s.offline), s.offline ? COLOR_ORANGE : COLOR_GREY);
      }

      let y;
      if (!lists.length) {
        const text = s.problem ? s.problem : "Brak list.\nUtwórz listę tutaj albo w aplikacji Zakupy na telefonie.";
        const msg = hmUI.createWidget(hmUI.widget.TEXT, { ...MESSAGE_STYLE, text });
        msg.addEventListener(hmUI.event.CLICK_UP, () => this.refresh());
        s.rowWidgets.push(msg);
        y = MESSAGE_STYLE.y + MESSAGE_STYLE.h;
      } else {
        lists.forEach((list, i) => {
          const c = counts(list);
          const open = () => push({ url: "page/gt/list/index.page", params: JSON.stringify({ id: list.id }) });
          const bg = hmUI.createWidget(hmUI.widget.FILL_RECT, rowBgProps(i));
          const name = hmUI.createWidget(hmUI.widget.TEXT, { ...rowNameStyle(i), text: list.name });
          const widgets = [bg, name];
          if (c.total > 0 && c.todo === 0) {
            widgets.push(hmUI.createWidget(hmUI.widget.IMG, rowDoneIconProps(i)));
          } else {
            widgets.push(
              hmUI.createWidget(hmUI.widget.TEXT, {
                ...rowCountStyle(i),
                text: c.total ? c.todo + "/" + c.total : "0",
              })
            );
          }
          widgets.forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, open));
          s.rowWidgets.push(...widgets);
        });
        y = rowRect(lists.length).y + px(8);
      }

      s.rowWidgets.push(
        button(wideRect(y, DEVICE_WIDTH), "+ Nowa lista", "primary", () =>
          push({ url: "page/gt/add/index.page", params: JSON.stringify({ mode: "list" }) })
        )
      );
      y += px(76);
      s.rowWidgets.push(
        button(wideRect(y, DEVICE_WIDTH), "Ustawienia", "secondary", () => push({ url: "page/gt/settings/index.page" }))
      );
      y += px(76);
      s.rowWidgets.push(hmUI.createWidget(hmUI.widget.FILL_RECT, bottomSpacerProps(y)));
    },

    setStatus(text, color) {
      this.state.status.setProperty(hmUI.prop.MORE, { ...STATUS_STYLE, text, color });
    },

    onDestroy() {
      logger.debug("home onDestroy");
      if (this.state.timer) clearInterval(this.state.timer);
    },
  })
);
