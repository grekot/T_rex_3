import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";
import { COLOR_WHITE, COLOR_GREY } from "../../../utils/ui";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

const text = (x, y, w, h, size, color, extra) => ({
  x,
  y,
  w,
  h,
  text: "",
  text_size: size,
  color,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
  ...(extra || {}),
});

export const NAME_STYLE = text(px(80), px(26), DEVICE_WIDTH - px(160), px(42), px(30), COLOR_WHITE, {
  text_style: hmUI.text_style.ELLIPSIS,
});
export const LINE_STYLE = text(px(80), px(66), DEVICE_WIDTH - px(160), px(28), px(20), COLOR_GREY, {
  text_style: hmUI.text_style.ELLIPSIS,
});

// Strzałka 180x180 obracana wokół swojego środka
const ARROW = px(180);
export const ARROW_PROPS = {
  x: (DEVICE_WIDTH - ARROW) / 2,
  y: px(98),
  w: ARROW,
  h: ARROW,
  center_x: ARROW / 2,
  center_y: ARROW / 2,
  src: "arrow.png",
  angle: 0,
};

// Poprzedni / następny szczyt po bokach strzałki
const SIDE = px(64);
export const PREV_RECT = { x: px(30), y: px(156), w: SIDE, h: SIDE };
export const NEXT_RECT = { x: DEVICE_WIDTH - px(30) - SIDE, y: px(156), w: SIDE, h: SIDE };
export const INDEX_STYLE = text(px(20), px(222), px(100), px(26), px(18), COLOR_GREY);

export const DISTANCE_STYLE = text(0, px(282), DEVICE_WIDTH, px(66), px(54), COLOR_WHITE);
export const DIRECTION_STYLE = text(px(80), px(346), DEVICE_WIDTH - px(160), px(28), px(20), COLOR_GREY);
export const HINT_STYLE = text(px(90), px(370), DEVICE_WIDTH - px(180), px(38), px(18), COLOR_GREY, {
  text_style: hmUI.text_style.WRAP,
});

const BTN_W = px(200);
export const BUTTON_RECT = { x: (DEVICE_WIDTH - BTN_W) / 2, y: px(408), w: BTN_W, h: px(46) };
