import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const COLOR_WHITE = 0xffffff;
export const COLOR_GREY = 0x8a8a8a;
export const COLOR_DONE_TEXT = 0x6a6a6a;
export const COLOR_GREEN = 0x4caf50;
export const COLOR_ORANGE = 0xff9100;
export const COLOR_ROW = 0x1c1c1c;
export const COLOR_ROW_DONE = 0x0f0f0f;

export const HEADER_STYLE = {
  x: px(80),
  y: px(20),
  w: DEVICE_WIDTH - px(160),
  h: px(40),
  text: "",
  text_size: px(28),
  color: COLOR_WHITE,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.ELLIPSIS,
};

export const SUB_STYLE = {
  x: px(90),
  y: px(60),
  w: DEVICE_WIDTH - px(180),
  h: px(30),
  text: "",
  text_size: px(20),
  color: COLOR_GREY,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.ELLIPSIS,
};

const LIST_TOP = px(104);
const ROW_X = px(48);
const ROW_W = DEVICE_WIDTH - px(96);
export const ROW_H = px(80);
const ROW_GAP = px(10);
export const LABEL_H = px(44);
const CHECK = px(40);

// Kolejne elementy listy układamy od góry; y liczy strona (wiersze i etykiety mają różne wysokości)
export function startY() {
  return LIST_TOP;
}

export function rowBgProps(y, done) {
  return { x: ROW_X, y, w: ROW_W, h: ROW_H, radius: px(22), color: done ? COLOR_ROW_DONE : COLOR_ROW };
}

// W trybie edycji zamiast pola wyboru jest kosz
export function rowCheckProps(y, done, edit) {
  return {
    x: ROW_X + px(18),
    y: y + (ROW_H - CHECK) / 2,
    src: edit ? "icons/trash.png" : done ? "icons/checked.png" : "icons/box.png",
  };
}

export function rowNameStyle(y, done) {
  return {
    x: ROW_X + px(18) + CHECK + px(14),
    y,
    w: ROW_W - (px(18) + CHECK + px(14)) - px(18),
    h: ROW_H,
    text: "",
    text_size: px(28),
    color: done ? COLOR_DONE_TEXT : COLOR_WHITE,
    align_h: hmUI.align.LEFT,
    align_v: hmUI.align.CENTER_V,
    text_style: hmUI.text_style.WRAP,
  };
}

export function rowStep() {
  return ROW_H + ROW_GAP;
}

export function labelStyle(y, text, color) {
  return {
    x: px(60),
    y,
    w: DEVICE_WIDTH - px(120),
    h: LABEL_H,
    text,
    text_size: px(22),
    color: color || COLOR_GREY,
    align_h: hmUI.align.CENTER_H,
    align_v: hmUI.align.CENTER_V,
    text_style: hmUI.text_style.NONE,
  };
}

export function bottomSpacerProps(y) {
  return { x: 0, y, w: DEVICE_WIDTH, h: px(140), color: 0x000000 };
}
