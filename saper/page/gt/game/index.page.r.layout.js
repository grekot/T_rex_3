import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

// Współrzędne w utils/geometry.js są dla ekranu 480 x 480. Na innych zegarkach zeus
// skaluje grafikę w tej samej proporcji, więc pozycje przeliczamy przez px().
export function scaled(rect) {
  return { x: px(rect.x), y: px(rect.y), w: px(rect.w), h: px(rect.h) };
}

// Prostokąt pola o indeksie i
export function cellRect(level, i) {
  return scaled({
    x: level.x + (i % level.cols) * level.cell,
    y: level.y + Math.floor(i / level.cols) * level.cell,
    w: level.cell,
    h: level.cell,
  });
}

export const COLOR_TEXT = 0xffffff;
export const COLOR_WIN = 0x5fd068;
export const COLOR_LOST = 0xff5a4e;

export const COUNTER_STYLE = {
  text: "",
  text_size: px(28),
  color: COLOR_TEXT,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
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
