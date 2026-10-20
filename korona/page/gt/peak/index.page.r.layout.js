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

export const NAME_STYLE = text(px(70), px(34), DEVICE_WIDTH - px(140), px(50), px(36), COLOR_WHITE, {
  text_style: hmUI.text_style.ELLIPSIS,
});
export const LINE_STYLE = text(px(60), px(84), DEVICE_WIDTH - px(120), px(32), px(22), COLOR_GREY);
export const NOTE_STYLE = text(px(70), px(116), DEVICE_WIDTH - px(140), px(48), px(18), COLOR_GREY, {
  text_style: hmUI.text_style.WRAP,
});
export const STATUS_STYLE = text(0, px(166), DEVICE_WIDTH, px(54), px(34), COLOR_WHITE);
export const SUB_STYLE = text(px(60), px(216), DEVICE_WIDTH - px(120), px(28), px(18), COLOR_GREY);
export const GPS_STYLE = text(px(50), px(246), DEVICE_WIDTH - px(100), px(34), px(22), COLOR_GREY, {
  text_style: hmUI.text_style.ELLIPSIS,
});

const B1_W = px(300);
const B2_W = px(260);
export const BUTTON1_RECT = { x: (DEVICE_WIDTH - B1_W) / 2, y: px(294), w: B1_W, h: px(60) };
export const BUTTON2_RECT = { x: (DEVICE_WIDTH - B2_W) / 2, y: px(366), w: B2_W, h: px(56) };
