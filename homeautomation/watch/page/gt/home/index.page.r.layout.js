import * as hmUI from "@zos/ui";
import { getDeviceInfo, SCREEN_SHAPE_SQUARE } from "@zos/device";
import { px } from "@zos/utils";
import { GEOMETRY } from "../../../utils/layout";

const info = getDeviceInfo();
export const DEVICE_WIDTH = info.width;
export const DEVICE_HEIGHT = info.height;
// ekran do układu kafelków (utils/layout.js) - kwadratowy tylko, gdy system tak mówi
export const SCREEN = {
  width: DEVICE_WIDTH,
  height: DEVICE_HEIGHT,
  shape: SCREEN_SHAPE_SQUARE !== undefined && info.screenShape === SCREEN_SHAPE_SQUARE ? "square" : "round",
};
// wymiary układu w pikselach tego ekranu (projekt na 480)
export const GEOMETRY_PX = {};
Object.keys(GEOMETRY).forEach((k) => {
  GEOMETRY_PX[k] = px(GEOMETRY[k]);
});

export const COLOR_TEXT = 0xffffff;
export const COLOR_GREY = 0x8a8a8a;
export const COLOR_ORANGE = 0xff9100;
export const COLOR_RED = 0xff5252;
export const COLOR_ROW = 0x1c1c1c;
export const COLOR_ON = 0xe67e00;
export const COLOR_OFF = 0x333333;
export const COLOR_BTN = 0x333333;

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
const left = { align_h: hmUI.align.LEFT, text_style: hmUI.text_style.ELLIPSIS };

export const TITLE_STYLE = text(px(90), px(24), DEVICE_WIDTH - px(180), px(34), px(24), COLOR_ORANGE, {
  text_style: hmUI.text_style.ELLIPSIS,
});
// Telefon niedostępny / Wysyłanie...
export const STATUS_STYLE = text(px(100), px(58), DEVICE_WIDTH - px(200), px(26), px(18), COLOR_GREY);
// Ekran bez kafelków: logowanie, brak konfiguracji, łączenie...
export const CENTER_STYLE = text(px(60), px(120), DEVICE_WIDTH - px(120), px(240), px(28), COLOR_TEXT, {
  text_style: hmUI.text_style.WRAP,
});

export function headerStyle(b) {
  return text(b.x + px(12), b.y, b.w - px(24), b.h, px(20), COLOR_GREY, { ...left, text: b.text });
}

// Części kafelka według rozmiaru (half / full / big). buttons = − / + w kafelku stepper,
// badge = miejsce na znacznik w prawym górnym rogu (ochrona termostatu: MRÓZ / AWARYJNIE),
// icon = plik ikony (assets/gt.r/icons/<icon>.png) przed nazwą albo null.
export function tileParts(b, buttons, badge, icon) {
  const parts = tilePartsNoIcon(b, buttons, badge);
  if (!icon) return { ...parts, icon: null };
  const { x, y } = b;
  const size = px(28); // jeden rozmiar - obrazki 28x28 (tools/gen_assets.py)
  const ix = x + (b.size === "half" ? px(12) : px(20));
  const iy = y + (b.size === "big" ? px(12) : buttons ? px(5) : b.size === "half" ? px(8) : px(12));
  const shift = size + px(8);
  // nazwa przesuwa się w prawo o ikonę (w big jest na środku - tylko węższa z obu stron)
  const name =
    b.size === "big"
      ? { ...parts.name, x: parts.name.x + shift, w: Math.max(px(40), parts.name.w - 2 * shift) }
      : { ...parts.name, x: parts.name.x + shift - (b.size === "half" ? 0 : px(4)), w: Math.max(px(40), parts.name.w - shift) };
  return { ...parts, name, icon: { x: ix, y: iy, w: size, h: size, src: "icons/" + icon + ".png" } };
}

