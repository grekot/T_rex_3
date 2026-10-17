import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";
import { COLOR_WHITE, COLOR_GREY, COLOR_GREEN, COLOR_ROW } from "../../../utils/ui";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();
export { COLOR_GREY };

export const TITLE_STYLE = {
  x: 0,
  y: px(24),
  w: DEVICE_WIDTH,
  h: px(40),
  text: "USTAWIENIA",
  text_size: px(28),
  char_space: px(2),
  color: COLOR_GREEN,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

// Wiersz z przełącznikiem
const ROW_X = px(48);
const ROW_W = DEVICE_WIDTH - px(96);
export const TOGGLE_Y = px(84);
export const TOGGLE_H = px(110);
const PILL_W = px(76);
const PILL_H = px(42);

export const TOGGLE_BG = { x: ROW_X, y: TOGGLE_Y, w: ROW_W, h: TOGGLE_H, radius: px(24), color: COLOR_ROW };

export const TOGGLE_LABEL = {
  x: ROW_X + px(22),
  y: TOGGLE_Y,
  w: ROW_W - px(22) - PILL_W - px(36),
  h: TOGGLE_H,
  text: "Nie wygaszaj po opuszczeniu ręki",
  text_size: px(24),
  color: COLOR_WHITE,
  align_h: hmUI.align.LEFT,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.WRAP,
};

const PILL_X = ROW_X + ROW_W - PILL_W - px(22);
const PILL_Y = TOGGLE_Y + (TOGGLE_H - PILL_H) / 2;

export function pillProps(on) {
  return { x: PILL_X, y: PILL_Y, w: PILL_W, h: PILL_H, radius: PILL_H / 2, color: on ? 0x2e7d32 : 0x444444 };
}

export function knobProps(on) {
  const r = PILL_H / 2 - px(5);
  return {
    center_x: on ? PILL_X + PILL_W - PILL_H / 2 : PILL_X + PILL_H / 2,
    center_y: PILL_Y + PILL_H / 2,
    radius: r,
    color: COLOR_WHITE,
  };
}

export function infoStyle(y, h, text) {
  return {
    x: px(64),
    y,
    w: DEVICE_WIDTH - px(128),
    h,
    text,
    text_size: px(20),
    color: COLOR_GREY,
    align_h: hmUI.align.CENTER_H,
    align_v: hmUI.align.CENTER_V,
    text_style: hmUI.text_style.WRAP,
  };
}

export const INFO_Y = TOGGLE_Y + TOGGLE_H + px(8);
export const SYNC_Y = INFO_Y + px(96);
export const ACCOUNT_Y = SYNC_Y + px(76);
