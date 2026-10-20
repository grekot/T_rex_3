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

export const TITLE_STYLE = text(px(80), px(34), DEVICE_WIDTH - px(160), px(32), px(22), COLOR_GREY, {
  text: "Data zdobycia",
});
export const NAME_STYLE = text(px(70), px(64), DEVICE_WIDTH - px(140), px(42), px(30), COLOR_WHITE, {
  text_style: hmUI.text_style.ELLIPSIS,
});

// Trzy kolumny: dzień, miesiąc, rok - każda z „+”, wartością i „−”
const COL_W = px(104);
const COL_GAP = px(14);
const COLS_X = (DEVICE_WIDTH - 3 * COL_W - 2 * COL_GAP) / 2;
const FIELDS = ["d", "m", "y"];
const LABELS = { d: "dzień", m: "miesiąc", y: "rok" };

export function colX(field) {
  return COLS_X + FIELDS.indexOf(field) * (COL_W + COL_GAP);
}

export function labelStyle(field) {
  return text(colX(field), px(112), COL_W, px(26), px(18), COLOR_GREY, { text: LABELS[field] });
}

export function plusRect(field) {
  return { x: colX(field), y: px(140), w: COL_W, h: px(56) };
}

export function valueStyle(field) {
  return text(colX(field) - px(10), px(200), COL_W + px(20), px(62), field === "y" ? px(36) : px(44), COLOR_WHITE);
}

export function minusRect(field) {
  return { x: colX(field), y: px(266), w: COL_W, h: px(56) };
}

export const WEEKDAY_STYLE = text(px(80), px(326), DEVICE_WIDTH - px(160), px(28), px(18), COLOR_GREY);

const SAVE_W = px(240);
export const SAVE_RECT = { x: (DEVICE_WIDTH - SAVE_W) / 2, y: px(362), w: SAVE_W, h: px(60) };

export { FIELDS };
