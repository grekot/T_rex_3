import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const COLOR_WHITE = 0xffffff;
export const COLOR_GREY = 0x8a8a8a;
export const COLOR_GREEN = 0x4caf50;
export const COLOR_ORANGE = 0xff9100;
export const COLOR_ROW = 0x1c1c1c;

export const TITLE_STYLE = {
  x: 0,
  y: px(24),
  w: DEVICE_WIDTH,
  h: px(40),
  text: "ZAKUPY",
  text_size: px(30),
  char_space: px(2),
  color: COLOR_GREEN,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

export const STATUS_STYLE = {
  x: px(90),
  y: px(64),
  w: DEVICE_WIDTH - px(180),
  h: px(30),
  text: "",
  text_size: px(20),
  color: COLOR_GREY,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.ELLIPSIS,
};

export const MESSAGE_STYLE = {
  x: px(70),
  y: px(150),
  w: DEVICE_WIDTH - px(140),
  h: px(200),
  text: "",
  text_size: px(26),
  color: COLOR_WHITE,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.WRAP,
};

// Wiersze list (strona przewija się, gdy jest ich więcej niż mieści ekran)
const ROW_X = px(60);
const ROW_W = DEVICE_WIDTH - px(120);
const ROW_H = px(76);
const ROW_GAP = px(12);
const ROWS_TOP = px(108);

export function rowRect(index) {
  return { x: ROW_X, y: ROWS_TOP + index * (ROW_H + ROW_GAP), w: ROW_W, h: ROW_H };
}

export function rowBgProps(index) {
  return { ...rowRect(index), radius: px(22), color: COLOR_ROW };
}

export function rowNameStyle(index) {
  const r = rowRect(index);
  return {
    x: r.x + px(24),
    y: r.y,
    w: r.w - px(24) - px(110),
    h: r.h,
    text: "",
    text_size: px(30),
    color: COLOR_WHITE,
    align_h: hmUI.align.LEFT,
    align_v: hmUI.align.CENTER_V,
    text_style: hmUI.text_style.ELLIPSIS,
  };
}

export function rowCountStyle(index) {
  const r = rowRect(index);
  return {
    x: r.x + r.w - px(110),
    y: r.y,
    w: px(90),
    h: r.h,
    text: "",
    text_size: px(28),
    color: COLOR_GREEN,
    align_h: hmUI.align.RIGHT,
    align_v: hmUI.align.CENTER_V,
    text_style: hmUI.text_style.NONE,
  };
}

// Ikona "wszystko kupione" zamiast licznika
export function rowDoneIconProps(index) {
  const r = rowRect(index);
  return { x: r.x + r.w - px(56), y: r.y + (r.h - px(36)) / 2, src: "icons/done.png" };
}

// Niewidoczny odstęp na końcu, żeby ostatni przycisk dało się przewinąć na środek ekranu
export function bottomSpacerProps(y) {
  return { x: 0, y, w: DEVICE_WIDTH, h: px(100), color: 0x000000 };
}
