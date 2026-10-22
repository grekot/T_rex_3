// Ekran główny: dinozaur z animacją, pierścień ikon akcji (dotyk albo przyciski
// góra/dół + zatwierdzenie), kupy, czaszka przy chorobie, wykrzyknik, gdy czegoś potrzebuje.
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { push } from "@zos/router";
import { onKey, offKey, KEY_UP, KEY_DOWN, KEY_SELECT, KEY_EVENT_CLICK } from "@zos/interaction";
import {
  FORMS,
  STAGES,
  meal,
  snack,
  toggleLight,
  medicine,
  clean,
  scold,
  restart,
  canPlay,
  moodOf,
  statusText,
  needsAttention,
  lastNews,
  ageDays,
  stageOf,
} from "../../../utils/pet";
import { load, apply, save, rawState, tz, newSeed } from "../../../utils/store";
import { openedByAlarm, scheduleReminder } from "../../../utils/reminder";
import { createBuzzer } from "../../../utils/device";
import { VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { RING, DISC } from "../../../utils/geometry";
import { COLOR, spriteSrc, label, image, rect, onTap, toast, daysText } from "../../../utils/ui";
import {
  PET_X,
  PET_Y,
  TITLE,
  STATUS,
  ACTION,
  POOPS,
  ALERT,
  SKULL,
  ZZZ_POS,
  FOOD,
} from "zosLoader:./index.page.[pf].layout.js";

const ANIM_MS = 600;
const SYNC_MS = 1000;
const ADVANCE_EVERY = 15; // co tyle synchronizacji przewijamy czas (stan zmienia się co minutę)
const MSG_MS = 2600;
const ANIM_LEN = 2400;

const ACTION_NAMES = {
  meal: "Jedzenie",
  snack: "Przekąska",
  light: "Światło",
  play: "Zabawa",
  medicine: "Lekarstwo",
  clean: "Sprzątanie",
  scold: "Zgań",
  stats: "Statystyki",
};

const ANIM_FRAMES = {
  eat: ["eat0", "eat1"],
  happy: ["happy0", "happy1"],
  sad: ["sad0", "sad1"],
  no: ["left", "idle0"],
};

const GAMES_PAGE = "page/gt/games/index.page";
const STATS_PAGE = "page/gt/stats/index.page";

Page({
  state: {},

  build() {
    const s = this.state;
    s.sel = 0;
    s.frame = 0;
    s.anim = null;
    s.msg = null;
    s.syncCount = 0;

    s.bg = rect(0, 0, 480, 480, 0x000000);
    s.bgColor = 0x000000;
    s.title = label({ ...TITLE, color: COLOR.grey });
    s.pet = image(spriteSrc("egg", "egg0"), PET_X, PET_Y);
    onTap([s.pet.widget], () => this.tapPet());
    s.poops = POOPS.map((p) => image("ui/poop.png", p.x, p.y));
    s.alert = image("ui/alert.png", ALERT.x, ALERT.y);
    s.skull = image("ui/skull.png", SKULL.x, SKULL.y);
    s.zzz = image("ui/zzz.png", ZZZ_POS.x, ZZZ_POS.y);
    s.food = image("ui/meal.png", FOOD.x, FOOD.y);
    s.status = label({ ...STATUS, color: COLOR.accent });
    s.action = label({ ...ACTION });
    s.ring = RING.map((r, i) => {
      const w = image("ring/" + r.id + ".png", r.cx - DISC / 2, r.cy - DISC / 2);
      onTap([w.widget], () => {
        s.sel = i;
        this.renderRing();
        this.run(r.id);
      });
      return w;
    });

    this.reload(true);
    this.renderRing();
    s.buzzer = createBuzzer();
    if (openedByAlarm(Date.now())) {
      s.buzzer.buzz(VIBRATOR_SCENE_NOTIFICATION);
      this.say("Pupil cię woła!");
      this.renderText();
    }

    s.animTimer = setInterval(() => {
      s.frame++;
      this.renderPet();
    }, ANIM_MS);
    s.syncTimer = setInterval(() => this.sync(), SYNC_MS);

    try {
      onKey({
        callback: (key, event) => {
          if (key === KEY_UP || key === KEY_DOWN) {
            if (event === KEY_EVENT_CLICK) this.move(key === KEY_UP ? -1 : 1);
            return true;
          }
          if (key === KEY_SELECT) {
            if (event === KEY_EVENT_CLICK) this.run(RING[s.sel].id);
            return true;
          }
          return false;
        },
      });
      s.keyHooked = true;
    } catch (e) {}
  },

  onDestroy() {
    const s = this.state;
    if (s.animTimer) clearInterval(s.animTimer);
    if (s.syncTimer) clearInterval(s.syncTimer);
    if (s.keyHooked) {
      try {
        offKey();
      } catch (e) {}
    }
    s.buzzer.stop();
    try {
      scheduleReminder(load().state, Date.now(), tz());
    } catch (e) {}
  },

  // Wczytuje stan z pamięci i przewija czas do teraz
  reload(first) {
    const s = this.state;
    const r = load();
    s.pet_ = r.state;
    s.raw = rawState();
    const news = r.fresh ? "Nowe jajo!" : lastNews(r.events);
    if (news) this.say(news);
    else if (first) s.msg = null;
    this.render();
  },

  sync() {
    const s = this.state;
    s.syncCount++;
    if (rawState() !== s.raw || s.syncCount % ADVANCE_EVERY === 0) this.reload(false);
    else this.renderText();
  },

  say(text) {
    this.state.msg = text ? { text, until: Date.now() + MSG_MS } : null;
  },

  move(d) {
    const s = this.state;
    s.sel = (s.sel + d + RING.length) % RING.length;
    this.renderRing();
  },

  run(id) {
    const s = this.state;
    if (s.pet_.gone) {
      this.newEgg();
      return;
    }
    let r = null;
    switch (id) {
      case "meal":
        r = apply(meal);
        break;
      case "snack":
        r = apply(snack);
        break;
      case "light":
        r = apply((p) => toggleLight(p, tz()));
        break;
      case "medicine":
        r = apply(medicine);
        break;
      case "clean":
        r = apply(clean);
        break;
      case "scold":
        r = apply(scold);
        break;
      case "play": {
        const why = canPlay(load().state);
        if (why) toast(why);
        else push({ url: GAMES_PAGE });
        return;
      }
      case "stats":
        push({ url: STATS_PAGE });
        return;
    }
    if (!r) return;
    s.pet_ = r.state;
    s.raw = rawState();
    this.say(r.msg);
    s.anim = r.anim ? { kind: r.anim, until: Date.now() + ANIM_LEN, food: id === "snack" ? "snack" : "meal" } : null;
    s.frame = 0;
    this.render();
  },

  tapPet() {
    const s = this.state;
    const p = s.pet_;
    if (p.gone) {
      this.newEgg();
      return;
    }
    if (stageOf(p) === "egg" || p.asleep) return;
    s.anim = { kind: moodOf(p) === "sad" ? "sad" : "happy", until: Date.now() + 1200 };
    s.frame = 0;
    this.renderPet();
  },

  newEgg() {
    const s = this.state;
    const egg = restart(s.pet_, Date.now(), newSeed());
    s.raw = save(egg);
    s.pet_ = egg;
    s.anim = null;
    this.say("Nowe jajo!");
    this.render();
  },

  render() {
    this.renderPet();
    this.renderText();
  },

  renderRing() {
    const s = this.state;
    s.ring.forEach((w, i) => w.set("ring/" + RING[i].id + (i === s.sel ? "_sel" : "") + ".png"));
    this.renderText();
  },

  renderText() {
    const s = this.state;
    const p = s.pet_;
    if (!p) return;
    const now = Date.now();
    if (s.msg && now > s.msg.until) s.msg = null;
    let title = "";
    if (!p.gone) {
      const stage = stageOf(p);
      title = stage === "egg" ? "Jajo · pokolenie " + p.gen : FORMS[p.form].name + " · " + daysText(ageDays(p));
    }
    s.title.set(title);
    const status = s.msg ? s.msg.text : statusText(p, tz());
    s.status.set(status, s.msg ? COLOR.text : COLOR.accent);
    s.action.set(p.gone ? "Stuknij: nowe jajo" : ACTION_NAMES[RING[s.sel].id], p.gone ? COLOR.accent : COLOR.text);
  },

  renderPet() {
    const s = this.state;
    const p = s.pet_;
    if (!p) return;
    const now = Date.now();
    if (s.anim && now > s.anim.until) s.anim = null;
    const tick = s.frame % 2;
    const dark = p.asleep && !p.light;
    const bg = dark ? COLOR.night : 0x000000;
    if (bg !== s.bgColor) {
      s.bgColor = bg;
      s.bg.setProperty(hmUI.prop.MORE, { x: 0, y: 0, w: px(480), h: px(480), color: bg });
    }

    let src;
    if (p.gone) {
      src = p.gone === "old" ? spriteSrc("egg", tick ? "egg1" : "egg0") : "ui/forest.png";
    } else if (stageOf(p) === "egg") {
      const hatching = now - p.stageAt > STAGES.egg.len - 60000;
      src = spriteSrc("egg", hatching ? (tick ? "egg2" : "egg1") : Math.floor(s.frame / 2) % 2 ? "egg1" : "egg0");
    } else if (s.anim) {
      src = spriteSrc(p.form, ANIM_FRAMES[s.anim.kind][tick]);
    } else {
      const mood = moodOf(p);
      const slow = Math.floor(s.frame / 2) % 2; // oddech wolniej niż animacje
      if (mood === "sleep") src = spriteSrc(p.form, (dark ? "dark" : "sleep") + slow);
      else if (mood === "sad") src = spriteSrc(p.form, "sad" + slow);
      else src = spriteSrc(p.form, "idle" + slow);
    }
    s.pet.set(src);

    const alive = !p.gone && stageOf(p) !== "egg";
    s.poops.forEach((w, i) => w.show(alive && i < p.poops));
    s.skull.show(alive && p.sick > 0);
    s.alert.show(alive && needsAttention(p) && !s.anim && tick === 0);
    s.zzz.show(alive && p.asleep);
    const eating = !!(s.anim && s.anim.kind === "eat");
    if (eating) s.food.set("ui/" + s.anim.food + ".png");
    s.food.show(eating && tick === 0);
  },
});
