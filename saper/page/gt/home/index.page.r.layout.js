import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const COLOR_TEXT = 0xffffff;
export const COLOR_GREY = 0x8a8a8a;
export const COLOR_ORANGE = 0xff9100;
export const COLOR_ROW = 0x1f1f1f;
export const COLOR_CONTINUE = 0xe67e00;

const CX = DEVICE_WIDTH / 2;

const CENTERED = {
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

// Ikona miny po lewej od napisu SAPER
export const TITLE_ICON = { x: CX - px(90), y: px(34), src: "ui/icon_mine_big.png" };

export const TITLE_STYLE = {
  ...CENTERED,
  x: CX - px(68),
  y: px(30),
  w: px(180),
  h: px(48),
  text: "SAPER",
  text_size: px(36),
  color: COLOR_TEXT,
};

const CONTINUE_RECT = { x: CX - px(130), y: px(92), w: px(260), h: px(54) };

export const CONTINUE_BG = { ...CONTINUE_RECT, radius: px(27), color: COLOR_CONTINUE };

export const CONTINUE_STYLE = { ...CENTERED, ...CONTINUE_RECT, text: "", text_size: px(24), color: COLOR_TEXT };

// Pokazywany zamiast "Kontynuuj", gdy nie ma przerwanej partii
export const PICK_STYLE = { ...CONTINUE_STYLE, text: "Wybierz poziom", color: COLOR_GREY };

function rowRect(index) {
  return { x: CX - px(170), y: px(160) + index * px(74), w: px(340), h: px(64) };
}

export function rowBg(index) {
  return { ...rowRect(index), radius: px(32), color: COLOR_ROW };
}

export function rowNameStyle(index) {
  const r = rowRect(index);
  return {
    ...CENTERED,
    align_h: hmUI.align.LEFT,
    x: r.x + px(30),
    y: r.y,
    w: px(200),
    h: r.h,
    text: "",
    text_size: px(28),
    color: COLOR_TEXT,
  };
}

export function rowRecordStyle(index) {
  const r = rowRect(index);
  return {
    ...CENTERED,
    align_h: hmUI.align.RIGHT,
    x: r.x + r.w - px(28) - px(120),
    y: r.y,
    w: px(120),
    h: r.h,
    text: "",
    text_size: px(26),
    color: COLOR_GREY,
  };
}

export const TIP_STYLE = {
  ...CENTERED,
  x: px(60),
  y: px(384),
  w: DEVICE_WIDTH - px(120),
  h: px(40),
  text: "przytrzymaj pole = flaga",
  text_size: px(22),
  color: COLOR_GREY,
};
