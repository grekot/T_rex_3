// GPS i kompas zegarka w prostych opakowaniach: start(callback) -> { stop() }.
import { Geolocation, Compass, FREQ_MODE_NORMAL } from "@zos/sensor";
import { signedCoord, validCoords } from "./geo";

// onFix({ lat, lon }) przy każdej nowej pozycji albo onFix(null), gdy GPS jeszcze szuka
export function startGps(onFix) {
  let geo;
  try {
    geo = new Geolocation();
  } catch (e) {
    onFix(null);
    return { stop() {} };
  }
  const read = () => {
    try {
      if (geo.getStatus() !== "A") {
        onFix(null);
        return;
      }
      const lat = signedCoord(geo.getLatitude({ format: "DD" }), geo.getLatitude({ format: "DMS" }));
      const lon = signedCoord(geo.getLongitude({ format: "DD" }), geo.getLongitude({ format: "DMS" }));
      onFix(validCoords(lat, lon) ? { lat, lon } : null);
    } catch (e) {
      onFix(null);
    }
  };
  try {
    geo.start();
    geo.onChange(read);
  } catch (e) {}
  read();
  return {
    stop() {
      try {
        geo.offChange(read);
        geo.stop();
      } catch (e) {}
    },
  };
}

// onHeading(stopnie od północy) albo onHeading(null), gdy kompas wymaga kalibracji
export function startCompass(onHeading) {
  let compass;
  try {
    compass = new Compass();
  } catch (e) {
    onHeading(null);
    return { stop() {} };
  }
  const read = () => {
    try {
      const angle = compass.getDirectionAngle();
      onHeading(compass.getStatus() && typeof angle === "number" ? angle : null);
    } catch (e) {
      onHeading(null);
    }
  };
  try {
    if (FREQ_MODE_NORMAL !== undefined && compass.setFreqMode) compass.setFreqMode(FREQ_MODE_NORMAL);
  } catch (e) {}
  try {
    compass.onChange(read);
    compass.start();
  } catch (e) {}
  read();
  return {
    stop() {
      try {
        compass.offChange(read);
        compass.stop();
      } catch (e) {}
    },
  };
}
