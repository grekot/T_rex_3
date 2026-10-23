import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const COLOR_TEXT = 0xffffff;
export const COLOR_GREY = 0x8a8a8a;
export const COLOR_DIM = 0x4a4a4a;
export const COLOR_ORANGE = 0xff9100;
export const COLOR_GREEN = 0x4caf50;
export const COLOR_RED = 0xef5350;
export const COLOR_PILL = 0x262626;
export const COLOR_PILL_DOWN = 0x404040;
export const COLOR_BUTTON = 0xe67e00;

const CX = DEVICE_WIDTH / 2;

const CENTERED = {
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

export const DATE_STYLE = {
  ...CENTERED,
  x: CX - px(120),
  y: px(34),
  w: px(240),
  h: px(36),
  text: "",
  text_size: px(26),
  color: COLOR_GREY,
};

// Duża liczba: "82,3"
export const VALUE_STYLE = {
  ...CENTERED,
  x: CX - px(130),
  y: px(112),
  w: px(260),
  h: px(120),
  text: "",
  text_size: px(100),
  color: COLOR_TEXT,
};

export const UNIT_STYLE = {
  ...CENTERED,
  x: CX - px(60),
  y: px(224),
  w: px(120),
  h: px(30),
  text: "kg",
  text_size: px(26),
  color: COLOR_GREY,
};

// Okrągłe przyciski − i + po bokach liczby
const BTN_R = px(52);
const BTN_Y = px(172);
function roundButton(cx, label) {
  return {
    circle: { center_x: cx, center_y: BTN_Y, radius: BTN_R, color: COLOR_PILL },
    text: {
      ...CENTERED,
      x: cx - BTN_R,
      y: BTN_Y - BTN_R,
      w: BTN_R * 2,
      h: BTN_R * 2,
      text: label,
      text_size: px(64),
      color: COLOR_ORANGE,
    },
  };
}
export const MINUS_BTN = roundButton(px(80), "−");
export const PLUS_BTN = roundButton(DEVICE_WIDTH - px(80), "+");

export const CHANGE_STYLE = {
  ...CENTERED,
  x: CX - px(170),
  y: px(258),
  w: px(340),
  h: px(32),
  text: "",
  text_size: px(24),
  color: COLOR_GREY,
};

export const AVG_STYLE = {
  ...CENTERED,
  x: CX - px(170),
  y: px(288),
  w: px(340),
  h: px(28),
  text: "",
  text_size: px(20),
  color: COLOR_GREY,
};

// Wykres 14 dni: słupki od dołu obszaru, dzisiejszy pomarańczowy
export const CHART_DAYS = 14;
export const CHART = { x: CX - px(119), y: px(326), w: px(238), h: px(54) };
export const BAR_MIN_H = px(6);
const PITCH = CHART.w / CHART_DAYS;
const BAR_W = Math.round(PITCH * 0.7);
export function barRect(i, h) {
  return {
    x: Math.round(CHART.x + i * PITCH + (PITCH - BAR_W) / 2),
    y: CHART.y + CHART.h - h,
    w: BAR_W,
    h,
    radius: Math.min(px(3), Math.floor(BAR_W / 2)),
  };
}
// Dzień bez pomiaru: kropka przy dolnej krawędzi
export function gapRect(i) {
  return barRect(i, px(3));
}
// Czarny (niewidoczny na tle) obszar pod wykresem do stuknięcia -> historia
export const CHART_HIT = { x: CHART.x, y: CHART.y - px(8), w: CHART.w, h: CHART.h + px(16), color: 0x000000 };

const SAVE_RECT = { x: CX - px(100), y: px(394), w: px(200), h: px(52) };
export const SAVE_BG = { ...SAVE_RECT, radius: px(26), color: COLOR_BUTTON };
export const SAVE_STYLE = { ...CENTERED, ...SAVE_RECT, text: "ZAPISZ", text_size: px(28), color: COLOR_TEXT };
