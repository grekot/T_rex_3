import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const COLOR_TEXT = 0xffffff;
export const COLOR_GREY = 0x9a9a9a;
export const COLOR_DIM = 0x5c5c5c;
export const COLOR_ORANGE = 0xff9100;
export const COLOR_FROZEN = 0x4fc3f7;
export const COLOR_PILL = 0x262626;

const W = DEVICE_WIDTH;

const text = (y, h, size, color, extra) => ({
  x: px(50),
  y: px(y),
  w: W - px(100),
  h: px(h),
  text: "",
  text_size: px(size),
  color,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
  ...extra,
});

// Kierunek 12:00 u góry: "213° Pd-Zach"
export const TOP_STYLE = text(30, 40, 30, COLOR_ORANGE, { x: px(90), w: W - px(180) });
// GPS / ostatnia pozycja / wysokość
export const STATUS_STYLE = text(70, 28, 20, COLOR_GREY, { x: px(70), w: W - px(140) });
// Nazwa szczytu - duża, do dwóch linii
export const NAME_STYLE = text(102, 112, 42, COLOR_TEXT, { x: px(40), w: W - px(80), text_style: hmUI.text_style.WRAP });
// "1725 m · 38 km"
export const DETAILS_STYLE = text(214, 42, 34, COLOR_TEXT);
// "kierunek 216° · 3° w prawo"
export const HINT_STYLE = text(256, 30, 21, COLOR_GREY, { x: px(40), w: W - px(80) });

// Pasek horyzontu: -30°..+30° na 360 px, linia horyzontu na y=346
export const STRIP = { cx: 240, half: 180, baseY: 346, pxPerElev: 5, elevMin: -2, elevMax: 8 };
export const STRIP_LINE = { x: px(60), y: px(STRIP.baseY), w: px(360), h: px(2), color: COLOR_DIM };
export const STRIP_MARK = { x: px(239), y: px(292), w: px(2), h: px(60), color: COLOR_ORANGE };
export const PEAK_ICON = { w: 24, h: 16 }; // assets/gt.r/peak.png i peak_best.png

// Pozycja ikony szczytu na pasku (offset w stopniach, kąt wzniesienia)
export function stripIconPos(off, elev) {
  const e = Math.max(STRIP.elevMin, Math.min(STRIP.elevMax, elev));
  const cx = STRIP.cx + (off / 30) * STRIP.half;
  const bottom = STRIP.baseY - (e - STRIP.elevMin) * STRIP.pxPerElev;
  return { x: px(Math.round(cx - PEAK_ICON.w / 2)), y: px(Math.round(bottom - PEAK_ICON.h)) };
}

// Sąsiedzi: "‹ Pilsko 14°" po lewej, "Romanka 9° ›" po prawej (strzałki to obrazki)
export const LEFT_ARROW = { x: px(52), y: px(363), src: "arrow_left.png" };
export const RIGHT_ARROW = { x: px(414), y: px(363), src: "arrow_right.png" };
export const LEFT_STYLE = text(356, 30, 21, COLOR_TEXT, {
  x: px(70),
  w: px(168),
  align_h: hmUI.align.LEFT,
});
export const RIGHT_STYLE = text(356, 30, 21, COLOR_TEXT, {
  x: px(242),
  w: px(168),
  align_h: hmUI.align.RIGHT,
});
// "za nim: Rysy 2499 m"
export const BEHIND_STYLE = text(388, 28, 19, COLOR_GREY, { x: px(80), w: W - px(160) });

// Przycisk informacji na dole
const INFO_RECT = { x: W / 2 - px(24), y: px(420), w: px(48), h: px(40) };
export const INFO_BG = { ...INFO_RECT, radius: px(20), color: COLOR_PILL };
export const INFO_STYLE = { ...text(0, 0, 26, COLOR_GREY), ...INFO_RECT, text: "i" };

// Duży czarny (niewidoczny na czarnym tle) obszar na środku: stuknięcie = zatrzymaj / wznów.
// Rysowany pierwszy, teksty na nim mają ten sam odbiornik.
export const FREEZE_AREA = { x: px(40), y: px(100), w: W - px(80), h: px(186), color: 0x000000 };
