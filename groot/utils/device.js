// Sprzęt zegarka: akcelerometr (minigry), ekran i wibracje. Każdy błąd jest łapany,
// żeby brak jakiejś funkcji w systemie nie dał czarnego ekranu.
import { Accelerometer, FREQ_MODE_HIGH, Vibrator } from "@zos/sensor";
import {
  setPageBrightTime,
  resetPageBrightTime,
  pauseDropWristScreenOff,
  resetDropWristScreenOff,
} from "@zos/display";

export function startAccel() {
  const a = { sensor: null, last: null, onChange: null };
  try {
    a.sensor = new Accelerometer();
    try {
      a.sensor.setFreqMode(FREQ_MODE_HIGH);
    } catch (e) {}
    a.onChange = () => {
      try {
        a.last = a.sensor.getCurrent();
      } catch (e) {}
    };
    a.sensor.onChange(a.onChange);
    a.sensor.start();
  } catch (e) {
    a.sensor = null;
  }
  return a;
}

// Ostatni odczyt { x, y, z } w cm/s^2 albo null
export function readAccel(a) {
  if (!a || !a.sensor) return null;
  let r = null;
  try {
    r = a.sensor.getCurrent();
  } catch (e) {}
  return r && typeof r.x === "number" ? r : a.last;
}

export function stopAccel(a) {
  if (!a || !a.sensor) return;
  try {
    a.sensor.offChange(a.onChange);
  } catch (e) {}
  try {
    a.sensor.stop();
  } catch (e) {}
  a.sensor = null;
}

// Minigry ruchowe: nikt nie dotyka ekranu, a ręka się rusza - bez tego ekran by gasł
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
