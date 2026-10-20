import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const COLOR_TEXT = 0xffffff;
export const COLOR_GREY = 0x8a8a8a;
export const COLOR_ORANGE = 0xff9100;
export const COLOR_PILL = 0x262626;
export const COLOR_BUTTON = 0xe67e00;

// Kolory kości: [ścianka, cień pod spodem, oczka/cyfra]
export const DIE_COLORS = {
  6: [0xf4f4f4, 0x9e9e9e, 0x1c1c1c],
  4: [0x43a047, 0x1b5e20, 0xffffff],
  8: [0x1e88e5, 0x0d47a1, 0xffffff],
  10: [0x8e24aa, 0x4a148c, 0xffffff],
  12: [0xc62828, 0x7f0000, 0xffffff],
  20: [0x00897b, 0x004d40, 0xffffff],
};
// Zatrzymana kość
export const LOCKED_COLORS = [0xff9100, 0xa35d00, 0x1c1c1c];
// Jedno oczko na K6 jest czerwone (jak na klasycznych kościach)
export const PIP_ONE_COLOR = 0xd32f2f;

const CX = DEVICE_WIDTH / 2;

const CENTERED = {
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

// Przycisk ustawień u góry: "2 × K6 ›"
const CONFIG_RECT = { x: CX - px(95), y: px(28), w: px(190), h: px(50) };
export const CONFIG_BG = { ...CONFIG_RECT, radius: px(25), color: COLOR_PILL };
export const CONFIG_STYLE = { ...CENTERED, ...CONFIG_RECT, text: "", text_size: px(26), color: COLOR_TEXT };

// Geometria jednej kości z projektu 480 px (środek, bok) -> widżety
export function dieGeometry(d) {
  const size = px(d.size);
  const x = Math.round(px(d.cx) - size / 2);
  const y = Math.round(px(d.cy) - size / 2);
  const radius = Math.round(size * 0.18);
  const pipR = Math.round(size * 0.09);
  const off = Math.round(size * 0.27);
  return {
    face: { x, y, w: size, h: size, radius },
    shadow: { x, y: y + Math.round(size * 0.06), w: size, h: size, radius },
    pip(spot) {
      return { center_x: Math.round(x + size / 2 + spot[0] * off), center_y: Math.round(y + size / 2 + spot[1] * off), radius: pipR };
    },
    text: { ...CENTERED, x, y, w: size, h: size, text: "", text_size: Math.round(size * 0.5) },
  };
}

export const SUMMARY_STYLE = {
  ...CENTERED,
  x: px(60),
  y: px(340),
  w: DEVICE_WIDTH - px(120),
  h: px(38),
  text: "",
  text_size: px(30),
  color: COLOR_TEXT,
};

export const PREV_STYLE = {
  ...CENTERED,
  x: px(80),
  y: px(376),
  w: DEVICE_WIDTH - px(160),
  h: px(26),
  text: "",
  text_size: px(20),
  color: COLOR_GREY,
};

const ROLL_RECT = { x: CX - px(95), y: px(406), w: px(190), h: px(48) };
export const ROLL_BG = { ...ROLL_RECT, radius: px(24), color: COLOR_BUTTON };
export const ROLL_STYLE = { ...CENTERED, ...ROLL_RECT, text: "RZUĆ", text_size: px(28), color: COLOR_TEXT };
