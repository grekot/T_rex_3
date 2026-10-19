// Gra: przechylaj zegarek i doprowadź kulkę do zielonej mety, omijając dziury.
// Stuknięcie w ekran (albo przycisk góra/dół) ustawia aktualne trzymanie zegarka jako „poziomo”.
import * as hmUI from "@zos/ui";
import { VIBRATOR_SCENE_DURATION, VIBRATOR_SCENE_NOTIFICATION } from "@zos/sensor";
import { onKey, offKey, KEY_UP, KEY_DOWN, KEY_EVENT_CLICK, showToast } from "@zos/interaction";
import { log as Logger } from "@zos/utils";
import { buildLevel, cellAt, holeUnder, holePull, atGoal, formatClock } from "../../../utils/maze";
import { calibrate, physicsFor, tiltToAccel, collideRects, step } from "../../../utils/physics";
import { CALIB_MS, createTilt, readTilt, stopTilt, keepScreenOn, releaseScreen, createBuzzer } from "../../../utils/device";
import { loadLevel, saveLevel, recordLevel, loadFlip } from "../../../utils/store";
import {
  FLOOR_PROPS,
  wallProps,
  imageAt,
  TITLE_STYLE,
  TIME_STYLE,
  MESSAGE_STYLE,
  COLOR_TIME,
  COLOR_GREEN,
} from "zosLoader:./index.page.[pf].layout.js";

const logger = Logger.getLogger("labirynt");

const FRAME_MS = 40; // 25 klatek na sekundę
const MAX_DT = 0.06; // po przycince (np. wygaszony ekran) fizyka nie skacze
const FALL_MS = 600; // tyle kulki nie widać po wpadnięciu do dziury
const NEXT_LEVEL_MS = 1500;

// Etapy jednego poziomu
const CALIB = "calib";
const PLAY = "play";
const FALL = "fall";
const DONE = "done";

