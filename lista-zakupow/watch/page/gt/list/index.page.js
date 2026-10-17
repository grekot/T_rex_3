import * as hmUI from "@zos/ui";
import { push, back } from "@zos/router";
import { showToast, createModal, MODAL_CONFIRM } from "@zos/interaction";
import { Vibrator, VIBRATOR_SCENE_SHORT_LIGHT } from "@zos/sensor";
import { log as Logger, px } from "@zos/utils";
import { BasePage } from "@zeppos/zml/base-page";
import { sortItems, counts, findList, toggleOp, delItemOp, removeListOp, isOwn, isShared } from "../../../utils/shopping";
import { syncStatus, shorten } from "../../../utils/format";
import { loadData, loadPending, loadSettings, viewLists, addOp, sync, saveIncoming } from "../../../utils/store";
import { stayInApp, keepBright, holdOnWristDrop } from "../../../utils/screen";
import { button, pairRects, wideRect } from "../../../utils/ui";
import {
  DEVICE_WIDTH,
  HEADER_STYLE,
  SUB_STYLE,
  LABEL_H,
  startY,
  rowStep,
  rowBgProps,
  rowCheckProps,
  rowNameStyle,
  labelStyle,
  bottomSpacerProps,
  COLOR_GREEN,
  COLOR_ORANGE,
  COLOR_GREY,
} from "zosLoader:./index.page.[pf].layout.js";

const logger = Logger.getLogger("zakupy-list");

// Zmiany wysyłamy paczką chwilę po ostatnim stuknięciu
const SYNC_DELAY_MS = 1500;
// W sklepie ekran nie powinien gasnąć po kilku sekundach
const BRIGHT_MS = 60000;
// Co tyle sprawdzamy, czy lista w pamięci zegarka się zmieniła (np. po dodaniu produktów)
const WATCH_MS = 2000;
// Niewysłane zmiany (np. brak zasięgu) próbujemy wysłać ponownie co tyle
const RETRY_MS = 15000;

function parseParams(params) {
  try {
    return typeof params === "string" ? JSON.parse(params) : params || {};
  } catch (e) {
    return {};
  }
}

