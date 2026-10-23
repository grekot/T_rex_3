// Wspólny szkielet stron minigier: nagłówek, akcelerometr z pętlą co 40 ms, opcjonalna
// kalibracja ("trzymaj poziomo"), ekran włączony w trakcie gry, sprzątanie przy wyjściu.
import { calibrate, sideTilt } from "./games.js";
import { vertTilt } from "./moves.js";
import { startAccel, readAccel, stopAccel, keepScreenOn, releaseScreen, createBuzzer } from "./device.js";
import { COLOR, label } from "./ui.js";
import { load } from "./store.js";

export const POLL_MS = 40;
const CALIB_MS = 600;
// Wibracja zegarka trzęsie akcelerometrem - po buzz() gra dostaje ostatni spokojny odczyt,
// dopóki odczyty się nie uspokoją (co najmniej MIN, najwyżej MAX ms)
export const VIBRATION_HOLD = { min: 150, max: 800, calm: 150 };

export const HEAD = { x: 70, y: 28, w: 340, h: 44, size: 30 };
export const HINT = { x: 60, y: 72, w: 360, h: 34, size: 22 };
export const STATUS = { x: 70, y: 330, w: 340, h: 40, size: 26 };

export function header(title, hint) {
  label({ ...HEAD, text: title });
  return label({ ...HINT, text: hint || "", color: COLOR.grey });
}

export function petForm() {
  try {
    return load().state.form;
  } catch (e) {
    return "pisklak";
  }
}

// opts: { calibrate: bool, tick(a, now, dt, tilt), ready() } - tilt = { x, y } w g po kalibracji
export function startMotion(st, opts) {
  keepScreenOn();
  st.buzzer = createBuzzer();
  st.accel = startAccel();
  st.motionOk = !!st.accel.sensor;
  const samples = [];
  const t0 = Date.now();
  let last = t0;
  st.zero = opts.calibrate ? null : { x: 0, y: 0, z: 980, zSign: 1 };
  st.vibFrom = 0;
  st.vibCalm = 0;
  st.lastCalm = null;
  st.poll = setInterval(() => {
    const now = Date.now();
    let a = readAccel(st.accel);
    if (st.vibFrom) {
      const dev = a ? Math.abs(Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) - 980) : 0;
      st.vibCalm = dev < VIBRATION_HOLD.calm ? st.vibCalm + 1 : 0;
      const since = now - st.vibFrom;
      if (since >= VIBRATION_HOLD.max || (since >= VIBRATION_HOLD.min && st.vibCalm >= 2)) st.vibFrom = 0;
    }
    if (st.vibFrom) a = st.lastCalm;
    else st.lastCalm = a;
    if (!st.zero) {
      samples.push(a);
      if (now - t0 < CALIB_MS) return;
      st.zero = calibrate(samples);
      last = now;
      if (opts.ready) opts.ready();
      return;
    }
    const dt = now - last;
    last = now;
    const tilt = { x: sideTilt(a, st.zero), y: vertTilt(a, st.zero) };
    opts.tick(a, now, dt, tilt);
  }, POLL_MS);
  return st.motionOk;
}

export function stopMotion(st) {
  if (st.poll) clearInterval(st.poll);
  st.poll = null;
  stopAccel(st.accel);
  if (st.buzzer) st.buzzer.stop();
  releaseScreen();
}

export function buzz(st, scene) {
  if (st.buzzer) st.buzzer.buzz(scene);
  st.vibFrom = Date.now();
  st.vibCalm = 0;
}
