// `node test/format.test.mjs` - testy formatowania, bez zegarka
import assert from "node:assert/strict";
import { formatNumber, formatCompact, plural, withUnit, formatTime, formatDuration, relativeDay, shorten } from "../utils/format.js";

const DAY = 86400000;
const NOW = Date.parse("2026-10-16T12:00:00Z");
assert.equal(formatDuration(45), "0:45");
assert.equal(formatDuration(754), "12:34");
assert.equal(formatDuration(3723), "1:02:03");
assert.equal(formatDuration(0), "0:00");
assert.equal(relativeDay(NOW - 3 * 3600000, NOW), "dzisiaj");
assert.equal(relativeDay(NOW - 1 * DAY, NOW), "wczoraj");
assert.equal(relativeDay(NOW - 3 * DAY, NOW), "3 dni temu");
assert.equal(relativeDay(NOW - 7 * DAY, NOW), "tydzień temu");
assert.equal(relativeDay(NOW - 20 * DAY, NOW), "2 tyg. temu");
assert.equal(relativeDay(NOW - 35 * DAY, NOW), "miesiąc temu");
assert.equal(relativeDay(NOW - 100 * DAY, NOW), "3 mies. temu");
assert.equal(relativeDay(NOW - 400 * DAY, NOW), "rok temu");
assert.equal(relativeDay(NOW - 800 * DAY, NOW), "2 lata temu");
assert.equal(relativeDay(NOW - 2000 * DAY, NOW), "5 lat temu");

// dni kalendarzowe, nie pełne doby (czas lokalny)
const local = (d, h, m = 0) => new Date(2026, 9, d, h, m).getTime();
assert.equal(relativeDay(local(15, 20), local(16, 8)), "wczoraj", "12 h temu, ale wczoraj w kalendarzu");
assert.equal(relativeDay(local(15, 23, 59), local(16, 0, 1)), "wczoraj", "2 minuty po północy");
assert.equal(relativeDay(local(16, 0, 1), local(16, 23, 59)), "dzisiaj", "prawie doba, ale ten sam dzień");
assert.equal(relativeDay(local(14, 23), local(16, 1)), "2 dni temu", "26 h temu, ale przedwczoraj");
// przejście z czasu letniego na zimowy (25.10.2026) nie psuje liczenia
assert.equal(relativeDay(new Date(2026, 9, 24, 12).getTime(), new Date(2026, 9, 26, 12).getTime()), "2 dni temu");

assert.equal(formatNumber(0), "0");
assert.equal(formatNumber(7), "7");
assert.equal(formatNumber(999), "999");
assert.equal(formatNumber(1000), "1 000");
assert.equal(formatNumber(12345), "12 345");
assert.equal(formatNumber(1234567), "1 234 567");
assert.equal(formatNumber("4200"), "4 200");
assert.equal(formatNumber(-1500), "-1 500");
assert.equal(formatNumber(undefined), "0");

assert.equal(formatCompact(9999999), "9 999 999");
assert.equal(formatCompact(12345678), "12,3 mln");
assert.equal(formatCompact(1500000000), "1,5 mld");

assert.equal(plural(1, "film", "filmy", "filmów"), "film");
assert.equal(plural(2, "film", "filmy", "filmów"), "filmy");
assert.equal(plural(4, "film", "filmy", "filmów"), "filmy");
assert.equal(plural(5, "film", "filmy", "filmów"), "filmów");
assert.equal(plural(12, "film", "filmy", "filmów"), "filmów");
assert.equal(plural(14, "film", "filmy", "filmów"), "filmów");
assert.equal(plural(22, "film", "filmy", "filmów"), "filmy");
assert.equal(plural(112, "film", "filmy", "filmów"), "filmów");
assert.equal(plural(0, "film", "filmy", "filmów"), "filmów");
assert.equal(withUnit(1, "wyświetlenie", "wyświetlenia", "wyświetleń"), "1 wyświetlenie");
assert.equal(withUnit(2345, "wyświetlenie", "wyświetlenia", "wyświetleń"), "2 345 wyświetleń");
assert.equal(withUnit(1002, "wyświetlenie", "wyświetlenia", "wyświetleń"), "1 002 wyświetlenia");

assert.equal(formatTime(new Date(2026, 9, 15, 9, 5)), "09:05");
assert.equal(formatTime(new Date(2026, 9, 15, 14, 32)), "14:32");

assert.equal(shorten("krótki"), "krótki");
assert.equal(shorten("a".repeat(70), 60).length, 60);
assert.ok(shorten("a".repeat(70), 60).endsWith("..."));

console.log("format: WSZYSTKIE TESTY OK");
