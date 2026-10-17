import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";
import { COLOR_WHITE, COLOR_GREY, COLOR_ORANGE, COLOR_ROW } from "../../../utils/ui";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const TITLE_STYLE = {
  x: 0,
  y: px(24),
  w: DEVICE_WIDTH,
  h: px(40),
  text: "POWRÓT",
  text_size: px(30),
  char_space: px(2),
  color: COLOR_ORANGE,
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

export const SAVE_Y = px(104);
export const ROWS_TOP = px(186);

export const EMPTY_STYLE = {
  x: px(70),
  y: ROWS_TOP,
  w: DEVICE_WIDTH - px(140),
  h: px(150),
  text: "Brak zapisanych miejsc.\nZapisz miejsce, np. gdzie zaparkowałeś auto.",
  text_size: px(24),
  color: COLOR_GREY,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.WRAP,
};

const ROW_X = px(52);
const ROW_W = DEVICE_WIDTH - px(104);
const ROW_H = px(82);
const ROW_GAP = px(10);

export function rowY(index) {
  return ROWS_TOP + index * (ROW_H + ROW_GAP);
}

export function rowBgProps(index) {
  return { x: ROW_X, y: rowY(index), w: ROW_W, h: ROW_H, radius: px(22), color: COLOR_ROW };
}

export function rowNameStyle(index) {
  return {
    x: ROW_X + px(22),
    y: rowY(index) + px(8),
    w: ROW_W - px(44),
    h: px(38),
    text: "",
    text_size: px(28),
    color: COLOR_WHITE,
    align_h: hmUI.align.LEFT,
    align_v: hmUI.align.CENTER_V,
    text_style: hmUI.text_style.ELLIPSIS,
  };
}

export function rowInfoStyle(index) {
  return {
    x: ROW_X + px(22),
    y: rowY(index) + px(44),
    w: ROW_W - px(44),
    h: px(30),
    text: "",
    text_size: px(20),
    color: COLOR_GREY,
    align_h: hmUI.align.LEFT,
    align_v: hmUI.align.CENTER_V,
    text_style: hmUI.text_style.ELLIPSIS,
  };
}

export function rowDistanceStyle(index) {
  return {
    x: ROW_X + ROW_W - px(170),
    y: rowY(index) + px(8),
    w: px(150),
    h: px(38),
    text: "",
    text_size: px(26),
    color: COLOR_ORANGE,
    align_h: hmUI.align.RIGHT,
    align_v: hmUI.align.CENTER_V,
    text_style: hmUI.text_style.NONE,
  };
}

export function bottomSpacerProps(y) {
  return { x: 0, y, w: DEVICE_WIDTH, h: px(110), color: 0x000000 };
}
