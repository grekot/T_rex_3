// Uniesienie / opuszczenie nadgarstka z dwóch źródeł naraz: systemowe onWristMotion (nie wiadomo, czy
// przychodzi, gdy aplikacja jest na ekranie) i własne wykrywanie z akcelerometru (utils/wrist.js).
// Liczy się to, co zgłosi się pierwsze. Każdy błąd jest łapany, żeby brak funkcji nie dał czarnego ekranu.
import { Accelerometer } from "@zos/sensor";
import { onWristMotion, WRIST_MOTION_LIFT, WRIST_MOTION_LOWER } from "@zos/interaction";
import { wristState, feedWrist } from "./wrist.js";

const POLL_MS = 100;

// onWristMotion nie ma wyrejestrowania, więc rejestrujemy raz, a zdarzenia trafiają do bieżącego obserwatora
let current = null;
let systemHooked = false;

function hookSystem() {
  if (systemHooked) return;
  systemHooked = true;
  try {
    onWristMotion({
      callback: (r) => {
        if (!current || !r) return;
        // type 3 = zdarzenie nadgarstka (pole od API 3.6, wcześniej może go nie być)
        if (r.type !== undefined && r.type !== 3) return;
        if (r.motion === WRIST_MOTION_LIFT) current.emit("up");
        else if (r.motion === WRIST_MOTION_LOWER) current.emit("down");
      },
    });
  } catch (e) {}
}

// onEvent("up" | "down"); zwraca uchwyt do stopWrist
export function watchWrist(onEvent) {
  const w = { sensor: null, onChange: null, last: null, timer: null, st: wristState(), active: true };
  w.emit = (ev) => {
    if (w.active) onEvent(ev);
  };
  current = w;
  hookSystem();
  try {
    w.sensor = new Accelerometer();
    w.onChange = () => {
      try {
        w.last = w.sensor.getCurrent();
      } catch (e) {}
    };
    w.sensor.onChange(w.onChange);
    w.sensor.start();
    w.timer = setInterval(() => {
      let a = null;
      try {
        a = w.sensor.getCurrent();
      } catch (e) {}
      if (!a || typeof a.x !== "number") a = w.last;
      const ev = feedWrist(w.st, a, Date.now());
      if (ev) w.emit(ev);
    }, POLL_MS);
  } catch (e) {
    w.sensor = null;
  }
  return w;
}

export function stopWrist(w) {
  if (!w) return;
  w.active = false;
  if (current === w) current = null;
  if (w.timer) clearInterval(w.timer);
  w.timer = null;
  if (!w.sensor) return;
  try {
    w.sensor.offChange(w.onChange);
  } catch (e) {}
  try {
    w.sensor.stop();
  } catch (e) {}
  w.sensor = null;
}
