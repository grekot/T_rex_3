import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";
import { UI } from "../../../utils/geometry";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const COLOR_FLOOR = 0x1c150f;
export const COLOR_WALL = 0xd9a35f;
export const COLOR_TEXT = 0xffffff;
export const COLOR_TIME = 0xc8c8c8;
export const COLOR_GREEN = 0x5fd068;

// Współrzędne w utils/geometry.js są dla ekranu 480 x 480. Na innych zegarkach zeus
// skaluje grafikę w tej samej proporcji, więc pozycje też przeliczamy przez px().
export function scaled(rect) {
  return { x: px(rect.x), y: px(rect.y), w: px(rect.w), h: px(rect.h) };
}

// Obrazek o promieniu r ze środkiem w (x, y)
export function imageAt(x, y, r, src) {
  return { x: px(x - r), y: px(y - r), w: px(2 * r), h: px(2 * r), src };
}

export const FLOOR_PROPS = {
  center_x: px(UI.floor.cx),
  center_y: px(UI.floor.cy),
  radius: px(UI.floor.r),
  color: COLOR_FLOOR,
};

export function wallProps(w) {
  return { ...scaled(w), radius: px(2), color: COLOR_WALL };
}

const CENTERED = {
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

export const TITLE_STYLE = { ...CENTERED, ...scaled(UI.title), text: "", text_size: px(26), color: COLOR_TEXT };

export const TIME_STYLE = { ...CENTERED, ...scaled(UI.time), text: "", text_size: px(26), color: COLOR_TIME };

// Komunikat na środku (brak czujnika, błąd budowania ekranu)
export const MESSAGE_STYLE = {
  x: px(50),
  y: px(150),
  w: DEVICE_WIDTH - px(100),
  h: px(180),
  text: "",
  text_size: px(26),
  color: 0xff3d00,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.WRAP,
};
