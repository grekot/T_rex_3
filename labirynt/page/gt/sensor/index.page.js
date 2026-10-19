// Test czujnika: kulka toczy się swobodnie w kole, u góry surowe odczyty akcelerometru.
// Jeśli kulka ucieka w złą stronę, przyciski na dole odwracają osie (zapis działa też w grze).
import * as hmUI from "@zos/ui";
import { calibrate, tiltToAccel, collideCircle, step } from "../../../utils/physics";
import { CALIB_MS, createTilt, readTilt, stopTilt, keepScreenOn, releaseScreen } from "../../../utils/device";
import { loadFlip, saveFlip } from "../../../utils/store";
import {
  ARENA,
  ARENA_PROPS,
  imageAt,
  TITLE_STYLE,
  RAW_STYLE,
  buttonBg,
  buttonText,
} from "zosLoader:./index.page.[pf].layout.js";

const FRAME_MS = 40;
const MAX_DT = 0.06;
const BALL_R = 22; // ui/ball_arena.png
const RAW_EVERY = 6; // odczyty na górze odświeżamy co tyle klatek, żeby dało się je przeczytać
const AXES = [
  { key: "x", label: "lewo–prawo" },
  { key: "y", label: "góra–dół" },
];

Page({
  state: {},

  onInit() {
    Object.assign(this.state, {
      flip: loadFlip(),
      tilt: null,
      cal: null,
      calibrating: false,
      calibUntil: 0,
      samples: [],
      pos: { x: ARENA.cx, y: ARENA.cy, vx: 0, vy: 0 },
      lastFrame: 0,
      frames: 0,
      timer: null,
      buttons: [],
      destroyed: false,
    });
  },

  build() {
    const s = this.state;
    keepScreenOn();
    hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);
    s.raw = hmUI.createWidget(hmUI.widget.TEXT, RAW_STYLE);
    const arena = hmUI.createWidget(hmUI.widget.CIRCLE, ARENA_PROPS);
    s.ball = hmUI.createWidget(hmUI.widget.IMG, imageAt(s.pos.x, s.pos.y, BALL_R, "ui/ball_arena.png"));
    [arena, s.ball].forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, () => this.beginCalibration()));

    AXES.forEach((axis, k) => {
      const on = s.flip[axis.key];
      const bg = hmUI.createWidget(hmUI.widget.FILL_RECT, buttonBg(k, on));
      const text = hmUI.createWidget(hmUI.widget.TEXT, buttonText(k, axis.label, on));
      [bg, text].forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, () => this.toggleAxis(k)));
      s.buttons.push({ bg, text });
    });

    s.tilt = createTilt();
    if (!s.tilt.sensor) {
      s.raw.setProperty(hmUI.prop.MORE, { ...RAW_STYLE, text: "brak akcelerometru: " + s.tilt.error, color: 0xff3d00 });
      return;
    }
    this.beginCalibration();
    s.timer = setInterval(() => this.frame(), FRAME_MS);
  },

  onDestroy() {
    const s = this.state;
    s.destroyed = true;
    if (s.timer) clearInterval(s.timer);
    stopTilt(s.tilt);
    releaseScreen();
  },

  beginCalibration() {
    const s = this.state;
    s.calibrating = true;
    s.calibUntil = Date.now() + CALIB_MS;
    s.samples = [];
    s.pos.vx = 0;
    s.pos.vy = 0;
  },

  toggleAxis(k) {
    const s = this.state;
    const key = AXES[k].key;
    s.flip[key] = !s.flip[key];
    saveFlip(s.flip);
    const on = s.flip[key];
    s.buttons[k].bg.setProperty(hmUI.prop.MORE, buttonBg(k, on));
    s.buttons[k].text.setProperty(hmUI.prop.MORE, buttonText(k, AXES[k].label, on));
  },

  frame() {
    const s = this.state;
    if (s.destroyed) return;
    const now = Date.now();
    const dt = s.lastFrame ? Math.min(MAX_DT, (now - s.lastFrame) / 1000) : FRAME_MS / 1000;
    s.lastFrame = now;
    const reading = readTilt(s.tilt);
    if (!reading) return;

    if (s.frames++ % RAW_EVERY === 0) {
      const text = "x " + Math.round(reading.x) + "   y " + Math.round(reading.y) + "   z " + Math.round(reading.z);
      s.raw.setProperty(hmUI.prop.MORE, { ...RAW_STYLE, text });
    }

    if (s.calibrating) {
      s.samples.push({ x: reading.x, y: reading.y, z: reading.z });
      if (now >= s.calibUntil) {
        s.cal = calibrate(s.samples);
        s.calibrating = false;
      }
      return;
    }
    const acc = tiltToAccel(reading, s.cal, s.flip);
    step(s.pos, acc, dt, BALL_R, (b) => collideCircle(b, BALL_R, ARENA.cx, ARENA.cy, ARENA.r));
    s.ball.setProperty(hmUI.prop.MORE, imageAt(Math.round(s.pos.x), Math.round(s.pos.y), BALL_R, "ui/ball_arena.png"));
  },
});
