// Galaktyka: podróż Milano napędzana krokami z zegarka (utils/galaxy.js). Dzisiejsze kroki
// i energia, cel lotu z paskiem postępu, pocztówki z odwiedzonych planet (stuknij = opis).
import { load, apply, tz } from "../../../utils/store";
import { PLANETS, ENERGY, addSteps, tripInfo } from "../../../utils/galaxy";
import { readSteps } from "../../../utils/device";
import { COLOR, label, image, rect, onTap } from "../../../utils/ui";
import { TITLE, LINES, BAR, CARDS, INFO } from "zosLoader:./index.page.[pf].layout.js";

function num(n) {
  // 12345 -> "12 345"
  return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
}

Page({
  state: {},

  build() {
    const s = this.state;
    // świeże kroki: ta strona też dopisuje je do podróży
    const steps = readSteps();
    let p = load().state;
    if (steps !== null) p = apply((st) => ({ state: addSteps(st, steps, Date.now(), tz()).state })).state;
    const t = tripInfo(p);

    label({ ...TITLE, text: "Galaktyka" });
    label({ ...LINES[0], text: steps === null ? "Brak dostępu do kroków" : "Dziś " + num(t.today) + " kroków · energia +" + t.energy + "/" + ENERGY.maxPerDay, color: COLOR.grey });
    label({ ...LINES[1], text: "Milano leci na: " + t.next.name, color: COLOR.accent });
    rect(BAR.x, BAR.y, BAR.w, BAR.h, COLOR.pill, BAR.h / 2);
    const fill = Math.max(BAR.h, Math.round((BAR.w * t.progress) / t.next.need));
    rect(BAR.x, BAR.y, fill, BAR.h, 0x3f8ad8, BAR.h / 2);
    label({ ...LINES[2], text: num(t.progress) + " / " + num(t.next.need) + " kroków" + (t.rounds ? " · podróż " + (t.rounds + 1) : "") });

    s.info = label({ ...INFO, text: "Pocztówki: " + t.visited.length + "/" + PLANETS.length + " - stuknij", color: COLOR.grey });
    PLANETS.forEach((pl, i) => {
      const seen = t.visited.indexOf(pl.id) >= 0;
      const c = CARDS[i];
      const w = image("ui/pc_" + pl.id + (seen ? "" : "_x") + ".png", c.x, c.y);
      onTap([w.widget], () => {
        const here = t.visiting === pl.id ? " (jesteś tu)" : "";
        s.info.set(seen ? pl.name + here + ": " + pl.note : "Jeszcze nie dolecieliście", seen ? COLOR.text : COLOR.grey);
      });
    });
    if (t.visiting) s.info.set("Groot zwiedza: " + PLANETS.find((x) => x.id === t.visiting).name, COLOR.good);
  },
});
