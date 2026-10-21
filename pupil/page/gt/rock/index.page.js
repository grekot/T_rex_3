// Kołysanie do snu: delikatne bujanie ręką napełnia pasek snu, za mocne albo
// szarpnięcie budzi dinozaura. 3 pobudki albo koniec czasu = przegrana.
import { VIBRATOR_SCENE_SHORT_LIGHT, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { ROCK, createRocker } from "../../../utils/games";
import { load } from "../../../utils/store";
import { startAccel, readAccel, stopAccel, keepScreenOn, releaseScreen, createBuzzer } from "../../../utils/device";
import { COLOR, label, image, rect, spriteSrc } from "../../../utils/ui";
import { finishGame } from "../../../utils/gameui";
import { TITLE, HINT, PET, BAR, STRIKES } from "zosLoader:./index.page.[pf].layout.js";
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";

const POLL_MS = 40;

const HINTS = {
  still: ["Kołysz delikatnie", COLOR.grey],
  gentle: ["Dobrze… zasypia", COLOR.good],
  strong: ["Trochę za mocno", COLOR.accent],
  hard: ["Za mocno! Obudził się", COLOR.bad],
};

Page({
  state: {},

  build() {
    const s = this.state;
    keepScreenOn();
    s.buzzer = createBuzzer();
    s.form = load().state.form;
    s.rocker = createRocker();
    s.strikes = 0;
    s.t0 = Date.now();

    label({ ...TITLE, text: "Kołysanie do snu" });
    s.hint = label({ ...HINT, text: HINTS.still[0], color: HINTS.still[1] });
    s.pet = image(spriteSrc(s.form, "idle0"), PET.x, PET.y);
    rect(BAR.x, BAR.y, BAR.w, BAR.h, 0x26262e, BAR.h / 2);
    s.bar = rect(BAR.x, BAR.y, BAR.h, BAR.h, 0x6f8cff, BAR.h / 2);
    s.barW = 0;
    s.strikeText = label({ ...STRIKES, color: COLOR.grey });
    this.renderStrikes();

    s.accel = startAccel();
    if (!s.accel.sensor) s.hint.set("Brak akcelerometru", COLOR.bad);
    s.poll = setInterval(() => this.poll(), POLL_MS);
  },

  onDestroy() {
    const s = this.state;
    if (s.poll) clearInterval(s.poll);
    stopAccel(s.accel);
    s.buzzer.stop();
    releaseScreen();
  },

  renderStrikes() {
    const s = this.state;
    s.strikeText.set("Pobudki: " + s.strikes + "/" + ROCK.strikes + " · " + Math.max(0, Math.ceil((ROCK.limit - s.rocker.state.elapsed) / 1000)) + " s");
  },

  poll() {
    const s = this.state;
    const now = Date.now();
    const st = s.rocker.feed(readAccel(s.accel), now);
    const h = HINTS[st.level];
    s.hint.set(h[0], h[1]);
    if (st.strikes !== s.strikes) {
      s.strikes = st.strikes;
      s.buzzer.buzz(VIBRATOR_SCENE_SHORT_LIGHT);
    }
    this.renderStrikes();

    const w = Math.max(BAR.h, Math.round((BAR.w * st.progress) / ROCK.need));
    if (w !== s.barW) {
      s.barW = w;
      s.bar.setProperty(hmUI.prop.MORE, { x: px(BAR.x), y: px(BAR.y), w: px(w), h: px(BAR.h), radius: px(BAR.h / 2), color: 0x6f8cff });
    }

    // dinozaur buja się razem z ręką; śpi, gdy pasek jest w połowie
    const phase = Math.sin((now - s.t0) / 400);
    const swing = st.level === "gentle" ? Math.round(phase * PET.swing) : 0;
    const slow = Math.floor((now - s.t0) / 700) % 2;
    let frame = "idle" + slow;
    if (st.level === "hard") frame = "sad" + slow;
    else if (st.progress > ROCK.need / 2) frame = "sleep" + slow;
    else if (st.level === "gentle") frame = "happy0";
    s.pet.set(spriteSrc(s.form, frame), PET.x + swing, PET.y);

    if (st.done) {
      clearInterval(s.poll);
      s.poll = null;
      s.pet.set(spriteSrc(s.form, st.win ? "dark0" : "sad0"), PET.x, PET.y);
      s.hint.set(st.win ? "Śpi jak suseł" : "Nie chce spać", st.win ? COLOR.good : COLOR.bad);
      s.strikeText.set("");
      if (st.win) s.buzzer.buzz(VIBRATOR_SCENE_NOTIFICATION);
      finishGame(s, st.win, st.win ? "Wygrana!" : "Tym razem nie");
    }
  },
});
