// Plansza Sapera: stuknięcie odkrywa pole (albo stawia flagę w trybie flagi),
// przytrzymanie zawsze stawia/zdejmuje flagę, stuknięcie w cyfrę odkrywa resztę sąsiadów.
import * as hmUI from "@zos/ui";
import {
  Vibrator,
  VIBRATOR_SCENE_SHORT_MIDDLE,
  VIBRATOR_SCENE_DURATION,
  VIBRATOR_SCENE_NOTIFICATION,
} from "@zos/sensor";
import { onKey, offKey, KEY_UP, KEY_DOWN, KEY_EVENT_CLICK, showToast } from "@zos/interaction";
import { setWakeUpRelaunch, setPageBrightTime } from "@zos/display";
import { log as Logger } from "@zos/utils";
import { UI } from "../../../utils/geometry";
import {
  HIDDEN,
  OPEN,
  READY,
  PLAYING,
  WON,
  LOST,
  levelOf,
  isActive,
  isOver,
  newGame,
  reveal,
  toggleFlag,
  chord,
  tileName,
  minesLeft,
  recordWin,
  formatClock,
  formatSeconds,
} from "../../../utils/mines";
import { loadGame, saveGame, clearGame, loadStats, saveStats } from "../../../utils/store";
import {
  scaled,
  cellRect,
  COUNTER_STYLE,
  ERROR_STYLE,
  COLOR_TEXT,
  COLOR_WIN,
  COLOR_LOST,
} from "zosLoader:./index.page.[pf].layout.js";

const logger = Logger.getLogger("saper");

const LONG_PRESS_MS = 400; // tyle trzeba przytrzymać pole, żeby postawić flagę
const MOVE_CANCEL_PX = 24; // przesunięcie palca, które anuluje stuknięcie
const RESTART_CONFIRM_MS = 3000; // drugie stuknięcie w buźkę w tym czasie = nowa gra
const BRIGHT_MS = 30000; // ekran gaśnie dopiero po 30 s bez ruchu

const MODE_DIG = "dig";
const MODE_FLAG = "flag";

