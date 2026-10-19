import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";
import { COLOR_WHITE, COLOR_ORANGE } from "../../../utils/ui";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const TITLE_STYLE = {
  x: 0,
  y: px(26),
  w: DEVICE_WIDTH,
  h: px(40),
  text: "POWIADOMIENIA",
  text_size: px(28),
  char_space: px(1),
  color: COLOR_ORANGE,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
};

export const STATUS_STYLE = {
  x: px(52),
  y: px(66),
  w: DEVICE_WIDTH - px(104),
  h: px(158),
  text: "",
  text_size: px(18),
  color: COLOR_WHITE,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.WRAP,
};

export function methodRect(index) {
  return { x: px(70), y: px(228) + index * px(62), w: DEVICE_WIDTH - px(140), h: px(54) };
}

export const NOW_RECT = { x: px(110), y: px(476), w: DEVICE_WIDTH - px(220), h: px(50) };

// Pod spodem pusty pas, żeby ostatni przycisk dało się przewinąć na środek okrągłego ekranu
export const BOTTOM_SPACER = { x: 0, y: px(532), w: DEVICE_WIDTH, h: px(110), color: 0x000000 };
