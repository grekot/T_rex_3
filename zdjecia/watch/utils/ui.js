// Wspólne kolory i przyciski (pomarańcz jak akcenty T-Rex 3).
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";

export const COLOR_WHITE = 0xffffff;
export const COLOR_GREY = 0x8a8a8a;
export const COLOR_ORANGE = 0xff9100;

const KINDS = {
  primary: { normal_color: 0xe67e00, press_color: 0xb36200 },
  secondary: { normal_color: 0x333333, press_color: 0x222222 },
  danger: { normal_color: 0xb71c1c, press_color: 0x7f0000 },
};

export function buttonProps(rect, text, kind, onClick, textSize) {
  return {
    ...rect,
    text,
    text_size: textSize || px(26),
    color: COLOR_WHITE,
    radius: Math.floor(rect.h / 2),
    ...(KINDS[kind] || KINDS.secondary),
    click_func: () => onClick(),
  };
}