function tilePartsNoIcon(b, buttons, badge) {
  const { x, y, w, h } = b;
  const bg = { x, y, w, h, radius: px(24), color: COLOR_ROW };
  const right = { align_h: hmUI.align.RIGHT };
  if (b.size === "half") {
    const pill = { x: x + w - px(12) - px(60), y: y + px(44), w: px(60), h: px(34), radius: px(17), color: COLOR_OFF };
    return {
      bg,
      name: text(x + px(14), y + px(6), w - px(28) - (badge ? px(72) : 0), px(32), px(20), COLOR_TEXT, left),
      badge: badge ? text(x + w - px(12) - px(72), y + px(8), px(72), px(26), px(14), COLOR_ORANGE, right) : null,
      sub: null,
      value: text(x + px(14), y + px(36), w - px(28), px(46), px(30), COLOR_TEXT, left),
      smallValue: px(18),
      pill,
      pillText: text(pill.x, pill.y, pill.w, pill.h, px(18), COLOR_TEXT),
      minus: null,
      plus: null,
    };
  }
  if (b.size === "big") {
    const r = px(34);
    const cy = y + px(86);
    return {
      bg,
      name: badge
        ? text(x + px(130), y + px(10), w - px(260), px(32), px(22), COLOR_TEXT, { text_style: hmUI.text_style.ELLIPSIS })
        : text(x + px(20), y + px(10), w - px(40), px(32), px(22), COLOR_TEXT, { text_style: hmUI.text_style.ELLIPSIS }),
      badge: badge ? text(x + w - px(130), y + px(12), px(104), px(26), px(16), COLOR_ORANGE, right) : null,
      value: buttons
        ? text(x + px(90), y + px(44), w - px(180), px(84), px(56), COLOR_TEXT)
        : text(x + px(20), y + px(44), w - px(40), px(84), px(64), COLOR_TEXT),
      smallValue: px(30),
      sub: text(x + px(20), y + px(132), w - px(40), px(30), px(20), COLOR_GREY, { text_style: hmUI.text_style.ELLIPSIS }),
      pill: null,
      pillText: null,
      minus: buttons ? roundButton(x + px(50), cy, r, "−") : null,
      plus: buttons ? roundButton(x + w - px(50), cy, r, "+") : null,
    };
  }
  // full
  if (buttons) {
    const r = px(24);
    const cy = y + px(58);
    return {
      bg,
      name: text(x + px(24), y + px(4), w - px(48), px(30), px(20), COLOR_TEXT, left),
      badge: null,
      sub: null,
      value: text(x + px(70), y + px(32), w - px(140), px(52), px(34), COLOR_TEXT),
      smallValue: px(18),
      pill: null,
      pillText: null,
      minus: roundButton(x + px(40), cy, r, "−"),
      plus: roundButton(x + w - px(40), cy, r, "+"),
    };
  }
  const pill = { x: x + w - px(22) - px(78), y: y + (h - px(40)) / 2, w: px(78), h: px(40), radius: px(20), color: COLOR_OFF };
  return {
    bg,
    name: text(x + px(24), y + px(6), w - px(150), px(40), px(26), COLOR_TEXT, left),
    badge: badge ? text(x + w - px(130), y + px(4), px(108), px(22), px(14), COLOR_ORANGE, right) : null,
    sub: text(x + px(24), y + px(44), w - px(150), px(30), px(18), COLOR_GREY, left),
    value: text(x + w - px(140), y, px(118), h, px(34), COLOR_TEXT, { align_h: hmUI.align.RIGHT }),
    smallValue: px(18),
    pill,
    pillText: text(pill.x, pill.y, pill.w, pill.h, px(22), COLOR_TEXT),
    minus: null,
    plus: null,
  };
}

function roundButton(cx, cy, r, label) {
  return {
    circle: { center_x: cx, center_y: cy, radius: r, color: COLOR_BTN },
    text: text(cx - r, cy - r, 2 * r, 2 * r, Math.round(r * 1.3), COLOR_ORANGE, { text: label }),
  };
}

// Miejsce pod listą, żeby ostatni kafelek dało się przewinąć
export function bottomSpacer(y, h) {
  return { x: 0, y, w: DEVICE_WIDTH, h, color: 0x000000 };
}
