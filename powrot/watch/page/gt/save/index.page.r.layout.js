import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";
import { COLOR_GREY, COLOR_ORANGE } from "../../../utils/ui";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const TITLE_STYLE = {
  x: 0,
  y: px(24),
  w: DEVICE_WIDTH,
  h: px(40),
  text: "ZAPISZ MIEJSCE",
  text_size: px(26),
  char_space: px(1),
  color: COLOR_ORANGE,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

export const STATUS_STYLE = {
  x: px(70),
  y: px(64),
  w: DEVICE_WIDTH - px(140),
  h: px(56),
  text: "",
  text_size: px(22),
  color: COLOR_GREY,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.WRAP,
};

export const GRID_TOP = px(128);

export function bottomSpacerProps(y) {
  return { x: 0, y, w: DEVICE_WIDTH, h: px(110), color: 0x000000 };
}
