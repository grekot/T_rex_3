// GPS, kompas i barometr zegarka w prostych opakowaniach. Każdy błąd jest łapany, żeby brak
// czujnika albo uprawnienia nie dał czarnego ekranu. Na bazie powrot/watch/utils/sensors.js.
import { Geolocation, Compass, Barometer } from "@zos/sensor";
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

// Kompas: read() -> kąt 12:00 od północy (wg czujnika) albo null, gdy wymaga kalibracji.
// Dokumentacja: "względem północy", getDirectionAngle() = 'INVALID' przed kalibracją.
export function startCompass() {
  let compass = null;
  const noop = () => {};
  try {
    compass = new Compass();
    compass.onChange(noop);
    compass.start();
  } catch (e) {
    compass = null;
  }
  return {
    read() {
      if (!compass) return null;
      try {
        const angle = compass.getDirectionAngle();
        return compass.getStatus() && typeof angle === "number" && isFinite(angle) ? angle : null;
      } catch (e) {
        return null;
      }
    },
    stop() {
      if (!compass) return;
      try {
        compass.offChange(noop);
      } catch (e) {}
      try {
        compass.stop();
      } catch (e) {}
      compass = null;
    },
  };
}

// Wysokość z barometru (m n.p.m., przybliżona - zależy od pogody) albo null
export function startAltimeter() {
  let baro = null;
  const noop = () => {};
  try {
    baro = new Barometer();
    baro.onChange(noop);
  } catch (e) {
    baro = null;
  }
  return {
    read() {
      if (!baro) return null;
      try {
        const h = baro.getAltitude();
        return typeof h === "number" && isFinite(h) && h > -500 && h < 9000 ? h : null;
      } catch (e) {
        return null;
      }
    },
    stop() {
      if (!baro) return;
      try {
        baro.offChange(noop);
      } catch (e) {}
      baro = null;
    },
  };
}