Page(
  BasePage({
    state: {
      listId: "",
      edit: false,
      header: null,
      sub: null,
      rowWidgets: [],
      syncTimer: null,
      watchTimer: null,
      shown: "",
      offline: false,
      lastSyncAt: 0,
      vibrator: null,
      destroyed: false,
    },

    onInit(params) {
      this.state.listId = parseParams(params).id || "";
    },

    build() {
      const s = this.state;
      stayInApp();
      keepBright(BRIGHT_MS);
      if (loadSettings().keepOnWristDrop) holdOnWristDrop(true);

      s.header = hmUI.createWidget(hmUI.widget.TEXT, HEADER_STYLE);
      s.sub = hmUI.createWidget(hmUI.widget.TEXT, SUB_STYLE);
      s.sub.addEventListener(hmUI.event.CLICK_UP, () => this.syncNow());
      this.render();
      this.syncNow();
      s.watchTimer = setInterval(() => {
        if (this.snapshot() !== s.shown) this.render();
        if (!s.syncTimer && loadPending().length && Date.now() - s.lastSyncAt > RETRY_MS) this.syncNow();
      }, WATCH_MS);
    },

    onDestroy() {
      const s = this.state;
      s.destroyed = true;
      if (s.syncTimer) clearTimeout(s.syncTimer);
      if (s.watchTimer) clearInterval(s.watchTimer);
      holdOnWristDrop(false);
      try {
        if (s.vibrator) s.vibrator.stop();
      } catch (e) {}
    },

    onCall(req) {
      if (req && req.type === "DATA") {
        saveIncoming(req.result);
        this.render();
      }
    },

    snapshot() {
      return JSON.stringify([findList(viewLists(), this.state.listId), loadPending().length, this.state.edit]);
    },

    syncNow() {
      const s = this.state;
      if (s.syncTimer) {
        clearTimeout(s.syncTimer);
        s.syncTimer = null;
      }
      s.lastSyncAt = Date.now();
      sync(this, (r) => {
        if (s.destroyed) return;
        s.offline = !!r.offline;
        this.render();
      });
    },

    scheduleSync() {
      const s = this.state;
      if (s.syncTimer) clearTimeout(s.syncTimer);
      s.syncTimer = setTimeout(() => {
        s.syncTimer = null;
        this.syncNow();
      }, SYNC_DELAY_MS);
    },

    toggle(item) {
      addOp(toggleOp(this.state.listId, item, Date.now()));
      this.vibrate();
      this.render();
      this.scheduleSync();
    },

    removeItem(item) {
      addOp(delItemOp(this.state.listId, item.id, Date.now()));
      this.vibrate();
      showToast({ content: "Usunięto: " + shorten(item.n, 30) });
      this.render();
      this.scheduleSync();
    },

    removeBought(list) {
      const now = Date.now();
      list.items.filter((i) => i.c).forEach((i) => addOp(delItemOp(list.id, i.id, now)));
      showToast({ content: "Usunięto kupione" });
      this.render();
      this.scheduleSync();
    },

    // Własną listę usuwamy (u wszystkich), z cudzej tylko się wypisujemy
    removeList(list) {
      const question = isOwn(list)
        ? isShared(list)
          ? "Usunąć listę „" + shorten(list.name, 20) + "” u wszystkich?"
          : "Usunąć listę „" + shorten(list.name, 24) + "”?"
        : "Opuścić listę „" + shorten(list.name, 24) + "”?";
      const dialog = createModal({
        content: question,
        autoHide: true,
        onClick: (key) => {
          if (key && key.type === MODAL_CONFIRM) {
            addOp(removeListOp(list, Date.now()));
            this.syncNow();
            back();
          }
        },
      });
      try {
        dialog.show(true);
      } catch (e) {}
    },

    setEdit(on) {
      this.state.edit = on;
      this.render();
    },

    render() {
      const s = this.state;
      s.rowWidgets.forEach((w) => hmUI.deleteWidget(w));
      s.rowWidgets = [];
      s.shown = this.snapshot();

      const list = findList(viewLists(), s.listId);
      if (!list) {
        this.setHeader("Lista usunięta");
        this.setSub("wróć gestem w prawo", COLOR_ORANGE);
        return;
      }
      const c = counts(list);
      this.setHeader(list.name);
      const pending = loadPending().length;
      const state = syncStatus(loadData().fetchedAt, pending, s.offline);
      const sub = s.edit
        ? "tryb edycji - stuknij, by usunąć"
        : "kupione " + c.done + " z " + c.total + (pending || s.offline ? " · " + state : isShared(list) ? " · wspólna" : "");
      this.setSub(sub, s.edit ? COLOR_ORANGE : s.offline ? COLOR_ORANGE : COLOR_GREY);

      const add = (w) => {
        s.rowWidgets.push(w);
        return w;
      };
      let y = startY();

      // Przyciski u góry listy
      const [left, right] = pairRects(y, DEVICE_WIDTH);
      if (s.edit) {
        add(button(left, "Gotowe", "primary", () => this.setEdit(false)));
        add(button(right, isOwn(list) ? "Usuń listę" : "Opuść listę", "danger", () => this.removeList(list)));
      } else {
        add(
          button(left, "+ Dodaj", "primary", () =>
            push({ url: "page/gt/add/index.page", params: JSON.stringify({ mode: "item", id: list.id }) })
          )
        );
        add(button(right, "Edytuj", "secondary", () => this.setEdit(true)));
      }
      y += left.h + px(14);

      if (s.edit && c.done > 0) {
        const rect = wideRect(y, DEVICE_WIDTH);
        add(button(rect, "Usuń kupione (" + c.done + ")", "danger", () => this.removeBought(list)));
        y += rect.h + px(14);
      }

      if (c.total === 0) {
        add(hmUI.createWidget(hmUI.widget.TEXT, labelStyle(y, "Lista jest pusta")));
        y += LABEL_H;
      } else if (c.todo === 0 && !s.edit) {
        add(hmUI.createWidget(hmUI.widget.TEXT, labelStyle(y, "Wszystko kupione!", COLOR_GREEN)));
        y += LABEL_H;
      }

      let doneLabelShown = false;
      sortItems(list.items).forEach((item) => {
        const done = !!item.c;
        if (done && !doneLabelShown && c.todo > 0) {
          add(hmUI.createWidget(hmUI.widget.TEXT, labelStyle(y, "KUPIONE (" + c.done + ")")));
          y += LABEL_H;
          doneLabelShown = true;
        }
        const tap = s.edit ? () => this.removeItem(item) : () => this.toggle(item);
        const bg = add(hmUI.createWidget(hmUI.widget.FILL_RECT, rowBgProps(y, done)));
        const icon = add(hmUI.createWidget(hmUI.widget.IMG, rowCheckProps(y, done, s.edit)));
        const name = add(hmUI.createWidget(hmUI.widget.TEXT, { ...rowNameStyle(y, done), text: item.n }));
        [bg, icon, name].forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, tap));
        y += rowStep();
      });
      add(hmUI.createWidget(hmUI.widget.FILL_RECT, bottomSpacerProps(y)));
    },

    setHeader(text) {
      this.state.header.setProperty(hmUI.prop.MORE, { ...HEADER_STYLE, text });
    },

    setSub(text, color) {
      this.state.sub.setProperty(hmUI.prop.MORE, { ...SUB_STYLE, text, color });
    },

    vibrate() {
      const s = this.state;
      try {
        if (!s.vibrator) {
          s.vibrator = new Vibrator();
          s.vibrator.setMode(VIBRATOR_SCENE_SHORT_LIGHT);
        }
        s.vibrator.start();
      } catch (e) {
        logger.debug("wibracje niedostępne: " + e);
      }
    },
  })
);
