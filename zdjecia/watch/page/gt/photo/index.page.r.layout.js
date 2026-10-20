import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";
import { COLOR_WHITE, COLOR_GREY } from "../../../utils/ui";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const PHOTO_PROPS = { x: 0, y: 0, w: DEVICE_WIDTH, h: DEVICE_HEIGHT };

export const INFO_BG_PROPS = {
  x: px(110),
  y: px(382),
  w: DEVICE_WIDTH - px(220),
  h: px(62),
  radius: px(31),
  color: 0x000000,
};

export const INFO_STYLE = {
  x: px(110),
  y: px(382),
  w: DEVICE_WIDTH - px(220),
  h: px(62),
  text: "",
  text_size: px(19),
  color: COLOR_WHITE,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.WRAP,
};

export const EMPTY_STYLE = {
  x: px(60),
  y: px(140),
  w: DEVICE_WIDTH - px(120),
  h: px(200),
  text: "",
  text_size: px(24),
  color: COLOR_GREY,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.WRAP,
};
