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

export const TITLE_STYLE = text(px(90), px(28), DEVICE_WIDTH - px(180), px(32), px(22), COLOR_ORANGE, {
  text: "KORONA",
  char_space: px(2),
});
export const COUNT_STYLE = text(0, px(58), DEVICE_WIDTH, px(76), px(64), COLOR_WHITE);
export const COUNT_SUB_STYLE = text(px(80), px(130), DEVICE_WIDTH - px(160), px(28), px(20), COLOR_GREY);

// Karta stanu: GPS / najbliższy / „Jesteś na szczycie”
const CARD_X = px(50);
const CARD_W = DEVICE_WIDTH - px(100);
export const CARD_BG = { x: CARD_X, y: px(168), w: CARD_W, h: px(118), radius: px(26), color: COLOR_ROW };
export const CARD_LINE1 = text(CARD_X + px(20), px(176), CARD_W - px(40), px(48), px(28), COLOR_WHITE, {
  text_style: hmUI.text_style.ELLIPSIS,
});
export const CARD_LINE2 = text(CARD_X + px(20), px(222), CARD_W - px(40), px(56), px(20), COLOR_GREY, {
  text_style: hmUI.text_style.WRAP,
});

const ACTION_W = px(260);
export const ACTION_RECT = { x: (DEVICE_WIDTH - ACTION_W) / 2, y: px(298), w: ACTION_W, h: px(62) };

// Listy (strona przewija się w dół)
const ROW_X = px(46);
const ROW_W = DEVICE_WIDTH - px(92);
const ROW_H = px(72);
const ROW_STEP = px(80);
const LIST_TOP = px(384);

export function rowY(index) {
  return LIST_TOP + index * ROW_STEP;
}

export function rowBg(y) {
  return { x: ROW_X, y, w: ROW_W, h: ROW_H, radius: px(20), color: COLOR_ROW };
}

export function rowName(y) {
  return text(ROW_X + px(24), y + px(4), ROW_W - px(24) - px(120), px(50), px(26), COLOR_WHITE, {
    align_h: hmUI.align.LEFT,
    text_style: hmUI.text_style.ELLIPSIS,
  });
}

export function rowCount(y) {
  return text(ROW_X + ROW_W - px(140), y + px(4), px(118), px(50), px(24), COLOR_GREY, { align_h: hmUI.align.RIGHT });
}

const BAR_X = ROW_X + px(24);
const BAR_W = ROW_W - px(48);
export function rowBarTrack(y) {
  return { x: BAR_X, y: y + ROW_H - px(16), w: BAR_W, h: px(6), radius: px(3), color: COLOR_TRACK };
}

export function rowBarFill(y, done, total) {
  const w = total ? Math.max(px(6), Math.round((BAR_W * done) / total)) : 0;
  return { ...rowBarTrack(y), w: Math.max(px(6), w), color: COLOR_ORANGE };
}

export function addRect(y) {
  const w = px(300);
  return { x: (DEVICE_WIDTH - w) / 2, y, w, h: px(60) };
}

export function syncStyle(y) {
  return text(px(70), y, DEVICE_WIDTH - px(140), px(52), px(18), COLOR_GREY, { text_style: hmUI.text_style.WRAP });
}

// Niewidoczny odstęp na końcu, żeby ostatni wiersz dało się przewinąć wyżej
export function bottomSpacer(y) {
  return { x: 0, y, w: DEVICE_WIDTH, h: px(110), color: 0x000000 };
}
