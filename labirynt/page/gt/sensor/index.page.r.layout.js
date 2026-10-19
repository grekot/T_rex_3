import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";
import { UI } from "../../../utils/geometry";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const COLOR_FLOOR = 0x1c150f;
export const COLOR_TEXT = 0xffffff;
export const COLOR_GREY = 0x8a8a8a;
export const COLOR_ORANGE = 0xff9100;
export const COLOR_BUTTON = 0x1f1f1f;

const CENTERED = {
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

export const ARENA = UI.arena;

export const ARENA_PROPS = {
  center_x: px(ARENA.cx),
  center_y: px(ARENA.cy),
  radius: px(ARENA.r),
  color: COLOR_FLOOR,
};

// Obrazek o promieniu r ze środkiem w (x, y)
export function imageAt(x, y, r, src) {
  return { x: px(x - r), y: px(y - r), w: px(2 * r), h: px(2 * r), src };
}

export const TITLE_STYLE = {
  ...CENTERED,
  x: px(140),
  y: px(14),
  w: px(200),
  h: px(36),
  text: "Czujnik",
  text_size: px(26),
  color: COLOR_TEXT,
};

// Surowe odczyty akcelerometru (cm/s^2) - do sprawdzenia, czy osie mają dobre znaki
export const RAW_STYLE = {
  ...CENTERED,
  x: px(80),
  y: px(50),
  w: px(320),
  h: px(34),
  text: "",
  text_size: px(20),
  color: COLOR_GREY,
};

function buttonRect(index) {
  return { x: px(124 + index * 120), y: px(396), w: px(112), h: px(54) };
}

export function buttonBg(index, on) {
  return { ...buttonRect(index), radius: px(16), color: on ? COLOR_ORANGE : COLOR_BUTTON };
}

export function buttonText(index, label, on) {
  return {
    ...buttonRect(index),
    align_h: hmUI.align.CENTER_H,
    align_v: hmUI.align.CENTER_V,
    text_style: hmUI.text_style.WRAP,
    text: label + "\n" + (on ? "odwrócone" : "normalnie"),
    text_size: px(19),
    color: COLOR_TEXT,
  };
}
