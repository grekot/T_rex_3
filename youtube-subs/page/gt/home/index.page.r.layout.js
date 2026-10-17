import * as hmUI from "@zos/ui";
import { getDeviceInfo } from "@zos/device";
import { px } from "@zos/utils";

export const { width: DEVICE_WIDTH, height: DEVICE_HEIGHT } = getDeviceInfo();

export const COLOR_WHITE = 0xffffff;
export const COLOR_GREY = 0x8a8a8a;
export const COLOR_DARK = 0x444444;
export const COLOR_RED = 0xff0000;
export const COLOR_ORANGE = 0xff9100;

const CENTERED = {
  align_h: hmUI.align.CENTER_H,
  align_v: hmUI.align.CENTER_V,
};

// Nagłówek u góry, wspólny dla wszystkich ekranów ("YouTube", "OSTATNI FILM", ...)
export const TITLE_STYLE = {
  ...CENTERED,
  x: 0,
  y: px(30),
  w: DEVICE_WIDTH,
  h: px(36),
  text: "",
  text_size: px(26),
  char_space: px(2),
  color: COLOR_RED,
  text_style: hmUI.text_style.NONE,
};

// --- ekran 1: kanał ---

export const CHANNEL_STYLE = {
  ...CENTERED,
  x: px(80),
  y: px(68),
  w: DEVICE_WIDTH - px(160),
  h: px(36),
  text: "",
  text_size: px(24),
  color: COLOR_GREY,
  text_style: hmUI.text_style.ELLIPSIS,
};

export const COUNT_STYLE = {
  ...CENTERED,
  x: 0,
  y: px(130),
  w: DEVICE_WIDTH,
  h: px(120),
  text: "",
  text_size: px(88),
  color: COLOR_WHITE,
  text_style: hmUI.text_style.NONE,
};

export const LABEL_STYLE = {
  ...CENTERED,
  x: 0,
  y: px(248),
  w: DEVICE_WIDTH,
  h: px(36),
  text: "",
  text_size: px(26),
  color: COLOR_WHITE,
  text_style: hmUI.text_style.NONE,
};

export const DETAILS_STYLE = {
  ...CENTERED,
  x: 0,
  y: px(300),
  w: DEVICE_WIDTH,
  h: px(32),
  text: "",
  text_size: px(22),
  color: COLOR_GREY,
  text_style: hmUI.text_style.NONE,
};

// --- ekrany 2 i 3: ostatni film / ostatni short (te same widżety, inne dane) ---

export const VIDEO_TITLE_STYLE = {
  ...CENTERED,
  x: px(70),
  y: px(70),
  w: DEVICE_WIDTH - px(140),
  h: px(70),
  text: "",
  text_size: px(24),
  color: COLOR_WHITE,
  text_style: hmUI.text_style.WRAP,
};

export const VIDEO_COUNT_STYLE = {
  ...CENTERED,
  x: 0,
  y: px(140),
  w: DEVICE_WIDTH,
  h: px(100),
  text: "",
  text_size: px(72),
  color: COLOR_WHITE,
  text_style: hmUI.text_style.NONE,
};

export const VIDEO_LABEL_STYLE = {
  ...CENTERED,
  x: 0,
  y: px(240),
  w: DEVICE_WIDTH,
  h: px(32),
  text: "",
  text_size: px(24),
  color: COLOR_WHITE,
  text_style: hmUI.text_style.NONE,
};

// Siatka 2 x 2 "ikona + wartość": polubienia, komentarze / data publikacji, długość
export const COLOR_VALUE = 0xdddddd;

const STAT_ROWS = [px(284), px(322)];
const STAT_COLS = [px(100), px(270)];
const ICON_SIZE = px(28);
const ICON_GAP = px(6);
const STAT_TEXT_W = px(120);
const STAT_TEXT_H = px(32);

// Kolejność komórek: 0 polubienia, 1 komentarze, 2 data, 3 długość
export const STAT_ICONS = ["icons/like.png", "icons/comment.png", "icons/calendar.png", "icons/duration.png"];

function statCell(index) {
  return { x: STAT_COLS[index % 2], y: STAT_ROWS[Math.floor(index / 2)] };
}

export function statIconProps(index) {
  const c = statCell(index);
  return { x: c.x, y: c.y + (STAT_TEXT_H - ICON_SIZE) / 2, src: STAT_ICONS[index] };
}

export function statTextStyle(index) {
  const c = statCell(index);
  return {
    x: c.x + ICON_SIZE + ICON_GAP,
    y: c.y,
    w: STAT_TEXT_W,
    h: STAT_TEXT_H,
    text: "",
    text_size: px(22),
    color: COLOR_VALUE,
    align_h: hmUI.align.LEFT,
    align_v: hmUI.align.CENTER_V,
    text_style: hmUI.text_style.NONE,
  };
}

// --- wspólne: status na dole i kropki wskaźnika ekranu ---

// Dolna linia jest wąska (łuk tarczy), więc tekst zawija się w 2 linie
export const STATUS_STYLE = {
  ...CENTERED,
  x: px(100),
  y: px(372),
  w: DEVICE_WIDTH - px(200),
  h: px(64),
  text: "",
  text_size: px(20),
  color: COLOR_GREY,
  text_style: hmUI.text_style.WRAP,
};

const DOT_Y = px(452);
const DOT_RADIUS = px(4);
const DOT_GAP = px(18);

export function dotProps(index, total, active) {
  return {
    center_x: DEVICE_WIDTH / 2 + (index - (total - 1) / 2) * DOT_GAP,
    center_y: DOT_Y,
    radius: DOT_RADIUS,
    color: active ? COLOR_WHITE : COLOR_DARK,
  };
}
