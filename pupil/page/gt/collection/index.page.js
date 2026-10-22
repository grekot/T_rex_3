// Kolekcja form: zdobyte widać w kolorze, pozostałe jako cień. Stuknięcie = nazwa i jak ją zdobyć.
import { FORMS, FORM_ORDER, LINES, LINE_ORDER, SHARED } from "../../../utils/pet";
import { load } from "../../../utils/store";
import { COLOR, label, image, onTap, daysText } from "../../../utils/ui";
import { THUMB } from "../../../utils/geometry";
import { TITLE, ROW_Y, STEP, INFO, INFO2 } from "zosLoader:./index.page.[pf].layout.js";

const ROLE = {
  baby: "maluch - wykluwa się z jajka",
  child: "dziecko - maluch bez błędów",
  teen: "nastolatek - dobra opieka",
  best: "dorosły - wzorowo i z dyscypliną",
  good: "dorosły - dobra opieka",
};
const SHARED_HOW = {
  gapcio: "dziecko - maluch z błędami",
  mruk: "nastolatek - zaniedbany",
  burczek: "dorosły - zaniedbany",
};

Page({
  state: {},

  build() {
    const s = this.state;
    const p = load().state;
    const seen = (p.seen || []).filter((f) => FORM_ORDER.indexOf(f) >= 0);
    label({ ...TITLE, text: "Kolekcja " + seen.length + "/" + FORM_ORDER.length });
    s.info = label({ ...INFO, text: "Stuknij postać", color: COLOR.grey });
    const last = p.history && p.history[p.history.length - 1];
    s.info2 = label({
      ...INFO2,
      color: COLOR.grey,
      text: last ? "Poprzednio: " + FORMS[last.form].name + ", " + daysText(last.days) : "",
    });

    const rows = LINE_ORDER.map((id) => {
      const L = LINES[id];
      return ["baby", "child", "teen", "best", "good"].map((role) => ({
        form: L[role],
        title: FORMS[L[role]].name + " · " + L.name.toLowerCase(),
        how: ROLE[role],
      }));
    });
    rows.push(SHARED.map((f) => ({ form: f, title: FORMS[f].name + " · zaniedbany", how: SHARED_HOW[f] })));

    rows.forEach((row, r) => {
      const x0 = 240 - (row.length * STEP - (STEP - THUMB)) / 2;
      row.forEach((cell, i) => {
        const got = seen.indexOf(cell.form) >= 0;
        const w = image("thumb/" + cell.form + (got ? "" : "_x") + ".png", x0 + i * STEP, ROW_Y[r]);
        onTap([w.widget], () => {
          s.info.set(got ? cell.title : "???", got ? COLOR.accent : COLOR.grey);
          s.info2.set(cell.how);
        });
      });
    });
  },
});
