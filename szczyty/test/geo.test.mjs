import test from "node:test";
import assert from "node:assert/strict";
import {
  angleDiff, bearing, distance, elevationAngle, curvatureDrop, horizonDistance, smoothAngle,
  formatDistance, cardinal, formatDeg, signedCoord, formatWhen,
} from "../utils/geo.js";
import { declination, trueHeading, yearOf } from "../utils/declination.js";

const near = (a, b, eps, msg) => assert.ok(Math.abs(a - b) <= eps, `${msg ?? ""} ${a} != ${b} (±${eps})`);

test("odległość i kierunek: Zakopane -> Babia Góra", () => {
  // Zakopane Krupówki 49.2992, 19.9496; Babia Góra 49.5731, 19.5292
  const d = distance(49.2992, 19.9496, 49.5731, 19.5292);
  near(d / 1000, 43.4, 0.5, "km");
  near(bearing(49.2992, 19.9496, 49.5731, 19.5292), 315.6, 1, "kierunek");
});

test("angleDiff ma znak i zawija się przez północ", () => {
  assert.equal(angleDiff(10, 350), 20);
  assert.equal(angleDiff(350, 10), -20);
  assert.equal(angleDiff(180, 0), 180);
  assert.equal(angleDiff(90, 90), 0);
});

test("krzywizna Ziemi: 100 km chowa ok. 680 m (z refrakcją)", () => {
  near(curvatureDrop(100000), 683, 5);
  near(curvatureDrop(10000), 6.8, 0.1);
  // Rysy (2499) z Babiej Góry (1725), 80 km: wysoko nad horyzontem, ale mniej niż bez krzywizny
  const flat = (Math.atan2(2499 - 1725, 80000) * 180) / Math.PI;
  const real = elevationAngle(1725, 2499, 80000);
  assert.ok(real < flat && real > 0);
  near(horizonDistance(1725) / 1000, 159, 2);
});

test("wygładzanie kompasu po najkrótszym łuku", () => {
  assert.equal(smoothAngle(null, 370, 0.3), 10);
  near(smoothAngle(358, 2, 0.5), 0, 1e-9);
  near(smoothAngle(10, 350, 0.5), 0, 1e-9);
});

test("formatowanie", () => {
  assert.equal(formatDistance(347), "350 m");
  assert.equal(formatDistance(4321), "4,3 km");
  assert.equal(formatDistance(38200), "38 km");
  assert.equal(cardinal(213), "Pd-Zach");
  assert.equal(cardinal(359), "Pn");
  assert.equal(formatDeg(359.7), "0°");
  assert.equal(formatDeg(-3), "357°");
  assert.equal(signedCoord(19.5, { direction: "W" }), -19.5);
  assert.equal(signedCoord("49.1", { direction: "N" }), 49.1);
  const now = new Date(2026, 9, 20, 15, 0).getTime();
  assert.equal(formatWhen(new Date(2026, 9, 20, 14, 5).getTime(), now), "dziś 14:05");
  assert.equal(formatWhen(new Date(2026, 9, 19, 8, 0).getTime(), now), "wczoraj 08:00");
});

test("deklinacja WMM2025 (wartości z kalkulatora NOAA)", () => {
  // węzeł siatki 1.01.2027
  near(declination(49.5, 19.5, 2027.0), 6.215, 0.001);
  // Zakopane 20.10.2026: NOAA podaje 6,25°
  near(declination(49.3, 19.95, 2026.8), 6.25, 0.05);
  // wschód kraju ma większą deklinację niż zachód
  assert.ok(declination(52.2, 23.5, 2027) > declination(52.2, 14.7, 2027) + 2);
  // poza siatką - brzeg, bez wybuchów
  assert.ok(isFinite(declination(40, 0, 2040)));
  near(yearOf(new Date(2026, 9, 1).getTime()), 2026.75, 1e-9);
  assert.equal(trueHeading(355, 6.5), 1.5);
  assert.equal(trueHeading(10, -12), 358);
});
