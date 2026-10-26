// Ekran główny: duży Groot z animacją na tle sceny z filmów (sceneOf), pierścień ikon akcji
// (dotyk albo przyciski góra/dół + zatwierdzenie), opadłe liście, mszyca przy chorobie,
// wykrzyknik, gdy czegoś potrzebuje, dymek z prośbą o zabawę i przycisk "Gra o premię" po
// nawozie/lodach, grabieniu i oprysku. W doniczce podlewanie i nawóz, potem światło gwiazd
// i lody (feedOf). Gdy nic mu nie trzeba, Groot sam się czymś zajmuje (utils/idle.js).
// Co 20-40 s Groot sam zaczepia („Jestem Groot.” + tłumaczenie Rocketa: zaproszenie do gry
// z dymkiem, dowcip, komplement, podróż Milano - utils/rocket.js), po przerwie wita.
import * as hmUI from "@zos/ui";
import { push } from "@zos/router";
import { onKey, offKey, KEY_UP, KEY_DOWN, KEY_SELECT, KEY_EVENT_CLICK } from "@zos/interaction";
import {
  STAGES,
  meal,
  snack,
  toggleLight,
  medicine,
  clean,
  scold,
  LINES,
  lineOf,
  displayName,
  canPlay,
  moodOf,
  statusText,
  needsAttention,
  lastNews,
  stageOf,
  activeRequest,
  requestText,
  setBonus,
  feedOf,
  sceneOf,
} from "../../../utils/pet";
import { ACTION_GAMES, gamePage } from "../../../utils/gamelist";
import { load, apply, rawState, tz } from "../../../utils/store";
import { openedByAlarm, scheduleReminder } from "../../../utils/reminder";
import { createBuzzer, readSteps } from "../../../utils/device";
import { addSteps } from "../../../utils/galaxy";
import { chatter, greeting, CHAT_MS, INVITE_MS } from "../../../utils/rocket";
import { tripInfo } from "../../../utils/galaxy";
import { VIBRATOR_SCENE_NOTIFICATION, VIBRATOR_SCENE_SHORT_LIGHT } from "@zos/sensor";
import { RING, DISC } from "../../../utils/geometry";
import { ACT_FORMS } from "../../../utils/art";
import { newIdle, stepIdle, idleSprite, resetIdle, SMILE_HAPPY } from "../../../utils/idle";
import { COLOR, spriteSrc, label, image, button, onTap, toast } from "../../../utils/ui";
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
  BUBBLE,
  OFFER_BTN,
} from "zosLoader:./index.page.[pf].layout.js";

const ANIM_MS = 600;
const SYNC_MS = 1000;
const ADVANCE_EVERY = 15; // co tyle synchronizacji przewijamy czas (stan zmienia się co minutę)
const MSG_MS = 2600;
const LINE_MS = { first: 1400, next: 3000 }; // „Jestem Groot.” krótko, tłumaczenie i puenta dłużej
const FIRST_CHAT_MS = 9000; // pierwsza zaczepka po otwarciu
const INVITE_BUZZ_MS = 180000; // delikatna wibracja przy zaproszeniu najwyżej co 3 min
const ANIM_LEN = 2400;
const OFFER_MS = 6000; // tyle widać przycisk "Gra o premię" po akcji

