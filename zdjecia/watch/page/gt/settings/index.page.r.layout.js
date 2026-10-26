import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";
import { COLOR_WHITE, COLOR_GREY, COLOR_ORANGE } from "../../../utils/ui";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

const CENTERED = {
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

export const TITLE_STYLE = {
  ...CENTERED,
  x: 0,
  y: px(26),
  w: DEVICE_WIDTH,
  h: px(40),
  text: "LOSOWE ZDJĘCIA",
  text_size: px(28),
  char_space: px(1),
  color: COLOR_ORANGE,
};

// Włącz/wyłącz: tło + napis, kolor zmieniany przez prop.MORE (jak przełączniki w Labiryncie)
const TOGGLE_RECT = { x: px(110), y: px(76), w: DEVICE_WIDTH - px(220), h: px(56) };

export function toggleBg(on) {
  return { ...TOGGLE_RECT, radius: px(28), color: on ? 0xe67e00 : 0x333333 };
}

export function toggleText(on) {
  return { ...TOGGLE_RECT, ...CENTERED, text: on ? "Włączone" : "Wyłączone", text_size: px(26), color: COLOR_WHITE };
}

// Wiersze ustawień: podpis, pod nim  [-]  wartość  [+]
const ROW_Y = [146, 244, 342, 440];

export function rowLabel(index, text) {
  return { ...CENTERED, x: px(60), y: px(ROW_Y[index]), w: DEVICE_WIDTH - px(120), h: px(30), text, text_size: px(20), color: COLOR_GREY };
}

export function minusRect(index) {
  return { x: px(100), y: px(ROW_Y[index] + 34), w: px(76), h: px(56) };
}

export function plusRect(index) {
  return { x: px(304), y: px(ROW_Y[index] + 34), w: px(76), h: px(56) };
}

export function rowValue(index, text, on) {
  return {
    ...CENTERED,
    x: px(180),
    y: px(ROW_Y[index] + 34),
    w: px(120),
    h: px(56),
    text,
    text_size: px(32),
    color: on ? COLOR_WHITE : COLOR_GREY,
  };
}

// Odsłanianie zdjęcia: podpis i przełącznik (stuknięcie zmienia: ręka lub stuknięcie ↔ tylko stuknięcie)
const REVEAL_Y = 538;
const REVEAL_RECT = { x: px(80), y: px(REVEAL_Y + 34), w: DEVICE_WIDTH - px(160), h: px(56) };

export const REVEAL_LABEL_STYLE = { ...rowLabel(0, "Odsłanianie zdjęcia"), y: px(REVEAL_Y) };

export function revealBg() {
  return { ...REVEAL_RECT, radius: px(28), color: 0x333333 };
}

export function revealValue(text) {
  return { ...REVEAL_RECT, ...CENTERED, text, text_size: px(24), color: COLOR_WHITE };
}

// Najbliższe pokazy (przewijane pod wierszami ustawień)
export const STATUS_STYLE = {
  x: px(60),
  y: px(642),
  w: DEVICE_WIDTH - px(120),
  h: px(250),
  text: "",
  text_size: px(19),
  color: COLOR_WHITE,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.TOP,
  text_style: hmUI.text_style.WRAP,
};

export const TEST_RECT = { x: px(110), y: px(900), w: DEVICE_WIDTH - px(220), h: px(54) };

// Pod spodem pusty pas, żeby ostatni przycisk dało się przewinąć na środek okrągłego ekranu
export const BOTTOM_SPACER = { x: 0, y: px(960), w: DEVICE_WIDTH, h: px(140), color: 0x000000 };
