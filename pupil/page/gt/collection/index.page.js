// Kolekcja form: zdobyte widać w kolorze, pozostałe jako cień. Stuknięcie = nazwa i jak ją zdobyć.
import { FORMS, FORM_ORDER } from "../../../utils/pet";
import { load } from "../../../utils/store";
import { COLOR, label, image, onTap, daysText } from "../../../utils/ui";
import { THUMB } from "../../../utils/geometry";
import { TITLE, ROWS, STEP, INFO, INFO2 } from "zosLoader:./index.page.[pf].layout.js";

const HOW = {
  pisklak: "maluch - wykluwa się z jajka",
  tupek: "dziecko - maluch bez błędów",
  gapcio: "dziecko - maluch z błędami",
  rogal: "nastolatek - wzorowa opieka",
  kolec: "nastolatek - 2-3 błędy",
  lobuz: "nastolatek - zaniedbany",
  rex: "dorosły - wzorowo i z dyscypliną",
  szyjek: "dorosły - dobra opieka",
  ptero: "dorosły - średnia opieka",
  burczek: "dorosły - zaniedbany",
};

Page({
  state: {},

  build() {
    const s = this.state;
    const p = load().state;
    const seen = p.seen || [];
    label({ ...TITLE, text: "Kolekcja " + seen.length + "/" + FORM_ORDER.length });
    s.info = label({ ...INFO, text: "Stuknij postać", color: COLOR.grey });
    const last = p.history && p.history[p.history.length - 1];
    s.info2 = label({
      ...INFO2,
      color: COLOR.grey,
      text: last ? "Poprzednio: " + FORMS[last.form].name + ", " + daysText(last.days) : "",
    });
    ROWS.forEach((row) => {
      const x0 = 240 - (row.forms.length * STEP - (STEP - THUMB)) / 2;
      row.forms.forEach((id, i) => {
        const got = seen.indexOf(id) >= 0;
        const w = image("thumb/" + id + (got ? "" : "_x") + ".png", x0 + i * STEP, row.y);
        onTap([w.widget], () => {
          s.info.set(got ? FORMS[id].name : "???", got ? COLOR.accent : COLOR.grey);
          s.info2.set(HOW[id]);
        });
      });
    });
  },
});
