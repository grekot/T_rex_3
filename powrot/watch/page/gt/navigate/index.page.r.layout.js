import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";
import { COLOR_WHITE, COLOR_GREY } from "../../../utils/ui";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const NAME_STYLE = {
  x: px(80),
  y: px(26),
  w: DEVICE_WIDTH - px(160),
  h: px(40),
  text: "",
  text_size: px(28),
  color: COLOR_WHITE,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.ELLIPSIS,
};

export const SAVED_STYLE = {
  x: px(90),
  y: px(64),
  w: DEVICE_WIDTH - px(180),
  h: px(28),
  text: "",
  text_size: px(20),
  color: COLOR_GREY,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

// Strzałka 180x180 obracana wokół swojego środka
const ARROW = px(180);
export const ARROW_PROPS = {
  x: (DEVICE_WIDTH - ARROW) / 2,
  y: px(96),
  w: ARROW,
  h: ARROW,
  center_x: ARROW / 2,
  center_y: ARROW / 2,
  src: "arrow.png",
  angle: 0,
};

export const DISTANCE_STYLE = {
  x: 0,
  y: px(282),
  w: DEVICE_WIDTH,
  h: px(70),
  text: "",
  text_size: px(56),
  color: COLOR_WHITE,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

export const DIRECTION_STYLE = {
  x: px(80),
  y: px(350),
  w: DEVICE_WIDTH - px(160),
  h: px(28),
  text: "",
  text_size: px(20),
  color: COLOR_GREY,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

export const HINT_STYLE = {
  x: px(100),
  y: px(376),
  w: DEVICE_WIDTH - px(200),
  h: px(44),
  text: "",
  text_size: px(18),
  color: COLOR_GREY,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.WRAP,
};

const DEL_W = px(160);
export const DELETE_RECT = { x: (DEVICE_WIDTH - DEL_W) / 2, y: px(424), w: DEL_W, h: px(40) };
