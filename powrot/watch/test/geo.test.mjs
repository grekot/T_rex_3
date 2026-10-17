// `node test/geo.test.mjs` - odległości, kierunki i formatowanie, bez zegarka
import assert from "node:assert/strict";
import {
  normalize,
  distance,
  bearing,
  relativeAngle,
  smoothAngle,
  formatDistance,
  cardinal,
  signedCoord,
  validCoords,
  formatSavedAt,
  ARRIVED_M,
} from "../utils/geo.js";

const near = (a, b, tol, msg) => assert.ok(Math.abs(a - b) <= tol, `${msg}: ${a} != ${b} ±${tol}`);

assert.equal(normalize(370), 10);
assert.equal(normalize(-90), 270);
assert.equal(normalize(0), 0);

// Pałac Kultury (Warszawa) -> Wawel (Kraków): ok. 252 km na południowy zachód
const PKiN = [52.231838, 21.005995];
const WAWEL = [50.054008, 19.935278];
near(distance(...PKiN, ...WAWEL), 252000, 2000, "Warszawa-Kraków");
near(bearing(...PKiN, ...WAWEL), 197, 2, "kierunek Warszawa->Kraków");
assert.equal(cardinal(bearing(...PKiN, ...WAWEL)), "Pd");

// krótkie odległości (parking): 0.0001° szerokości ~ 11,1 m
near(distance(52.0, 21.0, 52.0001, 21.0), 11.1, 0.2, "11 m na północ");
near(bearing(52.0, 21.0, 52.0001, 21.0), 0, 0.5, "na północ");
near(bearing(52.0, 21.0, 52.0, 21.001), 90, 0.5, "na wschód");
near(bearing(52.0, 21.0, 51.999, 21.0), 180, 0.5, "na południe");
near(bearing(52.0, 21.0, 52.0, 20.999), 270, 0.5, "na zachód");
assert.equal(distance(52, 21, 52, 21), 0);

// strzałka: cel na wschodzie (90), patrzę na wschód (90) -> prosto (0); patrzę na północ -> w prawo (90)
assert.equal(relativeAngle(90, 90), 0);
assert.equal(relativeAngle(90, 0), 90);
assert.equal(relativeAngle(10, 350), 20);
assert.equal(relativeAngle(350, 10), 340);

// wygładzanie po najkrótszym łuku
assert.equal(smoothAngle(null, 370, 0.5), 10);
assert.equal(smoothAngle(0, 90, 0.5), 45);
near(smoothAngle(359, 1, 0.5), 0, 1e-9, "przez północ");
near(smoothAngle(10, 350, 0.5), 0, 1e-9, "przez północ wstecz");
assert.equal(smoothAngle(100, 200, 1), 200);

// formatowanie odległości
assert.equal(formatDistance(7.4), "7 m");
assert.equal(formatDistance(349.6), "350 m");
assert.equal(formatDistance(1250), "1,25 km");
assert.equal(formatDistance(12345), "12,3 km");
assert.equal(formatDistance(152400), "152 km");
assert.equal(formatDistance(NaN), "-");

assert.equal(cardinal(0), "Pn");
assert.equal(cardinal(44), "Pn-Wsch");
assert.equal(cardinal(359), "Pn");
assert.equal(cardinal(225), "Pd-Zach");

// znak współrzędnych z litery kierunku
assert.equal(signedCoord(52.1, { direction: "N" }), 52.1);
assert.equal(signedCoord(33.9, { direction: "S" }), -33.9);
assert.equal(signedCoord(-33.9, { direction: "S" }), -33.9, "DD już ze znakiem - nie odwracamy dwa razy");
assert.equal(signedCoord(118.2, { direction: "W" }), -118.2);
assert.equal(signedCoord(21.0, undefined), 21.0);

assert.equal(validCoords(52.1, 21.0), true);
assert.equal(validCoords(0, 0), false, "0,0 to typowa wartość przed ustaleniem pozycji");
assert.equal(validCoords(NaN, 21), false);
assert.equal(validCoords(95, 21), false);

const now = new Date(2026, 9, 17, 12, 0).getTime();
assert.equal(formatSavedAt(new Date(2026, 9, 17, 9, 5).getTime(), now), "dziś 09:05");
assert.equal(formatSavedAt(new Date(2026, 9, 16, 18, 30).getTime(), now), "wczoraj 18:30");
assert.equal(formatSavedAt(new Date(2026, 9, 3, 7, 0).getTime(), now), "03.10 07:00");

assert.ok(ARRIVED_M >= 5 && ARRIVED_M <= 30);

console.log("geo: WSZYSTKIE TESTY OK");
