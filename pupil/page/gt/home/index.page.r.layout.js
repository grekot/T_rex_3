// Ekran główny (px projektu 480): dinozaur na środku, pierścień ikon akcji wokół
// (położenie ikon w utils/geometry.js), napisy nad i pod dinozaurem.
import { SPRITE, ICON, ZZZ } from "../../../utils/geometry";

export const PET = { cx: 240, cy: 232 };
export const PET_X = PET.cx - SPRITE / 2;
export const PET_Y = PET.cy - SPRITE / 2;

export const TITLE = { x: 110, y: 102, w: 260, h: 40, size: 24 };
export const STATUS = { x: 90, y: 318, w: 300, h: 40, size: 28 };
export const ACTION = { x: 170, y: 404, w: 140, h: 40, size: 24 };

// Kupy wokół stóp (lewy górny róg obrazka 48 px)
export const POOPS = [
  { x: 324, y: 272 },
  { x: 108, y: 272 },
  { x: 332, y: 222 },
  { x: 100, y: 222 },
];
export const ALERT = { x: 112, y: 150 };
export const SKULL = { x: 112, y: 202 };
export const ZZZ_POS = { x: 320, y: 150 };
export const FOOD = { x: 324, y: 196 };
// Dymek prośby o zabawę (w miejscu "Zzz" - prośby są tylko na jawie)
export const BUBBLE = { x: 320, y: 150 };
// Przycisk gry o premię - między dolnymi ikonami pierścienia
export const OFFER_BTN = { x: 178, y: 362, w: 124, h: 36, size: 16, text: "Gra o premię ›", color: 0x4a3a1c };
export const ICON_SIZE = ICON;
export const ZZZ_SIZE = ZZZ;
