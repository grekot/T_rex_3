import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";
import { COLOR_WHITE, COLOR_ORANGE } from "../../../utils/ui";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

// --- Panel: przyciski i wyniki pomiarów ---

export const TITLE_STYLE = {
  x: 0,
  y: px(26),
  w: DEVICE_WIDTH,
  h: px(40),
  text: "ZDJĘCIA",
  text_size: px(30),
  char_space: px(2),
  color: COLOR_ORANGE,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

export const STATUS_STYLE = {
  x: px(52),
  y: px(70),
  w: DEVICE_WIDTH - px(104),
  h: px(178),
  text: "",
  text_size: px(19),
  color: COLOR_WHITE,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.WRAP,
};

export const SYNC_RECT = { x: px(60), y: px(254), w: DEVICE_WIDTH - px(120), h: px(60) };
export const SHOW_RECT = { x: px(80), y: px(322), w: DEVICE_WIDTH - px(160), h: px(56) };
export const TEST_RECT = { x: px(108), y: px(386), w: px(127), h: px(50) };
export const CLEAR_RECT = { x: px(245), y: px(386), w: px(127), h: px(50) };

// --- Podgląd zdjęcia: pełny ekran + pasek z pomiarami ---

export const PHOTO_PROPS = { x: 0, y: 0, w: DEVICE_WIDTH, h: DEVICE_HEIGHT };

export const BACK_RECT = { x: px(108), y: px(40), w: px(125), h: px(46) };
export const VARIANT_RECT = { x: px(247), y: px(40), w: px(125), h: px(46) };

export const INFO_BG_PROPS = {
  x: px(80),
  y: px(326),
  w: DEVICE_WIDTH - px(160),
  h: px(90),
  radius: px(16),
  color: 0x000000,
};

export const INFO_STYLE = {
  x: px(86),
  y: px(329),
  w: DEVICE_WIDTH - px(172),
  h: px(84),
  text: "",
  text_size: px(17),
  color: COLOR_WHITE,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.WRAP,
};
