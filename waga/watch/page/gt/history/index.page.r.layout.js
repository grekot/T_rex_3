import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const COLOR_TEXT = 0xffffff;
export const COLOR_GREY = 0x8a8a8a;
export const COLOR_ORANGE = 0xff9100;
export const COLOR_GREEN = 0x4caf50;
export const COLOR_RED = 0xef5350;
export const COLOR_LINE = 0x262626;

const CX = DEVICE_WIDTH / 2;

const CENTERED = {
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

export const TITLE_STYLE = {
  ...CENTERED,
  x: CX - px(120),
  y: px(30),
  w: px(240),
  h: px(40),
  text: "Historia",
  text_size: px(32),
  color: COLOR_ORANGE,
};

export function summaryStyle(i, text) {
  return { ...CENTERED, x: CX - px(170), y: px(74) + i * px(30), w: px(340), h: px(30), text, text_size: px(22), color: COLOR_GREY };
}

export const ROWS_TOP = px(146);
export const ROW_H = px(50);
const ROW_X = CX - px(165);
const ROW_W = px(330);

export function rowStyles(i) {
  const y = ROWS_TOP + i * ROW_H;
  const base = { align_v: hmUI.align.CENTER_V, text_style: hmUI.text_style.NONE, y, h: ROW_H };
  return {
    line: { x: ROW_X, y: y + ROW_H - 1, w: ROW_W, h: 1, color: COLOR_LINE },
    date: { ...base, align_h: hmUI.align.LEFT, x: ROW_X, w: px(120), text_size: px(24), color: COLOR_GREY },
    weight: { ...base, align_h: hmUI.align.RIGHT, x: ROW_X + px(110), w: px(110), text_size: px(28), color: COLOR_TEXT },
    delta: { ...base, align_h: hmUI.align.RIGHT, x: ROW_X + px(225), w: px(105), text_size: px(22), color: COLOR_GREY },
  };
}

export const EMPTY_STYLE = summaryStyle(2, "Brak pomiarów");

// Odstęp na dole, żeby ostatni wiersz dało się przewinąć nad krawędź okrągłego ekranu
export function bottomSpacer(rows) {
  return { x: 0, y: ROWS_TOP + rows * ROW_H, w: DEVICE_WIDTH, h: px(120), color: 0x000000 };
}
