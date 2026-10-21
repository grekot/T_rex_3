import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";
import { COLOR_WHITE, COLOR_GREY, COLOR_ROW } from "../../../utils/ui";

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

export const TITLE_STYLE = text(px(80), px(34), DEVICE_WIDTH - px(160), px(32), px(22), COLOR_GREY, {
  text: "Nowy szczyt",
});

// Nazwa w ramce - stuknięcie otwiera klawiaturę (gdy zegarek ją ma)
const NAME_W = px(340);
export const NAME_BG = { x: (DEVICE_WIDTH - NAME_W) / 2, y: px(72), w: NAME_W, h: px(64), radius: px(20), color: COLOR_ROW };
export const NAME_STYLE = text((DEVICE_WIDTH - NAME_W) / 2 + px(14), px(72), NAME_W - px(28), px(64), px(30), COLOR_WHITE, {
  text_style: hmUI.text_style.ELLIPSIS,
});
export const NAME_HINT_STYLE = text(px(70), px(138), DEVICE_WIDTH - px(140), px(26), px(17), COLOR_GREY);

export const POS_STYLE = text(px(50), px(174), DEVICE_WIDTH - px(100), px(34), px(22), COLOR_WHITE);
export const INFO_STYLE = text(px(56), px(210), DEVICE_WIDTH - px(112), px(84), px(19), COLOR_GREY, {
  text_style: hmUI.text_style.WRAP,
});

const B1_W = px(300);
const B2_W = px(240);
export const SAVE_RECT = { x: (DEVICE_WIDTH - B1_W) / 2, y: px(304), w: B1_W, h: px(62) };
export const OTHER_RECT = { x: (DEVICE_WIDTH - B2_W) / 2, y: px(378), w: B2_W, h: px(54) };
