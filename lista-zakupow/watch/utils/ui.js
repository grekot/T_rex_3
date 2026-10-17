// Wspólne kolory i przyciski dla wszystkich ekranów zegarka.
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";

export const COLOR_WHITE = 0xffffff;
export const COLOR_GREY = 0x8a8a8a;
export const COLOR_DIM = 0x6a6a6a;
export const COLOR_GREEN = 0x4caf50;
export const COLOR_ORANGE = 0xff9100;
export const COLOR_RED = 0xef5350;
export const COLOR_ROW = 0x1c1c1c;
export const COLOR_ROW_DONE = 0x0f0f0f;

const BUTTON_KINDS = {
  primary: { normal_color: 0x2e7d32, press_color: 0x1b5e20 },
  secondary: { normal_color: 0x333333, press_color: 0x222222 },
  danger: { normal_color: 0xb71c1c, press_color: 0x7f0000 },
};

// Przycisk z efektem wciśnięcia (BUTTON z Zepp OS)
export function button(rect, text, kind, onClick) {
  return hmUI.createWidget(hmUI.widget.BUTTON, {
    ...rect,
    text,
    text_size: px(26),
    color: COLOR_WHITE,
    radius: Math.floor(rect.h / 2),
    ...(BUTTON_KINDS[kind] || BUTTON_KINDS.secondary),
    click_func: () => onClick(),
  });
}

// Dwa przyciski obok siebie w wierszu y (lewy, prawy)
export function pairRects(y, deviceWidth) {
  const h = px(58);
  const gap = px(12);
  const w = px(170);
  const left = (deviceWidth - 2 * w - gap) / 2;
  return [
    { x: left, y, w, h },
    { x: left + w + gap, y, w, h },
  ];
}

export function wideRect(y, deviceWidth) {
  return { x: px(60), y, w: deviceWidth - px(120), h: px(64) };
}
