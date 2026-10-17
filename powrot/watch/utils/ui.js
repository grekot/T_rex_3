// Wspólne kolory i przyciski (pomarańcz jak akcenty T-Rex 3).
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";

export const COLOR_WHITE = 0xffffff;
export const COLOR_GREY = 0x8a8a8a;
export const COLOR_ORANGE = 0xff9100;
export const COLOR_GREEN = 0x4caf50;
export const COLOR_RED = 0xef5350;
export const COLOR_ROW = 0x1c1c1c;

const KINDS = {
  primary: { normal_color: 0xe67e00, press_color: 0xb36200 },
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

export function wideRect(y, deviceWidth, h) {
  return { x: px(60), y, w: deviceWidth - px(120), h: h || px(64) };
}

// Siatka 2 kolumn przycisków (nazwy miejsc)
export function gridRect(index, top, deviceWidth) {
  const w = px(170);
  const h = px(58);
  const gap = px(12);
  const left = (deviceWidth - 2 * w - gap) / 2;
  return {
    x: left + (index % 2) * (w + gap),
    y: top + Math.floor(index / 2) * (h + gap),
    w,
    h,
  };
}
