// Statystyki (px projektu 480): trzy rzędy serc, potem waga, wiek, forma, przycisk kolekcji.
export const TITLE = { x: 120, y: 34, w: 240, h: 44, size: 32 };
export const HEART_ROWS = [
  { label: "Woda", y: 96, full: "ui/drop.png", empty: "ui/drop_empty.png" },
  { label: "Humor", y: 146, full: "ui/heart.png", empty: "ui/heart_empty.png" },
  { label: "Dyscyplina", y: 196, full: "ui/heart.png", empty: "ui/heart_empty.png" },
];
// od etapu dziecka zamiast kropli wody: słoneczka energii
export const HUNGER_FREE = { full: "ui/sunpt.png", empty: "ui/sunpt_empty.png" };
export const ROW_LABEL = { x: 56, w: 150, h: 36, size: 24 };
export const HEARTS_X = 214; // pierwsze serce, kolejne co 46 px
export const HEART_STEP = 46;
export const INFO = [
  { x: 70, y: 248, w: 340, h: 34, size: 24 },
  { x: 70, y: 282, w: 340, h: 34, size: 24 },
  { x: 70, y: 316, w: 340, h: 34, size: 24 },
];
export const NAME_BTN = { x: 84, y: 356, w: 150, h: 50, size: 24, text: "Imię ›" };
export const COLLECTION_BTN = { x: 246, y: 356, w: 150, h: 50, size: 24, text: "Kolekcja ›" };
// podróż Milano po planetach - kroki z zegarka (strona Galaktyka)
export const GALAXY_BTN = { x: 150, y: 412, w: 180, h: 46, size: 24, text: "Podróż ›" };