Page({
  state: {},

  onInit(params) {
    let p = {};
    try {
      p = params ? JSON.parse(params) : {};
    } catch (e) {}
    Object.assign(this.state, {
      level: typeof p.level === "number" && p.level >= 1 ? p.level : loadLevel(),
      flip: loadFlip(),
      maze: [],
      ball: null,
      lv: null,
      pos: null,
      phase: CALIB,
      phaseUntil: 0,
      samples: [],
      cal: null,
      elapsed: 0,
      lastFrame: 0,
      shownTime: "",
      shownBall: "",
      timer: null,
      tilt: null,
      buzzer: createBuzzer(),
      destroyed: false,
    });
  },

  build() {
    const s = this.state;
    try {
      keepScreenOn();
      const floor = hmUI.createWidget(hmUI.widget.CIRCLE, FLOOR_PROPS);
      this.tapToCalibrate(floor);
      s.title = hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);
      s.time = hmUI.createWidget(hmUI.widget.TEXT, TIME_STYLE);

      s.tilt = createTilt();
      if (!s.tilt.sensor) {
        hmUI.createWidget(hmUI.widget.TEXT, {
          ...MESSAGE_STYLE,
          text: "Brak dostępu do akcelerometru\n" + s.tilt.error,
        });
        return;
      }

      try {
        onKey({
          callback: (key, event) => {
            if (key !== KEY_UP && key !== KEY_DOWN) return false;
            if (event === KEY_EVENT_CLICK) this.recalibrate();
            return true;
          },
        });
      } catch (e) {}

      this.startLevel(s.level);
      s.timer = setInterval(() => this.frame(), FRAME_MS);
    } catch (e) {
      // Zamiast czarnego ekranu pokaż, co poszło nie tak
      logger.error("build failed: " + e);
      hmUI.createWidget(hmUI.widget.TEXT, { ...MESSAGE_STYLE, text: "Błąd: " + e });
    }
  },

  onDestroy() {
    const s = this.state;
    s.destroyed = true;
    if (s.timer) clearInterval(s.timer);
    stopTilt(s.tilt);
    s.buzzer.stop();
    releaseScreen();
    try {
      offKey();
    } catch (e) {}
  },

  // --- poziomy -----------------------------------------------------------------------

  startLevel(level) {
    const s = this.state;
    s.maze.forEach((w) => hmUI.deleteWidget(w));
    s.maze = [];
    if (s.ball) hmUI.deleteWidget(s.ball);

    const lv = buildLevel(level);
    const size = lv.size;
    s.level = level;
    s.lv = lv;
    s.phys = physicsFor(level);
    s.elapsed = 0;
    saveLevel(level);

    lv.walls.forEach((w) => s.maze.push(hmUI.createWidget(hmUI.widget.FILL_RECT, wallProps(w))));
    lv.holePoints.forEach((p) =>
      s.maze.push(hmUI.createWidget(hmUI.widget.IMG, imageAt(p.x, p.y, size.hole, "maze/hole_" + size.cell + ".png")))
    );
    s.maze.push(
      hmUI.createWidget(
        hmUI.widget.IMG,
        imageAt(lv.goalPoint.x, lv.goalPoint.y, size.goal, "maze/goal_" + size.cell + ".png")
      )
    );
    s.maze.forEach((w) => this.tapToCalibrate(w));
    s.ballSrc = "maze/ball_" + size.cell + ".png";
    s.ball = hmUI.createWidget(hmUI.widget.IMG, imageAt(lv.startPoint.x, lv.startPoint.y, size.ball, s.ballSrc));
    this.tapToCalibrate(s.ball);
    s.shownBall = "";

    s.title.setProperty(hmUI.prop.MORE, { ...TITLE_STYLE, text: "Poziom " + level });
    this.resetBall();
    this.beginCalibration();
  },

  resetBall() {
    const s = this.state;
    s.pos = { x: s.lv.startPoint.x, y: s.lv.startPoint.y, vx: 0, vy: 0 };
    this.drawBall();
  },

  // Stuknięcie / przycisk: nie w trakcie spadania do dziury ani po dojechaniu do mety
  recalibrate() {
    const phase = this.state.phase;
    if (phase === PLAY || phase === CALIB) this.beginCalibration();
  },

  // Przez chwilę zbieramy odczyty - tak trzymany zegarek to od teraz „poziomo”
  beginCalibration() {
    const s = this.state;
    s.phase = CALIB;
    s.phaseUntil = Date.now() + CALIB_MS;
    s.samples = [];
    if (s.pos) {
      s.pos.vx = 0;
      s.pos.vy = 0;
    }
  },

  tapToCalibrate(widget) {
    widget.addEventListener(hmUI.event.CLICK_UP, () => this.recalibrate());
  },

  // --- pętla gry ---------------------------------------------------------------------

  frame() {
    const s = this.state;
    if (s.destroyed) return;
    const now = Date.now();
    const dt = s.lastFrame ? Math.min(MAX_DT, (now - s.lastFrame) / 1000) : FRAME_MS / 1000;
    s.lastFrame = now;
    const reading = readTilt(s.tilt);

    if (s.phase === CALIB) {
      if (reading) s.samples.push({ x: reading.x, y: reading.y, z: reading.z });
      if (now >= s.phaseUntil) {
        s.cal = calibrate(s.samples);
        s.phase = PLAY;
      }
    } else if (s.phase === FALL) {
      s.elapsed += dt * 1000;
      if (now >= s.phaseUntil) {
        this.resetBall();
        s.ball.setProperty(hmUI.prop.VISIBLE, true);
        s.phase = PLAY;
      }
    } else if (s.phase === DONE) {
      if (now >= s.phaseUntil) this.startLevel(s.level + 1);
      return;
    } else if (s.phase === PLAY && reading) {
      s.elapsed += dt * 1000;
      this.move(reading, dt, now);
    }
    this.drawTime();
  },

  move(reading, dt, now) {
    const s = this.state;
    const lv = s.lv;
    const r = lv.size.ball;
    const phys = s.phys;
    const acc = tiltToAccel(reading, s.cal, s.flip, phys);
    const pull = holePull(lv, s.pos, phys.pull);
    acc.ax += pull.ax;
    acc.ay += pull.ay;
    const collide = (b) => collideRects(b, r, lv.walls, lv.index[cellAt(lv.size, b.x, b.y)], phys.restitution);
    // Uderzeń w ściany nie sygnalizujemy wibracją: na zegarku przychodziła z wyraźnym opóźnieniem
    step(s.pos, acc, dt, r, collide, phys);
    this.drawBall();

    if (holeUnder(lv, s.pos) >= 0) {
      s.phase = FALL;
      s.phaseUntil = now + FALL_MS;
      s.ball.setProperty(hmUI.prop.VISIBLE, false);
      s.buzzer.buzz(VIBRATOR_SCENE_DURATION);
    } else if (atGoal(lv, s.pos)) {
      this.finishLevel(now);
    }
  },

  finishLevel(now) {
    const s = this.state;
    s.phase = DONE;
    s.phaseUntil = now + NEXT_LEVEL_MS;
    s.pos.x = s.lv.goalPoint.x;
    s.pos.y = s.lv.goalPoint.y;
    this.drawBall();
    const isRecord = recordLevel(s.level, s.elapsed);
    saveLevel(s.level + 1);
    s.buzzer.buzz(VIBRATOR_SCENE_NOTIFICATION);
    this.drawTime();
    try {
      showToast({ content: "Poziom " + s.level + " – " + formatClock(s.elapsed) + (isRecord ? " – rekord!" : "") });
    } catch (e) {}
  },

  // --- rysowanie -----------------------------------------------------------------------

  drawBall() {
    const s = this.state;
    const r = s.lv.size.ball;
    const x = Math.round(s.pos.x);
    const y = Math.round(s.pos.y);
    const key = x + "," + y;
    if (key === s.shownBall) return;
    s.shownBall = key;
    s.ball.setProperty(hmUI.prop.MORE, imageAt(x, y, r, s.ballSrc));
  },

  // Po dojechaniu do mety czas świeci na zielono
  drawTime() {
    const s = this.state;
    const text = formatClock(s.elapsed);
    const c = s.phase === DONE ? COLOR_GREEN : COLOR_TIME;
    if (s.shownTime === text + c) return;
    s.shownTime = text + c;
    s.time.setProperty(hmUI.prop.MORE, { ...TIME_STYLE, text, color: c });
  },
});
