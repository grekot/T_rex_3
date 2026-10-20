// Wspólne kolory i przyciski (pomarańcz jak akcenty T-Rex 3).
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";

export const COLOR_WHITE = 0xffffff;
export const COLOR_GREY = 0x8a8a8a;
export const COLOR_DIM = 0x5a5a5a;
export const COLOR_ORANGE = 0xff9100;
export const COLOR_GREEN = 0x4caf50;
export const COLOR_ROW = 0x1c1c1c;
export const COLOR_TRACK = 0x333333;

const KINDS = {
  primary: { normal_color: 0xe67e00, press_color: 0xb36200 },
  success: { normal_color: 0x2e7d32, press_color: 0x1b5e20 },
  secondary: { normal_color: 0x333333, press_color: 0x222222 },
  danger: { normal_color: 0xb71c1c, press_color: 0x7f0000 },
};

export function button(rect, text, kind, onClick, textSize) {
  return hmUI.createWidget(hmUI.widget.BUTTON, {
    ...rect,
    text,
    text_size: textSize || px(26),
    color: COLOR_WHITE,
    radius: Math.floor(rect.h / 2),
    ...(KINDS[kind] || KINDS.secondary),
    click_func: () => onClick(),
  });
}

export function setText(widget, style, text, color) {
  if (!widget) return;
  widget.setProperty(hmUI.prop.MORE, { ...style, text, color: color === undefined ? style.color : color });
}

export function onTap(widgets, handler) {
  widgets.forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, handler));
}

export function parseParams(params) {
  try {
    return typeof params === "string" ? JSON.parse(params) : params || {};
  } catch (e) {
    return {};
  }
}
