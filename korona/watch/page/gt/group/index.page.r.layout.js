import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";
import { COLOR_WHITE, COLOR_GREY, COLOR_GREEN, COLOR_ORANGE, COLOR_ROW, COLOR_TRACK } from "../../../utils/ui";

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

export const NAME_STYLE = text(px(80), px(22), DEVICE_WIDTH - px(160), px(32), px(22), COLOR_ORANGE, {
  text_style: hmUI.text_style.ELLIPSIS,
});
export const COUNT_STYLE = text(0, px(52), DEVICE_WIDTH, px(56), px(46), COLOR_WHITE);

const BAR_W = px(220);
export const BAR_TRACK = { x: (DEVICE_WIDTH - BAR_W) / 2, y: px(112), w: BAR_W, h: px(8), radius: px(4), color: COLOR_TRACK };
export function barFill(done, total) {
  return { ...BAR_TRACK, w: Math.max(px(8), Math.round((BAR_W * done) / Math.max(1, total))), color: COLOR_ORANGE };
}

const NEAR_W = px(190);
export const NEAREST_RECT = { x: (DEVICE_WIDTH - NEAR_W) / 2, y: px(128), w: NEAR_W, h: px(44) };

export const EMPTY_STYLE = text(px(70), px(220), DEVICE_WIDTH - px(140), px(160), px(22), COLOR_GREY, {
  text_style: hmUI.text_style.WRAP,
});

// Lista szczytów: systemowa SCROLL_LIST (setki pozycji bez setek widżetów)
const LIST_X = px(40);
const LIST_W = DEVICE_WIDTH - px(80);
const ITEM_H = px(66);
const LIST_Y = px(184);

export const TYPE_CLIMBED = 1;
export const TYPE_TODO = 2;

function itemConfig(typeId, nameColor, rightColor) {
  return {
    type_id: typeId,
    item_bg_color: COLOR_ROW,
    item_bg_radius: px(18),
    text_view: [
      { x: px(20), y: px(4), w: LIST_W - px(150), h: ITEM_H - px(8), key: "name", color: nameColor, text_size: px(24) },
      { x: LIST_W - px(128), y: px(4), w: px(116), h: ITEM_H - px(8), key: "right", color: rightColor, text_size: px(19) },
    ],
    text_view_count: 2,
    item_height: ITEM_H,
  };
}

// data = [{ name, right }], climbedCount = ile pierwszych pozycji to zdobyte
export function listProps(data, climbedCount, onClick) {
  const runs = [];
  if (climbedCount > 0) runs.push({ start: 0, end: climbedCount - 1, type_id: TYPE_CLIMBED });
  if (data.length > climbedCount) runs.push({ start: climbedCount, end: data.length - 1, type_id: TYPE_TODO });
  return {
    x: LIST_X,
    y: LIST_Y,
    w: LIST_W,
    h: DEVICE_HEIGHT - LIST_Y,
    item_space: px(8),
    item_config: [itemConfig(TYPE_CLIMBED, COLOR_WHITE, COLOR_GREEN), itemConfig(TYPE_TODO, COLOR_GREY, COLOR_GREY)],
    item_config_count: 2,
    data_array: data,
    data_count: data.length,
    data_type_config: runs,
    data_type_config_count: runs.length,
    item_click_func: (list, index) => onClick(index),
  };
}
