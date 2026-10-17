import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const COLOR_TEXT = 0xffffff;
export const COLOR_GREY = 0x8a8a8a;
export const COLOR_CELL = 0x1f1f1f;
export const COLOR_X = 0xff9100;
export const COLOR_O = 0x00e5ff;
// Przyciemnione wersje kolorów do podświetlenia wygrywającej linii
export const COLOR_X_WIN = 0x4d2b00;
export const COLOR_O_WIN = 0x00424d;

export const CELL = px(90);
export const GAP = px(8);
export const BOARD = CELL * 3 + GAP * 2;
export const BOARD_X = (DEVICE_WIDTH - BOARD) / 2;
export const BOARD_Y = px(92);

// Prostokąt pola o indeksie 0..8 (wiersz po wierszu)
export function cellRect(index) {
  const col = index % 3;
  const row = Math.floor(index / 3);
  return {
    x: BOARD_X + col * (CELL + GAP),
    y: BOARD_Y + row * (CELL + GAP),
    w: CELL,
    h: CELL,
  };
}

export const CELL_STYLE = {
  radius: px(14),
  color: COLOR_CELL,
};

const CENTERED = {
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

export const MARK_STYLE = {
  ...CENTERED,
  text: "",
  text_size: px(64),
  color: COLOR_TEXT,
};

export const SCORE_STYLE = {
  ...CENTERED,
  x: 0,
  y: px(34),
  w: DEVICE_WIDTH,
  h: px(40),
  text: "",
  text_size: px(26),
  char_space: px(1),
  color: COLOR_TEXT,
};

export const STATUS_STYLE = {
  ...CENTERED,
  x: 0,
  y: BOARD_Y + BOARD + px(10),
  w: DEVICE_WIDTH,
  h: px(40),
  text: "",
  text_size: px(28),
  color: COLOR_TEXT,
};

// Komunikat awaryjny, gdy budowanie ekranu się nie powiedzie
export const ERROR_STYLE = {
  x: px(40),
  y: px(120),
  w: DEVICE_WIDTH - px(80),
  h: px(240),
  text: "",
  text_size: px(24),
  color: 0xff3d00,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.WRAP,
};

export const HINT_STYLE = {
  ...CENTERED,
  x: 0,
  y: BOARD_Y + BOARD + px(50),
  w: DEVICE_WIDTH,
  h: px(30),
  text: "",
  text_size: px(20),
  color: COLOR_GREY,
};
