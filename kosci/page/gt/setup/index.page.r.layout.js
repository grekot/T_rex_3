import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const COLOR_TEXT = 0xffffff;
export const COLOR_GREY = 0x8a8a8a;
export const COLOR_PILL = 0x262626;
export const COLOR_SELECTED = 0xe67e00;

const CX = DEVICE_WIDTH / 2;

const CENTERED = {
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

function label(y, text) {
  return { ...CENTERED, x: px(90), y: px(y), w: DEVICE_WIDTH - px(180), h: px(28), text, text_size: px(22), color: COLOR_GREY };
}

export const TITLE_STYLE = { ...CENTERED, x: px(90), y: px(22), w: DEVICE_WIDTH - px(180), h: px(40), text: "Kości", text_size: px(32), color: COLOR_TEXT };

export const COUNT_LABEL = label(66, "Liczba kości");

// Rząd "−  3  +"
const COUNT_Y = px(96);
const STEP = px(58);
export const MINUS_BG = { x: CX - px(130), y: COUNT_Y, w: STEP, h: STEP, radius: STEP / 2, color: COLOR_PILL };
export const PLUS_BG = { x: CX + px(130) - STEP, y: COUNT_Y, w: STEP, h: STEP, radius: STEP / 2, color: COLOR_PILL };
export const MINUS_STYLE = { ...CENTERED, ...MINUS_BG, text: "−", text_size: px(36), color: COLOR_TEXT };
export const PLUS_STYLE = { ...CENTERED, ...PLUS_BG, text: "+", text_size: px(36), color: COLOR_TEXT };
export const COUNT_STYLE = { ...CENTERED, x: CX - px(60), y: COUNT_Y, w: px(120), h: STEP, text: "", text_size: px(44), color: COLOR_TEXT };

export const TYPE_LABEL = label(166, "Rodzaj");

// Rodzaje kości: 2 rzędy po 3
export function typeRect(index) {
  const col = index % 3;
  const row = Math.floor(index / 3);
  return { x: CX - px(162) + col * px(112), y: px(196) + row * px(64), w: px(100), h: px(54) };
}

export function typeBg(index, selected) {
  return { ...typeRect(index), radius: px(27), color: selected ? COLOR_SELECTED : COLOR_PILL };
}

export function typeStyle(index, text) {
  return { ...CENTERED, ...typeRect(index), text, text_size: px(26), color: COLOR_TEXT };
}

const SHAKE_RECT = { x: CX - px(140), y: px(330), w: px(280), h: px(50) };
export function shakeBg(on) {
  return { ...SHAKE_RECT, radius: px(25), color: on ? COLOR_SELECTED : COLOR_PILL };
}
export function shakeStyle(on) {
  return { ...CENTERED, ...SHAKE_RECT, text: "Potrząśnij = rzut: " + (on ? "TAK" : "NIE"), text_size: px(22), color: COLOR_TEXT };
}

const DONE_RECT = { x: CX - px(80), y: px(394), w: px(160), h: px(46) };
export const DONE_BG = { ...DONE_RECT, radius: px(23), color: COLOR_PILL };
export const DONE_STYLE = { ...CENTERED, ...DONE_RECT, text: "Gotowe", text_size: px(24), color: COLOR_TEXT };
