import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";
import { COLOR_WHITE, COLOR_GREY, COLOR_GREEN, COLOR_ROW } from "../../../utils/ui";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();
export { COLOR_GREY, COLOR_GREEN };

export const TITLE_STYLE = {
  x: px(80),
  y: px(20),
  w: DEVICE_WIDTH - px(160),
  h: px(36),
  text: "",
  text_size: px(24),
  char_space: px(1),
  color: COLOR_GREEN,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

export const SUB_STYLE = {
  x: px(80),
  y: px(56),
  w: DEVICE_WIDTH - px(160),
  h: px(36),
  text: "",
  text_size: px(26),
  color: COLOR_WHITE,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.ELLIPSIS,
};

export const BUTTONS_Y = px(100);

export function labelStyle(y, text) {
  return {
    x: px(60),
    y,
    w: DEVICE_WIDTH - px(120),
    h: px(40),
    text,
    text_size: px(20),
    color: COLOR_GREY,
    align_h: hmUI.align.CENTER_H,
    align_v: hmUI.align.CENTER_V,
    text_style: hmUI.text_style.WRAP,
  };
}

// Wiersze podpowiedzi
const ROW_X = px(56);
const ROW_W = DEVICE_WIDTH - px(112);
export const ROW_H = px(66);
const ROW_GAP = px(10);

export function rowStep() {
  return ROW_H + ROW_GAP;
}

export function rowBgProps(y) {
  return { x: ROW_X, y, w: ROW_W, h: ROW_H, radius: px(20), color: COLOR_ROW };
}

export function rowPlusStyle(y) {
  return {
    x: ROW_X + px(16),
    y,
    w: px(36),
    h: ROW_H,
    text: "+",
    text_size: px(34),
    color: COLOR_GREEN,
    align_h: hmUI.align.CENTER_H,
    align_v: hmUI.align.CENTER_V,
    text_style: hmUI.text_style.NONE,
  };
}

export function rowNameStyle(y) {
  return {
    x: ROW_X + px(60),
    y,
    w: ROW_W - px(76),
    h: ROW_H,
    text: "",
    text_size: px(28),
    color: COLOR_WHITE,
    align_h: hmUI.align.LEFT,
    align_v: hmUI.align.CENTER_V,
    text_style: hmUI.text_style.ELLIPSIS,
  };
}

export function bottomSpacerProps(y) {
  return { x: 0, y, w: DEVICE_WIDTH, h: px(120), color: 0x000000 };
}
