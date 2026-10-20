// Sprzęt zegarka: akcelerometr (potrząsanie), wibracje, ekran. Każdy błąd jest łapany,
// żeby brak jakiejś funkcji w systemie nie dał czarnego ekranu.
import { Accelerometer, FREQ_MODE_HIGH, Vibrator } from "@zos/sensor";
import { setPageBrightTime, setWakeUpRelaunch } from "@zos/display";

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

// Między rzutami ekran może zgasnąć; po podniesieniu ręki wraca ta sama strona z wynikiem
export function setupScreen() {
  try {
    setWakeUpRelaunch({ relaunch: true });
  } catch (e) {}
  try {
    setPageBrightTime({ brightTime: 30000 });
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
