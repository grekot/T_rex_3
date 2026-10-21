// Balans na kłodzie (px projektu 480)
import { SPRITE, LOG } from "../../../utils/geometry";

export const TITLE = { x: 100, y: 30, w: 280, h: 44, size: 30 };
export const HINT = { x: 60, y: 76, w: 360, h: 34, size: 22 };
export const LOG_POS = { x: 240 - LOG.w / 2, y: 290 };
export const PET = { x: 240 - SPRITE / 2, y: 290 - SPRITE + 6, range: LOG.w / 2 };
export const TIME = { x: 120, y: 336, w: 240, h: 36, size: 26 };