Page({
  state: {},

  onInit(params) {
    let p = {};
    try {
      p = params ? JSON.parse(params) : {};
    } catch (e) {}
    const saved = p.resume ? loadGame() : null;
    Object.assign(this.state, {
      game: saved && !isOver(saved) ? saved : newGame(p.level),
      mode: MODE_DIG,
      since: 0, // kiedy ruszył zegar bieżącego odcinka gry (0 = stoi)
      press: null,
      restartAsked: 0,
      destroyed: false,
      tiles: [],
      shown: [],
      timer: null,
      vibrator: null,
      faceShown: "",
      timeShown: "",
    });
  },

  build() {
    try {
      this.buildScreen();
    } catch (e) {
      // Zamiast czarnego ekranu pokaż, co poszło nie tak
      logger.error("build failed: " + e);
      hmUI.createWidget(hmUI.widget.TEXT, { ...ERROR_STYLE, text: "Błąd: " + e });
    }
  },

  onDestroy() {
    const s = this.state;
    s.destroyed = true;
    this.persist();
    if (s.timer) clearInterval(s.timer);
    this.cancelPress();
    try {
      offKey();
    } catch (e) {}
    try {
      if (s.vibrator) s.vibrator.stop();
    } catch (e) {}
  },

  buildScreen() {
    const s = this.state;
    const level = levelOf(s.game);

    try {
      setWakeUpRelaunch({ relaunch: true });
      setPageBrightTime({ brightTime: BRIGHT_MS });
    } catch (e) {}

    for (let i = 0; i < level.cols * level.rows; i++) {
      s.shown.push("");
      if (!isActive(level, i)) {
        s.tiles.push(null);
        continue;
      }
      const tile = hmUI.createWidget(hmUI.widget.IMG, {
        ...cellRect(level, i),
        src: "tiles/" + level.cell + "/hidden.png",
      });
      tile.addEventListener(hmUI.event.CLICK_DOWN, (e) => this.onDown(i, e));
      tile.addEventListener(hmUI.event.MOVE, (e) => this.onMove(e));
      tile.addEventListener(hmUI.event.CLICK_UP, () => this.onUp(i));
      s.tiles.push(tile);
    }

    s.face = hmUI.createWidget(hmUI.widget.IMG, { ...scaled(UI.smiley), src: "ui/face_smile.png" });
    s.face.addEventListener(hmUI.event.CLICK_UP, () => this.onFace());

    hmUI.createWidget(hmUI.widget.IMG, { ...scaled(UI.mineIcon), src: "ui/icon_mine.png" });
    s.minesText = hmUI.createWidget(hmUI.widget.TEXT, { ...COUNTER_STYLE, ...scaled(UI.mineText) });
    hmUI.createWidget(hmUI.widget.IMG, { ...scaled(UI.clockIcon), src: "ui/icon_clock.png" });
    s.timeText = hmUI.createWidget(hmUI.widget.TEXT, { ...COUNTER_STYLE, ...scaled(UI.timeText) });

    s.modeBtn = hmUI.createWidget(hmUI.widget.IMG, { ...scaled(UI.mode), src: "ui/mode_dig.png" });
    s.modeBtn.addEventListener(hmUI.event.CLICK_UP, () => this.onModeButton());

    // Przyciski góra/dół zegarka też przełączają łopatę i flagę
    try {
      onKey({
        callback: (key, event) => {
          if (key !== KEY_UP && key !== KEY_DOWN) return false;
          if (event === KEY_EVENT_CLICK && !isOver(s.game)) this.toggleMode();
          return true;
        },
      });
    } catch (e) {
      logger.debug("onKey niedostępne: " + e);
    }

    // Przerwana partia liczy czas dalej od chwili powrotu
    if (s.game.status === PLAYING) s.since = Date.now();
    this.renderBoard();
    this.refreshStatus();
    s.timer = setInterval(() => this.refreshTime(), 1000);
  },

  // --- dotyk -------------------------------------------------------------------

  onDown(i, e) {
    const s = this.state;
    if (isOver(s.game)) return;
    this.cancelPress();
    const press = { i, x: e && typeof e.x === "number" ? e.x : null, y: e ? e.y : null, fired: false, moved: false, timer: null };
    press.timer = setTimeout(() => {
      press.timer = null;
      if (s.destroyed || s.press !== press || press.moved) return;
      press.fired = true;
      this.longPress(i);
    }, LONG_PRESS_MS);
    s.press = press;
    this.setFace("wow");
  },

  onMove(e) {
    const p = this.state.press;
    if (!p || p.moved || p.x === null || !e || typeof e.x !== "number") return;
    const dx = e.x - p.x;
    const dy = e.y - p.y;
    if (dx * dx + dy * dy > MOVE_CANCEL_PX * MOVE_CANCEL_PX) {
      p.moved = true;
      this.cancelPress();
      this.refreshFace();
    }
  },

  onUp(i) {
    const s = this.state;
    const p = s.press;
    this.cancelPress();
    s.press = null;
    this.refreshFace();
    // palec zjechał na inne pole albo przytrzymanie już postawiło flagę
    if (!p || p.fired || p.moved || p.i !== i) return;
    this.tap(i);
  },

  cancelPress() {
    const p = this.state.press;
    if (p && p.timer) {
      clearTimeout(p.timer);
      p.timer = null;
    }
  },

  tap(i) {
    const s = this.state;
    const g = s.game;
    const v = g.view[i];
    if (v === OPEN) this.apply(() => chord(g, i));
    else if (s.mode === MODE_FLAG) this.apply(() => toggleFlag(g, i), true);
    else if (v === HIDDEN) this.apply(() => reveal(g, i));
    // flaga w trybie łopaty jest chroniona przed przypadkowym odkryciem
  },

  longPress(i) {
    const g = this.state.game;
    if (g.view[i] === OPEN) this.apply(() => chord(g, i));
    else this.apply(() => toggleFlag(g, i), true);
  },

  apply(move, buzz) {
    const s = this.state;
    const g = s.game;
    const before = g.status;
    const changed = move();
    if (!changed.length) return;
    if (before === READY && g.status !== READY) s.since = Date.now(); // pierwszy ruch uruchamia zegar
    if (isOver(g)) this.finish();
    else if (buzz) this.vibrate(VIBRATOR_SCENE_SHORT_MIDDLE);
    this.renderBoard();
    this.refreshStatus();
    this.persist();
  },

  finish() {
    const s = this.state;
    const g = s.game;
    g.elapsed = this.elapsed();
    s.since = 0;
    if (g.status === WON) {
      const stats = loadStats();
      const isRecord = recordWin(stats, g.level, g.elapsed);
      saveStats(stats);
      this.vibrate(VIBRATOR_SCENE_NOTIFICATION);
      this.toast((isRecord ? "Nowy rekord! " : "Wygrana! ") + formatClock(g.elapsed));
    } else {
      this.vibrate(VIBRATOR_SCENE_DURATION);
    }
  },

  // --- przyciski ---------------------------------------------------------------

  onFace() {
    const s = this.state;
    // trwającą partię łatwo przerwać przypadkiem - wymagamy drugiego stuknięcia
    if (s.game.status === PLAYING && Date.now() - s.restartAsked > RESTART_CONFIRM_MS) {
      s.restartAsked = Date.now();
      this.toast("Stuknij jeszcze raz: nowa gra");
      return;
    }
    this.restart();
  },

  onModeButton() {
    if (isOver(this.state.game)) this.restart();
    else this.toggleMode();
  },

  toggleMode() {
    const s = this.state;
    s.mode = s.mode === MODE_DIG ? MODE_FLAG : MODE_DIG;
    this.refreshStatus();
  },

  restart() {
    const s = this.state;
    s.game = newGame(s.game.level);
    s.mode = MODE_DIG;
    s.since = 0;
    s.restartAsked = 0;
    clearGame();
    this.renderBoard();
    this.refreshStatus();
  },

  // --- rysowanie ---------------------------------------------------------------

  renderBoard() {
    const s = this.state;
    const cell = levelOf(s.game).cell;
    for (let i = 0; i < s.tiles.length; i++) {
      if (!s.tiles[i]) continue;
      const name = tileName(s.game, i);
      if (s.shown[i] === name) continue;
      s.shown[i] = name;
      s.tiles[i].setProperty(hmUI.prop.SRC, "tiles/" + cell + "/" + name + ".png");
    }
  },

  refreshStatus() {
    const s = this.state;
    const g = s.game;
    this.refreshFace();
    s.minesText.setProperty(hmUI.prop.MORE, {
      ...COUNTER_STYLE,
      ...scaled(UI.mineText),
      text: String(minesLeft(g)),
      color: g.status === LOST ? COLOR_LOST : COLOR_TEXT,
    });
    const src = isOver(g) ? "ui/restart.png" : s.mode === MODE_FLAG ? "ui/mode_flag.png" : "ui/mode_dig.png";
    s.modeBtn.setProperty(hmUI.prop.SRC, src);
    this.refreshTime();
  },

  refreshTime() {
    const s = this.state;
    if (s.destroyed) return;
    const g = s.game;
    const text = formatSeconds(this.elapsed());
    const color = g.status === WON ? COLOR_WIN : COLOR_TEXT;
    if (s.timeShown === text + color) return;
    s.timeShown = text + color;
    s.timeText.setProperty(hmUI.prop.MORE, { ...COUNTER_STYLE, ...scaled(UI.timeText), text, color });
  },

  refreshFace() {
    const g = this.state.game;
    this.setFace(g.status === WON ? "cool" : g.status === LOST ? "dead" : "smile");
  },

  setFace(face) {
    const s = this.state;
    if (s.faceShown === face) return;
    s.faceShown = face;
    s.face.setProperty(hmUI.prop.SRC, "ui/face_" + face + ".png");
  },

  // --- czas, zapis, wibracje ------------------------------------------------------

  elapsed() {
    const s = this.state;
    return s.game.elapsed + (s.since ? Date.now() - s.since : 0);
  },

  // Zapisuje tylko trwającą partię - zakończona albo nierozpoczęta nie ma czego wznawiać
  persist() {
    const g = this.state.game;
    if (g.status === PLAYING) saveGame({ ...g, elapsed: this.elapsed() });
    else if (g.status === WON || g.status === LOST) clearGame();
  },

  toast(content) {
    try {
      showToast({ content });
    } catch (e) {}
  },

  // Wibracja jest dodatkiem - każdy błąd jest ignorowany, żeby nie zepsuć gry
  vibrate(scene) {
    const s = this.state;
    try {
      if (!s.vibrator) s.vibrator = new Vibrator();
      s.vibrator.stop();
      s.vibrator.setMode(scene);
      s.vibrator.start();
    } catch (e) {
      logger.debug("wibracje niedostępne: " + e);
    }
  },
});
