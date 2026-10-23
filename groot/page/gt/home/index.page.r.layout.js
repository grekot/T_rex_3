// Ekran główny (px projektu 480): duży Groot na środku na tle sceny z filmów, pierścień
// ikon akcji wokół (położenie ikon w utils/geometry.js). Komunikat nad głową, imię i nazwa
// akcji na dole między dolnymi ikonami.
import { HOME, ICON, ZZZ } from "../../../utils/geometry";

// stopy na wysokości ok. 366 px (klatka HOME, stopy na 160/168 wysokości klatki)
export const PET_X = 240 - HOME / 2;
export const PET_Y = 366 - Math.round((HOME * 160) / 168);

// dwa wiersze - mieszczą się tłumaczenia Rocketa i nazwy planet
export const STATUS = { x: 96, y: 90, w: 288, h: 56, size: 20, wrap: true };
export const TITLE = { x: 170, y: 366, w: 140, h: 28, size: 20 };
export const ACTION = { x: 170, y: 396, w: 140, h: 32, size: 20 };

// Opadłe liście wokół stóp (lewy górny róg obrazka 48 px)
export const POOPS = [
  { x: 334, y: 300 },
  { x: 100, y: 300 },
  { x: 330, y: 248 },
  { x: 104, y: 248 },
];
export const ALERT = { x: 116, y: 150 };
export const SKULL = { x: 116, y: 202 };
export const ZZZ_POS = { x: 310, y: 146 };
export const FOOD = { x: 316, y: 198 };
// Dymek prośby o zabawę (w miejscu "Zzz" - prośby są tylko na jawie)
export const BUBBLE = { x: 310, y: 146 };
// Przycisk gry o premię - w miejscu nazwy akcji (na czas oferty nazwa znika)
export const OFFER_BTN = { x: 178, y: 394, w: 124, h: 34, size: 16, text: "Gra o premię ›", color: 0x4a3a1c };
export const ICON_SIZE = ICON;
export const ZZZ_SIZE = ZZZ;