// meal i snack zależą od etapu (feedOf): podlewanie/nawóz albo światło gwiazd/lody
const ACTION_NAMES = {
  light: "Noc",
  play: "Zabawa",
  medicine: "Oprysk",
  clean: "Grabie",
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
const CHOOSE_PAGE = "page/gt/choose/index.page";

Page({
  state: {},

  build() {
    const s = this.state;
    s.sel = 0;
    s.frame = 0;
    s.anim = null;
    s.msg = null;
    s.queue = [];
    s.invite = null;
    s.nextChat = Date.now() + FIRST_CHAT_MS;
    s.lastInviteBuzz = 0;
    s.syncCount = 0;
    s.idle = newIdle();

    s.bgSrc = "ui/bg_kokpit.png";
    s.bg = image(s.bgSrc, 0, 0);
    s.title = label({ ...TITLE, color: COLOR.grey });
    s.pet = image(spriteSrc("egg", "egg0"), PET_X, PET_Y);
    onTap([s.pet.widget], () => this.tapPet());
    s.poops = POOPS.map((p) => image("ui/poop.png", p.x, p.y));
    s.alert = image("ui/alert.png", ALERT.x, ALERT.y);
    s.skull = image("ui/skull.png", SKULL.x, SKULL.y);
    s.zzz = image("ui/zzz.png", ZZZ_POS.x, ZZZ_POS.y);
    s.food = image("ui/meal.png", FOOD.x, FOOD.y);
    s.bubble = image("ui/bubble.png", BUBBLE.x, BUBBLE.y);
    onTap([s.bubble.widget], () => this.openRequest());
    s.status = label({ ...STATUS, color: COLOR.accent });
    onTap([s.status.widget], () => this.openRequest());
    s.offer = null;
    s.offerBtn = button(OFFER_BTN, () => this.takeOffer());
    s.offerShown = true;
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

    const fresh = this.reload(true);
    this.renderRing();
    if (fresh) setTimeout(() => this.newEgg(), 300); // pierwsze uruchomienie: wybór jajka
    s.buzzer = createBuzzer();
    if (openedByAlarm(Date.now())) {
      s.buzzer.buzz(VIBRATOR_SCENE_NOTIFICATION);
      const req = activeRequest(s.pet_);
      this.say(req ? requestText(req) : "Groot cię woła!");
      this.renderText();
    } else if (!fresh) this.greet();

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
    let news = r.fresh ? "Nowy patyczek!" : lastNews(r.events);
    // kroki z zegarka: energia i podróż Milano (zapis tylko, gdy przybyło kroków)
    const steps = r.fresh ? null : readSteps();
    const tr = s.pet_.trip;
    if (steps !== null && (!tr || steps !== tr.seen)) {
      const a = apply((p) => {
        const x = addSteps(p, steps, Date.now(), tz());
        return { state: x.state, msg: x.msgs.join(" ") };
      });
      s.pet_ = a.state;
      s.raw = rawState();
      if (a.msg) news = a.msg;
    }
    if (news) this.say(news);
    else if (first) s.msg = null;
    this.render();
    return r.fresh;
  },

  sync() {
    const s = this.state;
    s.syncCount++;
    if (rawState() !== s.raw || s.syncCount % ADVANCE_EVERY === 0) this.reload(false);
    this.maybeChat();
    this.renderText();
  },

  say(text) {
    this.state.queue = [];
    this.state.msg = text ? { text, until: Date.now() + MSG_MS } : null;
  },

  // Kilka dymków po kolei: „Jestem Groot.”, tłumaczenie Rocketa, puenta dowcipu
  talk(lines) {
    const s = this.state;
    if (!lines.length) return;
    s.msg = { text: lines[0], until: Date.now() + LINE_MS.first };
    s.queue = lines.slice(1);
  },

  // Powitanie, gdy dawno nikt nie zaglądał (ostatnia wizyta w stanie)
  greet() {
    const s = this.state;
    const now = Date.now();
    const gap = s.pet_.lastVisit ? now - s.pet_.lastVisit : 0;
    const r = apply((p) => ({ state: { ...p, lastVisit: now } }));
    s.pet_ = r.state;
    s.raw = rawState();
    if (!s.msg) this.talk(greeting(s.pet_, gap, tz()));
    this.renderText();
  },

  // Groot sam zaczepia co CHAT_MS: zaproszenie do gry, dowcip, komplement, podróż...
  maybeChat() {
    const s = this.state;
    const p = s.pet_;
    const now = Date.now();
    if (!p || now < s.nextChat || s.msg || s.queue.length || s.anim || s.offer) return;
    s.nextChat = now + CHAT_MS[0] + Math.random() * (CHAT_MS[1] - CHAT_MS[0]);
    if (p.gone || stageOf(p) === "egg" || p.asleep) return;
    this.chat(p);
  },

  chat(p) {
    const s = this.state;
    const now = Date.now();
    const c = chatter(p, tz(), Math.random, tripInfo(p));
    this.talk(c.lines);
    if (c.invite) {
      s.invite = { game: c.invite, until: now + INVITE_MS };
      if (now - s.lastInviteBuzz >= INVITE_BUZZ_MS) {
        s.lastInviteBuzz = now;
        s.buzzer.buzz(VIBRATOR_SCENE_SHORT_LIGHT);
      }
    }
    this.renderPet();
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
    s.offer = ACTION_GAMES[id] && r.anim !== "no" ? { action: id, until: Date.now() + OFFER_MS } : null;
    const feed = feedOf(r.state);
    s.anim = r.anim ? { kind: r.anim, until: Date.now() + ANIM_LEN, food: id === "snack" ? feed.snackIcon : feed.mealIcon } : null;
    s.frame = 0;
    this.render();
  },

  // Dymek albo napis prośby (albo zaproszenia z zaczepki): od razu do tej gry
  openRequest() {
    const s = this.state;
    const p = load().state;
    const req = activeRequest(p);
    const inv = s.invite && Date.now() < s.invite.until ? s.invite.game : null;
    const game = req ? req.game : inv;
    if (!game) return;
    s.invite = null;
    const why = canPlay(p, game);
    if (why) toast(why);
    else push({ url: gamePage(game) });
  },

  // Gra o premię po akcji: zapamiętuje premię w stanie i otwiera grę
  takeOffer() {
    const s = this.state;
    if (!s.offer || Date.now() > s.offer.until) return;
    const action = s.offer.action;
    s.offer = null;
    const r = apply((p) => ({ state: setBonus(p, action, Date.now()) }));
    s.pet_ = r.state;
    s.raw = rawState();
    const game = ACTION_GAMES[action].game;
    const why = canPlay(r.state, game);
    if (why) toast(why);
    else push({ url: gamePage(game) });
    this.renderText();
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
    // „Jestem Groot.”, a po chwili tłumaczenie Rocketa - jak zaczepka (dowcip, zaproszenie...)
    this.chat(p);
    s.nextChat = Date.now() + CHAT_MS[1];
    this.renderText();
  },

  // Wybór jajka i imienia na osobnej stronie; po powrocie stan wczyta sync()
  newEgg() {
    push({ url: CHOOSE_PAGE, params: "egg" });
  },

  render() {
    this.renderPet();
    this.renderText();
  },

  // Ikona akcji w pierścieniu: karmienie zależy od etapu (konewka/worek albo słońce/lody)
  ringIcon(id) {
    const p = this.state.pet_;
    if (p && (id === "meal" || id === "snack")) return feedOf(p)[id + "Icon"];
    return id;
  },

  actionName(id) {
    const p = this.state.pet_;
    return ACTION_NAMES[id] || (p ? feedOf(p)[id] : "");
  },

  renderRing() {
    const s = this.state;
    s.ring.forEach((w, i) => w.set("ring/" + this.ringIcon(RING[i].id) + (i === s.sel ? "_sel" : "") + ".png"));
    this.renderText();
  },

  renderText() {
    const s = this.state;
    const p = s.pet_;
    if (!p) return;
    const now = Date.now();
    if (s.msg && now > s.msg.until) {
      s.msg = s.queue.length ? { text: s.queue.shift(), until: now + LINE_MS.next } : null;
    }
    if (s.invite && now >= s.invite.until) s.invite = null;
    // na dole między ikonami mieści się tylko imię (wiek i pokolenie są w statystykach)
    let title = "";
    if (!p.gone) title = stageOf(p) === "egg" ? p.name || "Patyczek" : displayName(p);
    s.title.set(title);
    const status = s.msg ? s.msg.text : statusText(p, tz());
    s.status.set(status, s.msg ? COLOR.text : COLOR.accent);
    s.action.set(p.gone ? "Stuknij: nowy" : this.actionName(RING[s.sel].id), p.gone ? COLOR.accent : COLOR.text);
    const offer = !!(s.offer && now < s.offer.until && !p.gone);
    if (!offer) s.offer = null;
    if (offer !== s.offerShown) {
      s.offerShown = offer;
      s.offerBtn.bg.setProperty(hmUI.prop.VISIBLE, offer);
      s.offerBtn.txt.widget.setProperty(hmUI.prop.VISIBLE, offer);
      s.action.show(!offer); // przycisk premii stoi w miejscu nazwy akcji
    }
  },

  renderPet() {
    const s = this.state;
    const p = s.pet_;
    if (!p) return;
    const now = Date.now();
    if (s.anim && now > s.anim.until) s.anim = null;
    const tick = s.frame % 2;
    const dark = p.asleep && !p.light;
    const bg = "ui/bg_" + sceneOf(p) + (dark ? "_n" : "") + ".png";
    if (bg !== s.bgSrc) {
      s.bgSrc = bg;
      s.bg.set(bg, 0, 0);
    }
    // etap się zmienił (wyszedł z doniczki): inne ikony karmienia
    const feedKind = feedOf(p).mealIcon;
    if (feedKind !== s.feedKind) {
      s.feedKind = feedKind;
      this.renderRing();
    }

    const eggDir = LINES[lineOf(p)].egg;
    const tickedNow = s.lastFrame !== s.frame; // renderPet woła też odświeżanie po akcji
    s.lastFrame = s.frame;
    let src;
    let dx = 0;
    let dy = 0;
    let idling = false;
    if (p.gone) {
      src = p.gone === "old" ? spriteSrc(eggDir, tick ? "egg1" : "egg0") : "ui/forest.png";
    } else if (stageOf(p) === "egg") {
      const hatching = now - p.stageAt > STAGES.egg.len - 60000;
      src = spriteSrc(eggDir, hatching ? (tick ? "egg2" : "egg1") : Math.floor(s.frame / 2) % 2 ? "egg1" : "egg0");
    } else if (s.anim) {
      src = spriteSrc(p.form, ANIM_FRAMES[s.anim.kind][tick]);
    } else {
      const mood = moodOf(p);
      const slow = Math.floor(s.frame / 2) % 2; // oddech wolniej niż animacje
      if (mood === "sleep") src = spriteSrc(p.form, (dark ? "dark" : "sleep") + slow);
      else if (mood === "sad") src = spriteSrc(p.form, "sad" + slow);
      else if (!needsAttention(p)) {
        // nic mu nie trzeba: sam się czymś zajmuje
        idling = true;
        if (tickedNow) stepIdle(s.idle, ACT_FORMS.indexOf(p.form) >= 0, Math.random);
        const f = idleSprite(s.idle, s.frame, p.happy >= SMILE_HAPPY);
        src = spriteSrc(p.form, f.frame);
        dx = f.dx;
        dy = f.dy;
      } else src = spriteSrc(p.form, "idle" + slow);
    }
    // jedzenie, smutek, sen, prośby: od razu z powrotem na środek
    if (!idling && (s.idle.x || s.idle.kind !== "stand")) resetIdle(s.idle);
    s.pet.set(src, PET_X + dx, PET_Y + dy);

    const alive = !p.gone && stageOf(p) !== "egg";
    s.poops.forEach((w, i) => w.show(alive && i < p.poops));
    s.skull.show(alive && p.sick > 0);
    s.alert.show(alive && needsAttention(p) && !s.anim && tick === 0);
    s.zzz.show(alive && p.asleep);
    s.bubble.show(alive && (!!activeRequest(p) || !!(s.invite && Date.now() < s.invite.until)));
    const eating = !!(s.anim && s.anim.kind === "eat");
    if (eating) s.food.set("ui/" + s.anim.food + ".png");
    s.food.show(eating && tick === 0);
  },
});
