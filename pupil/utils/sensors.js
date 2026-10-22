// GPS, kompas i barometr w prostych opakowaniach (na bazie szczyty/utils/sensors.js).
// Każdy błąd jest łapany, żeby brak czujnika albo uprawnienia nie dał czarnego ekranu.
import { Geolocation, Compass, Barometer } from "@zos/sensor";

function signedCoord(dd, dms) {
  const value = Math.abs(Number(dd));
  const dir = dms && typeof dms === "object" ? String(dms.direction || "").toUpperCase() : "";
  return dir === "S" || dir === "W" ? -value : value;
}

function validCoords(lat, lon) {
  return isFinite(lat) && isFinite(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180 && !(lat === 0 && lon === 0);
}

// read() -> { lat, lon } albo null, gdy GPS jeszcze szuka
export function startGps() {
  let geo = null;
  const noop = () => {};
  try {
    geo = new Geolocation();
    geo.start();
    geo.onChange(noop);
  } catch (e) {
    geo = null;
  }
  return {
    read() {
      if (!geo) return null;
      try {
        if (geo.getStatus() !== "A") return null;
        const lat = signedCoord(geo.getLatitude({ format: "DD" }), geo.getLatitude({ format: "DMS" }));
        const lon = signedCoord(geo.getLongitude({ format: "DD" }), geo.getLongitude({ format: "DMS" }));
        return validCoords(lat, lon) ? { lat, lon } : null;
      } catch (e) {
        return null;
      }
    },
    stop() {
      if (!geo) return;
      try {
        geo.offChange(noop);
      } catch (e) {}
      try {
        geo.stop();
      } catch (e) {}
      geo = null;
    },
  };
}

// read() -> kąt godziny 12 od północy albo null (kompas wymaga kalibracji)
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

// read() -> wysokość z barometru (m, przybliżona) albo null
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
