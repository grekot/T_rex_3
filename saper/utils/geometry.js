// WYGENEROWANE przez tools/gen_assets.py - nie edytuj ręcznie, zmieniaj generator.
// Współrzędne w px dla ekranu 480 x 480 (strona dosuwa je na środek innych ekranów).

export const SCREEN = 480;

// active: "1" = pole w grze, "0" = pole wycięte (wystaje poza okrągły ekran)
export const LEVELS = [
  {
    "id": "easy",
    "name": "Łatwy",
    "cols": 6,
    "rows": 6,
    "mines": 5,
    "cell": 60,
    "x": 60,
    "y": 60,
    "active": "011110111111111111111111111111011110"
  },
  {
    "id": "medium",
    "name": "Średni",
    "cols": 8,
    "rows": 8,
    "mines": 10,
    "cell": 45,
    "x": 60,
    "y": 60,
    "active": "0111111011111111111111111111111111111111111111111111111101111110"
  },
  {
    "id": "hard",
    "name": "Trudny",
    "cols": 9,
    "rows": 9,
    "mines": 15,
    "cell": 40,
    "x": 60,
    "y": 60,
    "active": "011111110111111111111111111111111111111111111111111111111111111111111111011111110"
  }
];

export const UI = {
  "smiley": {
    "x": 216,
    "y": 7,
    "w": 48,
    "h": 48
  },
  "mineIcon": {
    "x": 15,
    "y": 196,
    "w": 30,
    "h": 30
  },
  "mineText": {
    "x": 2,
    "y": 228,
    "w": 56,
    "h": 40
  },
  "clockIcon": {
    "x": 435,
    "y": 196,
    "w": 30,
    "h": 30
  },
  "timeText": {
    "x": 422,
    "y": 228,
    "w": 56,
    "h": 40
  },
  "mode": {
    "x": 170,
    "y": 425,
    "w": 140,
    "h": 44
  }
};
