import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const COLOR_TEXT = 0xffffff;
export const COLOR_GREY = 0x8a8a8a;
export const COLOR_ORANGE = 0xff9100;
export const COLOR_ROW = 0x1f1f1f;
export const COLOR_PLAY = 0xe67e00;

const CX = DEVICE_WIDTH / 2;

const CENTERED = {
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

// Kulka po lewej od napisu LABIRYNT
export const TITLE_ICON = { x: CX - px(110), y: px(36), src: "ui/ball_menu.png" };

export const TITLE_STYLE = {
  ...CENTERED,
  x: CX - px(82),
  y: px(30),
  w: px(200),
  h: px(48),
  text: "LABIRYNT",
  text_size: px(34),
  color: COLOR_TEXT,
};

// Przyciski: [graj od zapisanego poziomu, od poziomu 1, test czujnika]
const BUTTONS = [
  { y: 98, h: 64, size: 28 },
  { y: 174, h: 56, size: 26 },
  { y: 242, h: 56, size: 26 },
];

function buttonRect(index) {
  const b = BUTTONS[index];
  return { x: CX - px(150), y: px(b.y), w: px(300), h: px(b.h) };
}

export function buttonBg(index) {
  const r = buttonRect(index);
  return { ...r, radius: Math.floor(r.h / 2), color: index === 0 ? COLOR_PLAY : COLOR_ROW };
}

export function buttonText(index, text) {
  return { ...CENTERED, ...buttonRect(index), text, text_size: px(BUTTONS[index].size), color: COLOR_TEXT };
}

export const RECORD_STYLE = {
  ...CENTERED,
  x: px(60),
  y: px(312),
  w: DEVICE_WIDTH - px(120),
  h: px(36),
  text: "",
  text_size: px(24),
  color: COLOR_ORANGE,
};

export const TIP_STYLE = {
  ...CENTERED,
  text_style: hmUI.text_style.WRAP,
  x: px(80),
  y: px(356),
  w: DEVICE_WIDTH - px(160),
  h: px(60),
  text: "stuknij ekran w grze =\nwyzeruj pochylenie",
  text_size: px(21),
  color: COLOR_GREY,
};
