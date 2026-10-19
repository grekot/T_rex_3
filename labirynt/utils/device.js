// Sprzęt zegarka: akcelerometr, ekran i wibracje. Każdy błąd jest łapany, żeby brak
// jakiejś funkcji w systemie nie dał czarnego ekranu.
import { Accelerometer, FREQ_MODE_HIGH, Vibrator } from "@zos/sensor";
import {
  setPageBrightTime,
  resetPageBrightTime,
  pauseDropWristScreenOff,
  resetDropWristScreenOff,
} from "@zos/display";

// Ile trwa kalibracja (zbieranie odczytów „tak trzymam zegarek poziomo”)
export const CALIB_MS = 500;
const SMOOTH = 0.5; // wygładzanie odczytów (0 = bez, bliżej 1 = mocniej)

export function createTilt() {
  const t = { sensor: null, last: null, smooth: null, onChange: null, error: "" };
  try {
    t.sensor = new Accelerometer();
    try {
      t.sensor.setFreqMode(FREQ_MODE_HIGH);
    } catch (e) {}
    t.onChange = () => {
      try {
        t.last = t.sensor.getCurrent();
      } catch (e) {}
    };
    t.sensor.onChange(t.onChange);
    t.sensor.start();
  } catch (e) {
    t.sensor = null;
    t.error = String(e);
  }
  return t;
}

// Aktualny, wygładzony odczyt { x, y, z } w cm/s^2 albo null
export function readTilt(t) {
  if (!t.sensor) return null;
  let r = null;
  try {
    r = t.sensor.getCurrent();
  } catch (e) {}
  if (!r || typeof r.x !== "number") r = t.last;
  if (!r || typeof r.x !== "number") return null;
  if (!t.smooth) t.smooth = { x: r.x, y: r.y, z: r.z };
  else {
    t.smooth.x = t.smooth.x * SMOOTH + r.x * (1 - SMOOTH);
    t.smooth.y = t.smooth.y * SMOOTH + r.y * (1 - SMOOTH);
    t.smooth.z = t.smooth.z * SMOOTH + r.z * (1 - SMOOTH);
  }
  return t.smooth;
}

export function stopTilt(t) {
  if (!t || !t.sensor) return;
  try {
    t.sensor.offChange(t.onChange);
  } catch (e) {}
  try {
    t.sensor.stop();
  } catch (e) {}
}

// W tej grze nikt nie dotyka ekranu, a nadgarstek się pochyla - bez tego ekran by gasł
export function keepScreenOn() {
  try {
    setPageBrightTime({ brightTime: 600000 });
  } catch (e) {}
  try {
    pauseDropWristScreenOff({ duration: 0 });
  } catch (e) {}
}

// Koniecznie przy wyjściu ze strony: wyłączenie gaszenia po opuszczeniu nadgarstka
// trwa do odwołania, także poza aplikacją
export function releaseScreen() {
  try {
    resetDropWristScreenOff();
  } catch (e) {}
  try {
    resetPageBrightTime();
  } catch (e) {}
}

export function createBuzzer() {
  let vibrator = null;
  return {
    buzz(scene) {
      try {
        if (!vibrator) vibrator = new Vibrator();
        vibrator.stop();
        vibrator.setMode(scene);
        vibrator.start();
      } catch (e) {}
    },
    stop() {
      try {
        if (vibrator) vibrator.stop();
      } catch (e) {}
    },
  };
}
