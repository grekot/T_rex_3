import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

// Paleta "zachód słońca" - pasuje do pomarańczowych akcentów T-Rex 3
export const COLOR_GOLD = 0xffd600;
export const COLOR_ORANGE = 0xff9100;
export const COLOR_RED = 0xff3d00;
export const COLOR_GREY = 0x8a8a8a;

// Gradient pierścienia: od góry (złoty) przez boki (pomarańcz) do dołu (czerwień) i z powrotem
export const RING_STOPS = [COLOR_GOLD, COLOR_ORANGE, COLOR_RED, COLOR_ORANGE, COLOR_GOLD];
export const RING_SEGMENTS = 72;

// Kąt 0° to godzina 3, więc -90° to góra tarczy
export const RING_STYLE = {
  x: px(14),
  y: px(14),
  w: DEVICE_WIDTH - px(28),
  h: DEVICE_HEIGHT - px(28),
  start_angle: -90,
  end_angle: 270,
  line_width: px(10),
};

export const INNER_RING_STYLE = {
  x: px(40),
  y: px(40),
  w: DEVICE_WIDTH - px(80),
  h: DEVICE_HEIGHT - px(80),
  start_angle: 0,
  end_angle: 360,
  line_width: px(2),
  color: 0x262626,
};

const NAME_Y = px(155);
const NAME_H = px(110);
const SHADOW_OFFSET = px(4);

const NAME_BASE = {
  x: 0,
  y: NAME_Y,
  w: DEVICE_WIDTH,
  h: NAME_H,
  text: "GREKOT",
  text_size: px(84),
  char_space: px(4),
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

// Cień przesunięty w prawo-dół daje efekt "3D"
export const NAME_SHADOW_STYLE = {
  ...NAME_BASE,
  x: SHADOW_OFFSET,
  y: NAME_Y + SHADOW_OFFSET,
  color: COLOR_RED,
};

export const NAME_STYLE = {
  ...NAME_BASE,
  color: 0xffffff,
};

const BAR_W = px(140);

export const BAR_STYLE = {
  x: (DEVICE_WIDTH - BAR_W) / 2,
  y: NAME_Y + NAME_H + px(8),
  w: BAR_W,
  h: px(5),
  radius: px(3),
  color: COLOR_ORANGE,
};

export const SUBTITLE_STYLE = {
  x: 0,
  y: NAME_Y + NAME_H + px(26),
  w: DEVICE_WIDTH,
  h: px(36),
  text: "T-REX 3",
  text_size: px(26),
  char_space: px(8),
  color: COLOR_GREY,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};
