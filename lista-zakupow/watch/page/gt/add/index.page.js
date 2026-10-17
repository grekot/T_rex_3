// Dodawanie produktu do listy albo tworzenie nowej listy - z klawiatury, głosem lub z podpowiedzi.
import * as hmUI from "@zos/ui";
import { replace } from "@zos/router";
import { showToast } from "@zos/interaction";
import { px } from "@zos/utils";
import { BasePage } from "@zeppos/zml/base-page";
import {
  findList,
  planAdd,
  suggestions,
  listNameSuggestions,
  addItemOp,
  addListOp,
  toggleOp,
  cleanName,
} from "../../../utils/shopping";
import { shorten } from "../../../utils/format";
import { viewLists, addOp, loadHistory, remember, sync } from "../../../utils/store";
import { stayInApp, keepBright } from "../../../utils/screen";
import { canType, askText } from "../../../utils/input";
import { button, pairRects } from "../../../utils/ui";
import {
  DEVICE_WIDTH,
  TITLE_STYLE,
  SUB_STYLE,
  BUTTONS_Y,
  labelStyle,
  rowStep,
  rowBgProps,
  rowPlusStyle,
  rowNameStyle,
  bottomSpacerProps,
} from "zosLoader:./index.page.[pf].layout.js";

const SYNC_DELAY_MS = 1500;

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
      mode: "item", // "item" - produkt do listy, "list" - nowa lista
      listId: "",
      title: null,
      sub: null,
      widgets: [],
      syncTimer: null,
      destroyed: false,
    },

    onInit(params) {
      const p = parseParams(params);
      this.state.mode = p.mode === "list" ? "list" : "item";
      this.state.listId = p.id || "";
    },

    build() {
      const s = this.state;
      stayInApp();
      keepBright(60000);
      s.title = hmUI.createWidget(hmUI.widget.TEXT, {
        ...TITLE_STYLE,
        text: s.mode === "list" ? "NOWA LISTA" : "DODAJ DO",
      });
      s.sub = hmUI.createWidget(hmUI.widget.TEXT, SUB_STYLE);
      this.render();
    },

    onDestroy() {
      const s = this.state;
      s.destroyed = true;
      // Wyślij od razu; gdyby się nie udało, ekran listy ponowi wysyłkę sam
      if (s.syncTimer) {
        clearTimeout(s.syncTimer);
        sync(this, () => {});
      }
    },

    scheduleSync() {
      const s = this.state;
      if (s.syncTimer) clearTimeout(s.syncTimer);
      s.syncTimer = setTimeout(() => {
        s.syncTimer = null;
        sync(this, () => {});
      }, SYNC_DELAY_MS);
    },

    type(voice) {
      const ok = askText(voice, (text) => this.submit(text));
      if (!ok) showToast({ content: "Klawiatura wymaga Zepp OS 4" });
    },

    submit(rawName) {
      const s = this.state;
      const name = cleanName(rawName);
      if (!name) return;

      if (s.mode === "list") {
        const op = addListOp(name, Date.now());
        addOp(op);
        sync(this, () => {});
        // Od razu na nową listę; powrót gestem prowadzi do ekranu list
        replace({ url: "page/gt/list/index.page", params: JSON.stringify({ id: op.l }) });
        return;
      }

      const list = findList(viewLists(), s.listId);
      if (!list) {
        showToast({ content: "Lista została usunięta" });
        return;
      }
      const plan = planAdd(list, name);
      if (plan.action === "add") {
        addOp(addItemOp(list.id, name, Date.now()));
        remember(name);
        showToast({ content: "Dodano: " + shorten(name, 30) });
      } else if (plan.action === "uncheck") {
        addOp(toggleOp(list.id, plan.item, Date.now()));
        showToast({ content: "Wraca na listę: " + shorten(plan.item.n, 24) });
      } else if (plan.action === "exists") {
        showToast({ content: "Już jest na liście" });
        return;
      }
      this.render();
      this.scheduleSync();
    },

    render() {
      const s = this.state;
      s.widgets.forEach((w) => hmUI.deleteWidget(w));
      s.widgets = [];
      const add = (w) => {
        s.widgets.push(w);
        return w;
      };

      const lists = viewLists();
      let names;
      if (s.mode === "list") {
        s.sub.setProperty(hmUI.prop.MORE, { ...SUB_STYLE, text: "podaj nazwę" });
        names = listNameSuggestions(lists);
      } else {
        const list = findList(lists, s.listId);
        s.sub.setProperty(hmUI.prop.MORE, { ...SUB_STYLE, text: list ? list.name : "?" });
        names = suggestions(lists, s.listId, loadHistory());
      }

      let y = BUTTONS_Y;
      if (canType()) {
        const [left, right] = pairRects(y, DEVICE_WIDTH);
        add(button(left, "Wpisz", "primary", () => this.type(false)));
        add(button(right, "Podyktuj", "secondary", () => this.type(true)));
        y += left.h + px(14);
      } else {
        add(hmUI.createWidget(hmUI.widget.TEXT, labelStyle(y, "Wpisywanie wymaga Zepp OS 4 - wybierz z podpowiedzi")));
        y += px(56);
      }

      if (!names.length) {
        add(hmUI.createWidget(hmUI.widget.TEXT, labelStyle(y, "Brak podpowiedzi")));
        return;
      }
      add(hmUI.createWidget(hmUI.widget.TEXT, labelStyle(y, s.mode === "list" ? "SKLEPY" : "PODPOWIEDZI")));
      y += px(42);
      names.forEach((name) => {
        const tap = () => this.submit(name);
        const bg = add(hmUI.createWidget(hmUI.widget.FILL_RECT, rowBgProps(y)));
        const plus = add(hmUI.createWidget(hmUI.widget.TEXT, rowPlusStyle(y)));
        const text = add(hmUI.createWidget(hmUI.widget.TEXT, { ...rowNameStyle(y), text: name }));
        [bg, plus, text].forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, tap));
        y += rowStep();
      });
      add(hmUI.createWidget(hmUI.widget.FILL_RECT, bottomSpacerProps(y)));
    },
  })
);
