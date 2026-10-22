// Znaczenie terenu (GPS, zadanie spacerowe): oznacz 3 miejsca oddalone od siebie
// o co najmniej 100 m (w ciągu doby). Na spacerze otwórz tę grę w nowym miejscu
// i stuknij "Oznacz tu".
import * as hmUI from "@zos/ui";
import { VIBRATOR_SCENE_SHORT_MIDDLE, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { MARKS, marksStatus, addMark } from "../../../utils/walks";
import { getWalk, setWalk } from "../../../utils/pet";
import { load, apply } from "../../../utils/store";
import { startGps } from "../../../utils/sensors";
import { createBuzzer } from "../../../utils/device";
import { COLOR, label, image, button } from "../../../utils/ui";
import { finishWalk } from "../../../utils/gameui";
import { header, petForm } from "../../../utils/gamekit";
import { PET, FLAGS, INFO, MARK_BTN } from "zosLoader:./index.page.[pf].layout.js";

const TICK_MS = 1000;
const KEY = "marks";

Page({
  state: {},

  build() {
    const s = this.state;
    s.buzzer = createBuzzer();
    s.hint = header("Znaczenie terenu", MARKS.need + " miejsca, co najmniej " + MARKS.spacing + " m od siebie");
    image("thumb/" + petForm() + ".png", PET.x, PET.y);
    s.flags = [];
    for (let i = 0; i < MARKS.need; i++) s.flags.push(image("ui/nest.png", FLAGS.x + i * FLAGS.step, FLAGS.y));
    s.info = label({ ...INFO, color: COLOR.grey });
    s.btn = button(MARK_BTN, () => this.mark());
    s.gps = startGps();
    s.msg = "";
    this.tick();
    s.timer = setInterval(() => this.tick(), TICK_MS);
  },

  onDestroy() {
    const s = this.state;
    if (s.timer) clearInterval(s.timer);
    s.gps.stop();
    s.buzzer.stop();
  },

  mark() {
    const s = this.state;
    const fix = s.gps.read();
    if (!fix) {
      s.msg = "Czekam na GPS - wyjdź pod gołe niebo";
      this.tick();
      return;
    }
    let res = null;
    apply((p) => {
      res = addMark(getWalk(p, KEY), fix, Date.now());
      return { state: setWalk(p, KEY, res.task) };
    });
    if (res.result === "near") s.msg = "Za blisko poprzedniego (" + res.nearest + " m) - przejdź dalej";
    else {
      s.msg = "Oznaczone!";
      s.buzzer.buzz(VIBRATOR_SCENE_SHORT_MIDDLE);
    }
    this.tick();
  },

  tick() {
    const s = this.state;
    if (s.finished) return;
    const st = marksStatus(getWalk(load().state, KEY), Date.now());
    s.flags.forEach((w, i) => w.set(i < st.count ? "ui/nest.png" : "ui/rock.png"));
    if (st.state === "done") {
      clearInterval(s.timer);
      s.timer = null;
      s.info.set("");
      s.btn.bg.setProperty(hmUI.prop.VISIBLE, false);
      s.btn.txt.widget.setProperty(hmUI.prop.VISIBLE, false);
      s.buzzer.buzz(VIBRATOR_SCENE_NOTIFICATION);
      finishWalk(s, KEY, "Teren oznaczony!");
      return;
    }
    const fix = s.gps.read();
    const base = "Oznaczone " + st.count + "/" + MARKS.need + ". " + (fix ? "GPS gotowy." : "Szukam GPS…");
    s.info.set(s.msg ? s.msg + " " + base : base, s.msg === "Oznaczone!" ? COLOR.good : COLOR.grey);
  },
});
