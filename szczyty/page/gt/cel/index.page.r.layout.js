import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const COLOR_TEXT = 0xffffff;
export const COLOR_GREY = 0x9a9a9a;
export const COLOR_ORANGE = 0xff9100;
export const COLOR_TAB_ON = 0x2e7d32;
export const COLOR_TAB_OFF = 0x262626;
const COLOR_ROW = 0x1c1c1c;
const COLOR_OFF_ROW = 0x4a1c1c;

const W = DEVICE_WIDTH;

const text = (x, y, w, h, size, color, extra) => ({
  x: px(x),
  y: px(y),
  w: px(w),
  h: px(h),
  text: "",
  text_size: px(size),
  color,
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
  text_style: hmUI.text_style.NONE,
  ...extra,
});

export const TITLE_STYLE = text(140, 20, 200, 40, 30, COLOR_ORANGE, { text: "Cel" });

// Zakładki: najbliższe | najwybitniejsze
const TAB = (x) => ({ x: px(x), y: px(66), w: px(150), h: px(44) });
export const TAB_NEAR = TAB(86);
export const TAB_TOP = TAB(244);
export const tabBg = (rect, on) => ({ ...rect, radius: px(22), color: on ? COLOR_TAB_ON : COLOR_TAB_OFF });
export const tabText = (rect, label) => ({ ...text(0, 0, 0, 0, 21, COLOR_TEXT), ...rect, text: label });

export const MSG_STYLE = text(60, 190, 360, 140, 24, COLOR_GREY, { text_style: hmUI.text_style.WRAP });

// Lista: systemowa SCROLL_LIST (jak w Na szczycie) - nazwa po lewej, km i m n.p.m. po prawej
const LIST_X = px(40);
const LIST_W = W - px(80);
const LIST_Y = px(122);
const ITEM_H = px(64);
export const TYPE_OFF = 1;
export const TYPE_PEAK = 2;

function itemConfig(typeId, bg, nameColor) {
  return {
    type_id: typeId,
    item_bg_color: bg,
    item_bg_radius: px(18),
    text_view: [
      { x: px(18), y: px(4), w: LIST_W - px(128), h: ITEM_H - px(8), key: "name", color: nameColor, text_size: px(23) },
      { x: LIST_W - px(108), y: px(6), w: px(96), h: px(26), key: "km", color: COLOR_TEXT, text_size: px(20) },
      { x: LIST_W - px(108), y: px(32), w: px(96), h: px(26), key: "ele", color: COLOR_GREY, text_size: px(18) },
    ],
    text_view_count: 3,
    item_height: ITEM_H,
  };
}

// data = [{ name, km, ele }]; offFirst = pierwsza pozycja to "wyłącz naprowadzanie"
export function listProps(data, offFirst, onClick) {
  const runs = [];
  if (offFirst) runs.push({ start: 0, end: 0, type_id: TYPE_OFF });
  if (data.length > (offFirst ? 1 : 0)) runs.push({ start: offFirst ? 1 : 0, end: data.length - 1, type_id: TYPE_PEAK });
  return {
    x: LIST_X,
    y: LIST_Y,
    w: LIST_W,
    h: DEVICE_HEIGHT - LIST_Y,
    item_space: px(8),
    item_config: [itemConfig(TYPE_OFF, COLOR_OFF_ROW, COLOR_TEXT), itemConfig(TYPE_PEAK, COLOR_ROW, COLOR_TEXT)],
    item_config_count: 2,
    data_array: data,
    data_count: data.length,
    data_type_config: runs,
    data_type_config_count: runs.length,
    item_click_func: (list, index) => onClick(index),
  };
}
