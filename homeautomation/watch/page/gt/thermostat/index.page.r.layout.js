import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const COLOR_TEXT = 0xffffff;
export const COLOR_GREY = 0x8a8a8a;
export const COLOR_ORANGE = 0xff9100;
export const COLOR_RED = 0xff5252;
export const COLOR_PILL = 0x262626;
export const COLOR_PILL_DOWN = 0x404040;
export const COLOR_ACTIVE = 0xe67e00;

const CX = DEVICE_WIDTH / 2;

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

// Nazwa termostatu (przy kilku: stuknięcie = następny)
export const NAME_STYLE = text(px(90), px(30), DEVICE_WIDTH - px(180), px(36), px(24), COLOR_ORANGE, {
  text_style: hmUI.text_style.ELLIPSIS,
});
// Ostrzeżenie: Brak kontaktu / Awaria czujnika / wyłączony
export const ALERT_STYLE = text(px(60), px(68), DEVICE_WIDTH - px(120), px(34), px(26), COLOR_RED, {
  text_style: hmUI.text_style.ELLIPSIS,
});

// Temperatura w pokoju
export const TEMP_STYLE = text(px(60), px(100), DEVICE_WIDTH - px(120), px(110), px(100), COLOR_TEXT);
export const FLAME_IMG = { x: px(372), y: px(126), w: px(48), h: px(60), src: "flame.png" };
export const OUTDOOR_STYLE = text(px(80), px(206), DEVICE_WIDTH - px(160), px(30), px(22), COLOR_GREY);

// Nastawa: − 21,5° +
const BTN_Y = px(288);
const BTN_R = px(42);
function roundButton(cx, label) {
  return {
    circle: { center_x: cx, center_y: BTN_Y, radius: BTN_R, color: COLOR_PILL },
    text: text(cx - BTN_R, BTN_Y - BTN_R, BTN_R * 2, BTN_R * 2, px(56), COLOR_ORANGE, { text: label }),
  };
}
export const MINUS_BTN = roundButton(px(112), "−");
export const PLUS_BTN = roundButton(DEVICE_WIDTH - px(112), "+");
export const TARGET_LABEL_STYLE = text(CX - px(80), px(240), px(160), px(24), px(18), COLOR_GREY, { text: "nastawa" });
export const TARGET_STYLE = text(CX - px(86), px(260), px(172), px(64), px(58), COLOR_ORANGE);

// Tryb: dwa segmenty RĘCZNY | AUTO
const SEG_W = px(140);
const SEG_H = px(52);
const SEG_Y = px(340);
const SEG_X = CX - SEG_W;
export const MODE_BG = { x: SEG_X, y: SEG_Y, w: SEG_W * 2, h: SEG_H, radius: SEG_H / 2, color: COLOR_PILL };
export function modeSegment(index) {
  return { x: SEG_X + index * SEG_W, y: SEG_Y, w: SEG_W, h: SEG_H, radius: SEG_H / 2, color: COLOR_ACTIVE };
}
export function modeText(index, label) {
  return text(SEG_X + index * SEG_W, SEG_Y, SEG_W, SEG_H, px(22), COLOR_TEXT, { text: label });
}
// AUTO: „komfort do 22:30” / „nadpisane do 22:30”
export const INFO_STYLE = text(px(100), px(398), DEVICE_WIDTH - px(200), px(28), px(20), COLOR_GREY);
// Wysyłanie / telefon niedostępny
export const MSG_STYLE = text(px(130), px(426), DEVICE_WIDTH - px(260), px(26), px(18), COLOR_GREY, {
  text_style: hmUI.text_style.ELLIPSIS,
});

// Ekran bez danych: logowanie, brak konfiguracji, łączenie...
export const CENTER_STYLE = text(px(60), px(120), DEVICE_WIDTH - px(120), px(240), px(28), COLOR_TEXT, {
  text_style: hmUI.text_style.WRAP,
});
