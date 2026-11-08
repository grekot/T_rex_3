import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";

export const { width: DEVICE_WIDTH } = getDeviceInfo();

export const COLOR_TEXT = 0xffffff;
export const COLOR_GREY = 0x9a9a9a;
export const COLOR_ORANGE = 0xff9100;
export const COLOR_ON = 0x2e7d32;
export const COLOR_OFF = 0x424242;

const W = DEVICE_WIDTH;

const text = (y, h, size, color, inset = 60, extra) => ({
  x: px(inset),
  y: px(y),
  w: W - px(2 * inset),
  h: px(h),
  text: "",
  text_size: px(size),
  color,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.WRAP,
  ...extra,
});

export const TITLE_STYLE = text(34, 44, 34, COLOR_ORANGE, 100, { text: "Szczyty" });
export const DB_STYLE = text(80, 56, 22, COLOR_TEXT, 50);
export const OSM_STYLE = text(138, 54, 20, COLOR_GREY, 40, {
  text: "Dane: © OpenStreetMap contributors, licencja ODbL",
});

// Przełącznik korekty deklinacji
const DECL_RECT = { x: px(50), y: px(200), w: W - px(100), h: px(60) };
export const DECL_BG = { ...DECL_RECT, radius: px(30), color: COLOR_OFF };
export const DECL_STYLE = { ...text(0, 0, 21, COLOR_TEXT), ...DECL_RECT };

// Zasięg wykrywania: [-]  Zasięg: 60 km  [+]
const RANGE_Y = 270;
const RANGE_H = 56;
const RANGE_BTN = (x) => ({ x: px(x), y: px(RANGE_Y), w: px(64), h: px(RANGE_H) });
export const RANGE_MINUS_BG = { ...RANGE_BTN(60), radius: px(28), color: 0x262626 };
export const RANGE_MINUS = { ...text(0, 0, 34, COLOR_TEXT), ...RANGE_BTN(60), text: "-" };
export const RANGE_PLUS_BG = { ...RANGE_BTN(356), radius: px(28), color: 0x262626 };
export const RANGE_PLUS = { ...text(0, 0, 34, COLOR_TEXT), ...RANGE_BTN(356), text: "+" };
export const RANGE_STYLE = { ...text(RANGE_Y, RANGE_H, 22, COLOR_TEXT), x: px(128), w: px(224) };

export const HELP_STYLE = text(332, 64, 18, COLOR_GREY, 60, {
  text: "Kompas: zatocz ósemkę. Stuknięcie w nazwę albo przycisk = zatrzymaj odczyt.",
});

const BACK_RECT = { x: W / 2 - px(80), y: px(400), w: px(160), h: px(48) };
export const BACK_BG = { ...BACK_RECT, radius: px(24), color: 0x262626 };
export const BACK_STYLE = { ...text(0, 0, 26, COLOR_TEXT), ...BACK_RECT, text: "Wróć" };
