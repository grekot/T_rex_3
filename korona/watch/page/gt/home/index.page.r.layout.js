import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";
import { COLOR_WHITE, COLOR_GREY, COLOR_ORANGE, COLOR_ROW, COLOR_TRACK } from "../../../utils/ui";

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

export const TITLE_STYLE = text(px(90), px(30), DEVICE_WIDTH - px(180), px(32), px(22), COLOR_ORANGE, {
  text: "KORONA GÓR POLSKI",
  char_space: px(1),
});

export const COUNT_STYLE = text(0, px(62), DEVICE_WIDTH, px(76), px(64), COLOR_WHITE);

// Pasek postępu
const BAR_W = px(240);
export const BAR_TRACK = { x: (DEVICE_WIDTH - BAR_W) / 2, y: px(144), w: BAR_W, h: px(10), radius: px(5), color: COLOR_TRACK };
export function barFill(done, total) {
  const w = Math.max(px(10), Math.round((BAR_W * done) / Math.max(1, total)));
  return { ...BAR_TRACK, w, color: COLOR_ORANGE };
}

// Karta stanu: GPS / najbliższy / „Jesteś na szczycie”
const CARD_X = px(50);
const CARD_W = DEVICE_WIDTH - px(100);
export const CARD_BG = { x: CARD_X, y: px(170), w: CARD_W, h: px(118), radius: px(26), color: COLOR_ROW };
export const CARD_LINE1 = text(CARD_X + px(20), px(178), CARD_W - px(40), px(48), px(28), COLOR_WHITE, {
  text_style: hmUI.text_style.ELLIPSIS,
});
export const CARD_LINE2 = text(CARD_X + px(20), px(224), CARD_W - px(40), px(56), px(20), COLOR_GREY, {
  text_style: hmUI.text_style.WRAP,
});

const ACTION_W = px(260);
export const ACTION_RECT = { x: (DEVICE_WIDTH - ACTION_W) / 2, y: px(300), w: ACTION_W, h: px(62) };

// Lista szczytów (strona przewija się w dół)
const ROW_X = px(46);
const ROW_W = DEVICE_WIDTH - px(92);
const ROW_H = px(70);
const ROW_STEP = px(78);
const LIST_TOP = px(424);
const HEADER_H = px(44);
// Warianty mają własny nagłówek po 28 wierszach
const VARIANTS_GAP = HEADER_H + px(10);

export const LIST_HEADER_STYLE = text(px(60), LIST_TOP - HEADER_H - px(4), DEVICE_WIDTH - px(120), HEADER_H, px(20), COLOR_GREY, {
  text: "Szczyty · stuknij po szczegóły",
});

export function rowY(index, officialCount) {
  return LIST_TOP + index * ROW_STEP + (index >= officialCount ? VARIANTS_GAP : 0);
}

export function variantsHeaderStyle(officialCount) {
  return text(px(60), rowY(officialCount, officialCount) - HEADER_H - px(4), DEVICE_WIDTH - px(120), HEADER_H, px(20), COLOR_GREY, {
    text: "Warianty (nie liczą się do 28)",
  });
}

export function rowBg(y) {
  return { x: ROW_X, y, w: ROW_W, h: ROW_H, radius: px(20), color: COLOR_ROW };
}

export function rowDot(y) {
  return { center_x: ROW_X + px(28), center_y: y + ROW_H / 2, radius: px(9), color: COLOR_TRACK };
}

export function rowName(y) {
  return text(ROW_X + px(48), y, ROW_W - px(48) - px(140), ROW_H, px(26), COLOR_WHITE, {
    align_h: hmUI.align.LEFT,
    text_style: hmUI.text_style.ELLIPSIS,
  });
}

export function rowRight(y) {
  return text(ROW_X + ROW_W - px(146), y, px(130), ROW_H, px(20), COLOR_GREY, { align_h: hmUI.align.RIGHT });
}

// Niewidoczny odstęp na końcu, żeby ostatni wiersz dało się przewinąć wyżej
export function bottomSpacer(y) {
  return { x: 0, y, w: DEVICE_WIDTH, h: px(120), color: 0x000000 };
}
